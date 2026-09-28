#!/bin/bash
# imageserver - dev stack menu: nginx proxy + WordPress + MariaDB + wp-cli

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CFG="$DIR/dockers/docker-compose.yml"

PREFIX="imageserver"
SVC_PROXY="proxy"
SVC_APP="wordpress"
SVC_DB="db"
SVC_WPCLI="wpcli"
APP="${PREFIX}_${SVC_APP}"
DB="${PREFIX}_${SVC_DB}"

PORT="${IMAGESERVER_PORT:-8080}"
URL="http://127.0.0.1:${PORT}"
DB_NAME="${WORDPRESS_DB_NAME:-imageserver}"
DB_USER="${WORDPRESS_DB_USER:-imageserver}"
DB_PASS="${WORDPRESS_DB_PASSWORD:-imageserver}"
DB_ROOT_PASS="${MARIADB_ROOT_PASSWORD:-imageserver-root}"

DUMP_DIR="$DIR/dumps"
WP_TITLE="Image Server Test"
WP_USER="admin"
WP_PASS="admin"
WP_EMAIL="admin@example.com"

[ -f "$CFG" ] || { echo "Missing compose file: $CFG"; exit 1; }

dc() {
  docker compose -f "$CFG" "$@"
}

confirm() {
  local reply
  read -rp "$1 [y/N] " reply
  case "$reply" in
    [Yy]*) return 0 ;;
    *) echo "Cancelled."; return 1 ;;
  esac
}

stack_up() {
  docker ps --filter "name=${PREFIX}_" --filter "status=running" -q 2>/dev/null | grep -q .
}

start_stack() {
  echo "Starting proxy, WordPress and MariaDB ..."
  dc up -d "$SVC_PROXY" "$SVC_APP" "$SVC_DB"
  echo ""
  echo "WordPress: $URL"
  echo "If it is not installed yet, run task 9."
}

