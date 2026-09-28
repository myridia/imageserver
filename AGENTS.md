# AGENTS.md — imageserver

## What this is
WordPress plugin (PHP 8.2, WordPress 6.7+) that rewrites WooCommerce product image HTML to point at an external image server. It does not upload, proxy, or copy files — it only rewrites URLs in the markup WooCommerce already produced. Namespace `Salamander\Imageserver`, classes `IS_Admin` and `IS_Frontend`.

## Layout
```
imageserver/imageserver.php          plugin header, constants, autoloader, bootstrap
imageserver/src/Class/IS_Admin.php   settings page, option + sanitization, defaults
imageserver/src/Class/IS_Frontend.php WooCommerce filters, meta reading, URL building
test/docker-compose.yml              nginx proxy + WordPress + MariaDB + wpcli (profile: setup)
test/nginx/default.conf              reverse proxy to wordpress:80, 64m body cap
```

## Autoloading — KNOWN BUG, plugin does not load
`imageserver.php` maps `Salamander\Imageserver\X` → `IMAGESERVER_PLUGIN_DIR . 'src/' . 'X' . '.php'`, but the classes live in `src/Class/`. There is no `composer.json`, so nothing else provides the mapping. `is_readable()` therefore fails, neither class is ever loaded, and `imageserver_init()` fatals with "Class not found" on every request — including activation, since `register_activation_hook` references `IS_Admin::activate`. The fix is to add the missing `Class/` segment in the autoloader's `$file` (or move the classes to `src/`). Verify the plugin loads at all before debugging anything else.

## Settings
Single option `imageserver_settings` (array), page at Settings → Image Server, capability `manage_options`, registered on `admin_init` with a `sanitize_callback`.
- `enabled` — checkbox, default `1`; when off, no filters are registered at all.
- `source` — base URL, default `https://img.salamander-jewelry.net`, run through `esc_url_raw` + `untrailingslashit`.
- `original_pattern` — default `/img/{path}`; used when no size is passed.
- `resize_pattern` — default `/canvas/{size}/{path}`.
- `sanitize_pattern()` appends `{path}` if missing and force-prefixes a leading `/`, so a pattern can never escape the source host.

## Data source
Meta written by the syncer, not by this plugin:
- product: `picture_paths` (plural)
- variation: `picture_path` (singular), falling back to the parent's `picture_paths` when empty.

`collect_paths()` accepts a JSON array, a real array, or a delimited string (`;`, `,`, `|`), trims, drops empties, and de-dupes. Paths may be absolute `http(s)://` URLs, which are passed through untouched; otherwise each segment is `rawurlencode`d and appended to `source + pattern`. `{size}` is `rawurlencode`d.

## Hooks (IS_Frontend::register)
Bails early when `is_admin() && !wp_doing_ajax()`, when WooCommerce is absent, or when disabled. Otherwise:
`woocommerce_single_product_image_thumbnail_html`, `woocommerce_gallery_thumbnail_html`, `woocommerce_catalog_product_thumbnail`, `woocommerce_cart_item_thumbnail`, `woocommerce_email_order_item_thumbnail`, `woocommerce_variation_image_html` — all at priority 10.

`rewrite_html()` replaces `src`, `data-thumb`, `href` and rewrites `srcset` to a single `1x` entry, using a regex callback so the original quote style is preserved. If the meta is missing, the index does not exist, or the HTML has no `<img`, the original HTML is returned untouched — preserve that fallback in any change.

Gallery index comes from `array_search($attachment_id, get_gallery_image_ids())` and is 1-based (index 0 is the main image); an unknown id falls back to index 0.

## Test stack
Only nginx is published, on `${IMAGESERVER_PORT:-8080}` (default `127.0.0.1:8080`). The repo root is bind-mounted read-only into the plugin dir, so edits on the host are live in the container with no rebuild.

```bash
docker compose -f test/docker-compose.yml up -d proxy wordpress db
docker compose -f test/docker-compose.yml run --rm wpcli core install \
  --url=http://127.0.0.1:8080 --title='Image Server Test' \
  --admin_user=admin --admin_password=admin --admin_email=admin@example.com --skip-email
docker compose -f test/docker-compose.yml run --rm wpcli plugin install woocommerce --activate
docker compose -f test/docker-compose.yml run --rm wpcli plugin activate imageserver
docker compose -f test/docker-compose.yml down
```

`wpcli` is behind `profiles: [setup]` so it never starts with the main stack. DB credentials come from `WORDPRESS_DB_*` / `MARIADB_ROOT_PASSWORD` env vars, all defaulting to `imageserver` / `imageserver-root` — test-only values, never reuse them. There is no unit test suite; verification is the stack plus manual checks in wp-admin and on a product page.

## Conventions
- Escape on output (`esc_url`, `esc_attr`, `esc_html`, `esc_url_raw`) and sanitize on input; never read `$_POST` directly.
- Resolve products defensively — `global $product`, `wc_get_product()`, and the filter's own `$product`/`$product_id` argument are all different shapes across these hooks, which is why `resolve_product()` exists.
- Keep the "no meta → return original HTML" behaviour.
- No comments in code unless asked.
- Do not run git-modifying commands or commit; the user commits.
- Do not commit credentials or real customer/image data.
- `.gitignore` is the WordPress template: safe to add real WP files to a checkout, but never commit `wp-config.php` or `wp-content/uploads/`.

## Verify
- `php -l imageserver/imageserver.php imageserver/src/Class/*.php` — note the agent container has no PHP, so ask the user to run it if unavailable.
- `docker compose -f test/docker-compose.yml config` to validate the stack.
- Manual: activate the plugin (this is where the autoloader bug surfaces), then check a product page, a category listing, cart, and a WooCommerce email for rewritten URLs.
