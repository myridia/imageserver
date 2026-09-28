#!/bin/bash
# imageserver - dev stack menu: nginx proxy + WordPress + MariaDB + wp-cli

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CFG="$DIR/dockers/docker-compose.yml"

PREFIX="imageserver"
SVC_PROXY="nginx-proxy"
SVC_APP="wordpress"
SVC_DB="db"
SVC_WPCLI="wpcli"
SVC_PMA="phpmyadmin"
APP="${PREFIX}_${SVC_APP}"
DB="${PREFIX}_${SVC_DB}"

HTTP_PORT="${IMAGESERVER_HTTP_PORT:-80}"
HTTPS_PORT="${IMAGESERVER_HTTPS_PORT:-443}"
PMA_PORT="${IMAGESERVER_PMA_PORT:-8081}"
HOST="www.app.local"
PMA_HOSTNAME="phpmyadmin.app.local"
URL="https://${HOST}"
PMA_URL="https://${PMA_HOSTNAME}"
PMA_PLAIN_URL="http://127.0.0.1:${PMA_PORT}"
CERT_DIR="$DIR/dockers/certs/_.app.local"
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

install_trusted_cert() {
  local src
  for src in "${IMAGESERVER_CERT_SRC:-}" \
    /home/veto/webs/gitlab/tibellus/dockers/certs/_.app.local \
    /home/veto/webs/gitlab/exobank/dockers/certs/_.app.local; do
    [ -n "$src" ] || continue
    [ -f "$src/${HOST}.crt" ] || continue
    mkdir -p "$CERT_DIR" || return 1
    cp "$src/${HOST}.crt" "$CERT_DIR/${HOST}.crt" || return 1
    cp "$src/${HOST}.key" "$CERT_DIR/${HOST}.key" || return 1
    cp "$src/${HOST}.crt" "$CERT_DIR/${PMA_HOSTNAME}.crt" || return 1
    cp "$src/${HOST}.key" "$CERT_DIR/${PMA_HOSTNAME}.key" || return 1
    chmod 644 "$CERT_DIR"/*.crt
    chmod 600 "$CERT_DIR"/*.key
    echo "  installed the shared *.app.local cert from $src"
    echo "  it is issued by 'minica root ca', which your browser already trusts"
    return 0
  done
  return 1
}

setup_tls() {
  local names="127.0.0.1 ${HOST} ${PMA_HOSTNAME}"
  if grep -q "${HOST}" /etc/hosts 2>/dev/null && grep -q "${PMA_HOSTNAME}" /etc/hosts 2>/dev/null; then
    echo "  /etc/hosts already resolves ${HOST} and ${PMA_HOSTNAME}"
  elif printf '%s\n' "$names" | sudo tee -a /etc/hosts >/dev/null 2>&1; then
    echo "  appended '${names}' to /etc/hosts"
  elif printf '%s\n' "$names" >>/etc/hosts 2>/dev/null; then
    echo "  appended '${names}' to /etc/hosts"
  else
    echo "  WARNING: cannot edit /etc/hosts - add this line yourself:"
    echo "           ${names}"
  fi

  if [ -f "$CERT_DIR/${HOST}.crt" ] && [ -f "$CERT_DIR/${PMA_HOSTNAME}.crt" ]; then
    echo "  cert already present in dockers/certs/_.app.local"
    echo "  issuer: $(openssl x509 -in "$CERT_DIR/${HOST}.crt" -noout -issuer 2>/dev/null | cut -d= -f2-)"
    return 0
  fi
  install_trusted_cert && return 0
  mkdir -p "$CERT_DIR" || return 1
  echo "  no trusted cert source found - generating a self-signed one"
  echo "  (browsers and curl will reject it until you trust it or set IMAGESERVER_CERT_SRC)"
  echo "  generating self-signed wildcard cert for *.app.local ..."
  if ! openssl req -x509 -nodes -newkey rsa:2048 -days 825 \
    -subj "/CN=*.app.local" \
    -addext "subjectAltName=DNS:*.app.local" \
    -keyout "$CERT_DIR/app.local.key" -out "$CERT_DIR/app.local.crt" 2>/dev/null; then
    echo "  WARNING: openssl failed (needs 1.1.1+ for -addext) - generate the cert yourself"
    return 1
  fi
  local host
  for host in "$HOST" "$PMA_HOSTNAME"; do
    cp "$CERT_DIR/app.local.crt" "$CERT_DIR/${host}.crt"
    cp "$CERT_DIR/app.local.key" "$CERT_DIR/${host}.key"
  done
  chmod 644 "$CERT_DIR"/*.crt
  chmod 600 "$CERT_DIR"/*.key
  echo "  cert written to dockers/certs/_.app.local (gitignored)"
  echo "  your browser will warn once - accept the certificate for both names"
}

start_foreground() {
  echo "Configuring TLS hosts and cert ..."
  setup_tls
  echo ""
  echo "Starting in the foreground - logs stream here, Ctrl+C stops the stack ..."
  echo ""
  dc up
  echo ""
  echo "Stack stopped. Restart it with task 2 when you are ready."
}

start_background() {
  echo "Configuring TLS hosts and cert ..."
  setup_tls
  echo ""
  echo "Starting nginx-proxy, WordPress, MariaDB and phpMyAdmin in the background ..."
  dc up -d "$SVC_PROXY" "$SVC_APP" "$SVC_DB" "$SVC_PMA"
  echo ""
  echo "WordPress:  $URL"
  echo "phpMyAdmin: $PMA_URL (root / $DB_ROOT_PASS)"
  echo "            plain http fallback: $PMA_PLAIN_URL"
  echo "If WordPress is not installed yet, run task 10."
}

status_stack() {
  echo "== Containers =="
  docker ps -a --filter "name=${PREFIX}_" --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
  echo ""
  echo "== Compose config =="
  echo "  file: $CFG"
  echo "  url:  $URL"
  echo "  bind: http :${HTTP_PORT}  https :${HTTPS_PORT}  pma :${PMA_PORT} (127.0.0.1 only)"
  echo ""
  echo "== Host port holders =="
  local port holders
  for port in "$HTTP_PORT" "$HTTPS_PORT" "$PMA_PORT"; do
    holders="$(docker ps --filter "publish=$port" --format '{{.Names}}' 2>/dev/null | tr '\n' ' ')"
    printf '  :%-5s %s\n' "$port" "${holders:-free}"
  done
  echo "  pma:  $PMA_URL (root / $DB_ROOT_PASS)"
  echo "        plain http: $PMA_PLAIN_URL"
  echo ""
  echo "== TLS =="
  if [ -f "$CERT_DIR/${HOST}.crt" ] && [ -f "$CERT_DIR/${PMA_HOSTNAME}.crt" ]; then
    echo "  cert ok - $(openssl x509 -in "$CERT_DIR/${HOST}.crt" -noout -enddate 2>/dev/null)"
  else
    echo "  no cert yet - run task 1 to generate one"
  fi
  if grep -q "${PMA_HOSTNAME}" /etc/hosts 2>/dev/null; then
    echo "  hosts ok - $(grep "${PMA_HOSTNAME}" /etc/hosts | head -1)"
  else
    echo "  WARNING: ${PMA_HOSTNAME} missing from /etc/hosts - run task 1"
  fi
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
  dc up -d "$SVC_PROXY" "$SVC_APP" "$SVC_DB" "$SVC_PMA"
  echo "Restarted. WordPress: $URL  phpMyAdmin: $PMA_URL"
}

enter_app() {
  stack_up || { echo "Stack is not running - start it with task 1 (foreground) or 2 (background) first."; return 1; }
  echo "Entering $APP ('exit' leaves) ..."
  docker exec -it "$APP" bash
}

enter_db() {
  stack_up || { echo "Stack is not running - start it with task 1 (foreground) or 2 (background) first."; return 1; }
  echo "Entering $DB as root ('exit' leaves) ..."
  docker exec -it "$DB" mariadb -u root -p"$DB_ROOT_PASS"
}

db_root() {
  docker exec -i "$DB" mariadb -u root -p"$DB_ROOT_PASS" "$@"
}

export_db() {
  stack_up || { echo "Stack is not running - start it with task 1 (foreground) or 2 (background) first."; return 1; }
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
  [ -d "$DUMP_DIR" ] || { echo "No dumps in $DUMP_DIR - export one with task 8 first."; return 1; }
  dumps="$(list_dumps)"
  if [ -z "$dumps" ]; then
    echo "No dumps in $DUMP_DIR - export one with task 8 first."
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
  stack_up || { echo "Stack is not running - start it with task 1 (foreground) or 2 (background) first."; return 1; }
  dc run --rm "$SVC_WPCLI" wp "$@"
}

setup_site() {
  stack_up || { echo "Stack is not running - start it with task 1 (foreground) or 2 (background) first."; return 1; }
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
  echo "Done. WordPress must be reinstalled with task 10."
}

while true; do
  echo ""
  echo "imageserver - $URL   (phpMyAdmin $PMA_URL)"
  echo "  1  Run (foreground) - start the stack and stream logs, Ctrl+C stops it"
  echo "  2  Run (background) - start the stack detached"
  echo "  3  Status - containers, url, TLS, plugin visibility"
  echo "  4  Stop - stop the stack (containers stay)"
  echo "  5  Restart - restart the stack"
  echo "  6  Enter WordPress container"
  echo "  7  Enter DB (mariadb, root)"
  echo "  8  Export DB - dump to dumps/"
  echo "  9  Import DB - drop + reload DB from a dump"
  echo " 10  Setup site - install WordPress, WooCommerce, activate plugin"
  echo " 11  wp-cli - run a wp command, e.g. 11 plugin list"
  echo " 12  Remove containers (keeps volumes)"
  echo " 13  Remove containers AND volumes (destructive - wipes data)"
  echo "  0  Exit"
  if ! read -rp "Task: " task; then
    break
  fi
  case "$task" in
    1) start_foreground ;;
    2) start_background ;;
    3) status_stack ;;
    4) stop_stack ;;
    5) restart_stack ;;
    6) enter_app ;;
    7) enter_db ;;
    8) export_db ;;
    9) import_db ;;
    10) setup_site ;;
    11) read -rp "wp arguments: " -a wp_args; wpcli "${wp_args[@]}" ;;
    12) remove_containers ;;
    13) remove_all ;;
    0) break ;;
    *) echo "Unknown task" ;;
  esac
done
exit 0