status_stack() {
  echo "== Containers =="
  docker ps -a --filter "name=${PREFIX}_" --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
  echo ""
  echo "== Compose config =="
  echo "  file: $CFG"
  echo "  url:  $URL"
  echo ""
  echo "== Plugin visibility =="
  local first
  first="$(compgen -G "$DIR/*.php" 2>/dev/null | head -1)"
  if [ -n "$first" ]; then
    echo "  ok - $(basename "$first") found at the plugin-dir root"
  else
    echo "  WARNING: no .php file at $DIR"
    echo "  The compose file mounts the repo root as wp-content/plugins/imageserver, and"
    echo "  WordPress only detects a plugin whose main file sits at that root."
  fi
}

stop_stack() {
  echo "Stopping (containers and volumes are kept) ..."
  dc stop
  echo "Stopped."
}

restart_stack() {
  dc stop
  dc up -d "$SVC_PROXY" "$SVC_APP" "$SVC_DB"
  echo "Restarted. WordPress: $URL"
}

enter_app() {
  stack_up || { echo "Stack is not running - start it with task 1 first."; return 1; }
  echo "Entering $APP ('exit' leaves) ..."
  docker exec -it "$APP" bash
}

enter_db() {
  stack_up || { echo "Stack is not running - start it with task 1 first."; return 1; }
  echo "Entering $DB as root ('exit' leaves) ..."
  docker exec -it "$DB" mariadb -u root -p"$DB_ROOT_PASS"
}

db_root() {
  docker exec -i "$DB" mariadb -u root -p"$DB_ROOT_PASS" "$@"
}

export_db() {
  stack_up || { echo "Stack is not running - start it with task 1 first."; return 1; }
  mkdir -p "$DUMP_DIR" || return 1
  local stamp out
  stamp="$(date +%Y%m%d-%H%M%S)"
  out="$DUMP_DIR/${PREFIX}-${stamp}.sql.gz"
  echo "Dumping $DB_NAME ..."
  if docker exec "$DB" sh -c 'command -v mariadb-dump >/dev/null && echo yes' | grep -q yes; then
    docker exec "$DB" mariadb-dump -u"$DB_USER" -p"$DB_PASS" --single-transaction "$DB_NAME" | gzip > "$out"
  else
    docker exec "$DB" mysqldump -u"$DB_USER" -p"$DB_PASS" --single-transaction "$DB_NAME" | gzip > "$out"
  fi
  [ -s "$out" ] || { echo "Dump failed or empty: $out"; return 1; }
  echo "Wrote $out ($(du -h "$out" | cut -f1))"
}

list_dumps() {
  find "$DUMP_DIR" -maxdepth 1 -type f -name '*.sql.gz' -printf '%T@ %p\n' 2>/dev/null | sort -rn | cut -d' ' -f2-
}

import_db() {
  local file dumps
  [ -d "$DUMP_DIR" ] || { echo "No dumps in $DUMP_DIR - export one with task 7 first."; return 1; }
  dumps="$(list_dumps)"
  if [ -z "$dumps" ]; then
    echo "No dumps in $DUMP_DIR - export one with task 7 first."
    return 1
  fi
  echo "Available dumps (newest first):"
  while read -r file; do
    printf '  %s  %s\n' "$(du -h "$file" | cut -f1)" "$(basename "$file")"
  done <<< "$dumps"
  read -rp "Dump to import (name): " file
  file="$DUMP_DIR/$(basename "$file")"
  [ -f "$file" ] || { echo "No such dump: $file"; return 1; }
  echo "This DROPS and recreates '$DB_NAME' on $DB, wiping all current data."
  confirm "Continue?" || return 1
  echo "Stopping $SVC_APP ..."
  dc stop "$SVC_APP"
  echo "Recreating $DB_NAME ..."
  db_root -e "DROP DATABASE IF EXISTS \`$DB_NAME\`; CREATE DATABASE \`$DB_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" || return 1
  echo "Restoring $(basename "$file") ..."
  gunzip -c "$file" | docker exec -i "$DB" mariadb -u"$DB_USER" -p"$DB_PASS" "$DB_NAME" || {
    echo "Restore failed - the database is currently empty."
    dc up -d "$SVC_APP"
    return 1
  }
  dc up -d "$SVC_APP"
  echo "Imported. WordPress: $URL"
}

wpcli() {
  stack_up || { echo "Stack is not running - start it with task 1 first."; return 1; }
  dc run --rm "$SVC_WPCLI" wp "$@"
}

setup_site() {
  stack_up || { echo "Stack is not running - start it with task 1 first."; return 1; }
  echo "== WordPress core =="
  if dc run --rm "$SVC_WPCLI" core is-installed >/dev/null 2>&1; then
    echo "  already installed - skipping"
  else
    dc run --rm "$SVC_WPCLI" core install \
      --url="$URL" \
      --title="$WP_TITLE" \
      --admin_user="$WP_USER" \
      --admin_password="$WP_PASS" \
      --admin_email="$WP_EMAIL" \
      --skip-email || return 1
  fi
  echo "== WooCommerce =="
  if dc run --rm "$SVC_WPCLI" plugin is-installed woocommerce >/dev/null 2>&1; then
    echo "  already installed"
    dc run --rm "$SVC_WPCLI" plugin activate woocommerce
  else
    dc run --rm "$SVC_WPCLI" plugin install woocommerce --activate || return 1
  fi
  echo "== Image Server plugin =="
  dc run --rm "$SVC_WPCLI" plugin activate imageserver || return 1
  echo ""
  echo "Done. $URL  (login $WP_USER / $WP_PASS)"
  echo "Settings live under Settings -> Image Server."
}

remove_containers() {
  echo "Removing containers and networks, keeping volumes ..."
  dc down
  echo "Done. Data volumes (${PREFIX}_wordpress_data, ${PREFIX}_db_data) are intact."
}

remove_all() {
  echo "This removes the containers AND the database volumes - all local data is lost."
  confirm "Really remove containers and volumes?" || return 1
  dc down -v
  echo "Done. WordPress must be reinstalled with task 9."
}

while true; do
  echo ""
  echo "imageserver - $URL"
  echo "  1  Run - start the stack"
  echo "  2  Status - containers, url, plugin visibility"
  echo "  3  Stop - stop the stack (containers stay)"
  echo "  4  Restart - restart the stack"
  echo "  5  Enter WordPress container"
  echo "  6  Enter DB (mariadb, root)"
  echo "  7  Export DB - dump to dumps/"
  echo "  8  Import DB - drop + reload DB from a dump"
  echo "  9  Setup site - install WordPress, WooCommerce, activate plugin"
  echo "  10 Remove containers (keeps volumes)"
  echo "  11 Remove containers AND volumes (destructive - wipes data)"
  echo "  12 wp-cli - run a wp command, e.g. 12 plugin list"
  echo "  0  Exit"
  if ! read -rp "Task: " task; then
    break
  fi
  case "$task" in
    1) start_stack ;;
    2) status_stack ;;
    3) stop_stack ;;
    4) restart_stack ;;
    5) enter_app ;;
    6) enter_db ;;
    7) export_db ;;
    8) import_db ;;
    9) setup_site ;;
    10) remove_containers ;;
    11) remove_all ;;
    12) read -rp "wp arguments: " -a wp_args; wpcli "${wp_args[@]}" ;;
    0) break ;;
    *) echo "Unknown task" ;;
  esac
done
exit 0
