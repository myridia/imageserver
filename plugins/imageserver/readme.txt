=== Image Server ===
Contributors: veto
Tags: woocommerce, images, media
Requires at least: 6.7
Tested up to: 7.1
Requires PHP: 8.2
Stable tag: 1.0.0
License: GPL-3.0-or-later
License URI: https://www.gnu.org/licenses/gpl-3.0.html
Short description: Rewrites WooCommerce product, variation, gallery, catalog, cart and email image URLs to point at an external image server.

Serve WooCommerce product images from an external image server instead of the WordPress media library.

== Description ==

This plugin rewrites the image markup that WooCommerce already produces, so that
the `src`, `srcset`, `data-thumb` and `href` attributes point at an external
image server instead of the local media library.

It does not upload, copy or proxy any image file. Only the URLs inside the
markup are changed, so the plugin does not add a second copy of an image and
does not slow down page loads.

The plugin covers the product image, the gallery, the variation image, the
catalog listing, the cart and the order emails.

== Where the image paths come from ==

The paths are not stored by this plugin. They are written to the product and
variation meta by the separate product sync:

* a product carries the meta key `picture_paths`
* a variation carries the meta key `picture_path`, and falls back to the
  `picture_paths` of its parent product when it is empty

Both keys may hold a JSON array, a PHP array or a string delimited by `;`,
`,` or `|`. Values may be relative paths or complete `http(s)://` URLs; a
complete URL is used unchanged.

If a product has no such meta, the plugin returns the original WooCommerce
markup untouched, so products without synced paths keep working as they are.

== Settings ==

Open Settings -> Image Server. The page has four fields:

* `enabled` - the checkbox that registers the filters. When it is off, the
  plugin does nothing at all.
* `source` - the base URL of the image server, for example
  `https://img.example.com`. A trailing slash is removed.
* `original_pattern` - the path pattern used when no size is passed, for
  example `/img/{path}`.
* `resize_pattern` - the path pattern used for a resized image, for example
  `/canvas/{size}/{path}`.

`{path}` is replaced with the image path and `{size}` with the WooCommerce
image size. Each path segment is URL encoded, so spaces and other characters
are escaped correctly. A pattern that is missing `{path}` gets it appended, and
a pattern without a leading `/` gets one, so a pattern can never be used to
leave the image server host.

== Installation ==

1. Copy the `imageserver` directory into `/wp-content/plugins/`, or install the
   plugin from the Plugins screen.
2. Activate the plugin through the Plugins menu in WordPress.
3. Open Settings -> Image Server and fill in the image server source and the
   two path patterns.
4. Check a product page, a category listing, the cart and a WooCommerce order
   email to confirm the images now point at the image server.

== Frequently Asked Questions ==

= Are the images uploaded anywhere? =

No. The plugin only rewrites URLs. The image files stay where they are and are
served by the image server.

= What happens to a product without synced image paths? =

Nothing. The original WooCommerce image markup is returned unchanged.

= Why is a `srcset` reduced to a single entry? =

The image server serves a resized image at the requested size, so the
WooCommerce `srcset` candidates, which all point at local derivative files,
are replaced by one entry at that size.

== Changelog ==

= 1.0.0 =
* First release.
