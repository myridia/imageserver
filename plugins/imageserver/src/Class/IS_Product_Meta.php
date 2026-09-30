<?php

namespace Salamander\Imageserver;

class IS_Product_Meta
{
    public const PRODUCT_KEY = 'picture_paths';
    public const VARIATION_KEY = 'picture_path';
    public const PRODUCT_FIELD = self::PRODUCT_KEY;
    public const VARIATION_FIELD = 'variable_picture_path';
    public const NONCE_FIELD = 'imageserver_meta_nonce';
    public const NONCE_ACTION = 'imageserver_save_picture_paths';

    public function register()
    {
        add_action('init', [$this, 'register_meta_keys']);

        if (!is_admin()) {
            return;
        }

        add_action('add_meta_boxes', [$this, 'add_meta_box']);
        add_action('woocommerce_process_product_meta', [$this, 'save_product'], 30, 1);
        add_action('woocommerce_product_after_variable_attributes', [$this, 'render_variation_field'], 10, 3);
        add_action('woocommerce_save_product_variation', [$this, 'save_variation'], 10, 2);
    }

    public function register_meta_keys()
    {
        $auth = function ($allowed, $meta_key, $post_id) {
            return current_user_can('edit_post', $post_id);
        };

        register_post_meta('product', self::PRODUCT_KEY, [
            'type' => 'string',
            'single' => true,
            'show_in_rest' => true,
            'auth_callback' => $auth,
        ]);

        register_post_meta('product_variation', self::VARIATION_KEY, [
            'type' => 'string',
            'single' => true,
            'show_in_rest' => true,
            'auth_callback' => $auth,
        ]);
    }

    public function add_meta_box()
    {
        add_meta_box(
            'imageserver-picture-paths',
            'Image server paths',
            [$this, 'render_meta_box'],
            'product',
            'normal',
            'default'
        );
    }

    public function render_meta_box($post)
    {
        wp_nonce_field(self::NONCE_ACTION, self::NONCE_FIELD);

        $paths = $this->normalize_paths(get_post_meta($post->ID, self::PRODUCT_KEY, true));
        ?>
        <p>
            One image server path per line, in <code>category/name</code> form, for example
            <code>BC/BCSB51.png</code>. Leave empty when the product has no image server images.
        </p>
        <textarea
            name="<?php echo esc_attr(self::PRODUCT_FIELD); ?>"
            id="imageserver-<?php echo esc_attr(self::PRODUCT_FIELD); ?>"
            rows="6"
            class="large-text code"
            spellcheck="false"
        ><?php echo esc_textarea(implode("\n", $paths)); ?></textarea>
        <p class="description">
            The product sync writes this key, so values entered here are replaced on the next sync of
            this product.
        </p>
        <?php
    }

    public function save_product($post_id)
    {
        $post_id = (int) $post_id;

        if (!$post_id || !current_user_can('edit_post', $post_id)) {
            return;
        }

        if (!isset($_POST[self::NONCE_FIELD])) {
            return;
        }

        $nonce = sanitize_text_field(wp_unslash($_POST[self::NONCE_FIELD]));

        if (!wp_verify_nonce($nonce, self::NONCE_ACTION)) {
            return;
        }

        $raw = isset($_POST[self::PRODUCT_FIELD]) ? wp_unslash($_POST[self::PRODUCT_FIELD]) : '';
        $paths = $this->normalize_paths(is_string($raw) ? $raw : '');

        if ($paths) {
            update_post_meta($post_id, self::PRODUCT_KEY, $paths);
        } else {
            delete_post_meta($post_id, self::PRODUCT_KEY);
        }
    }

    public function render_variation_field($loop, $variation_data, $variation)
    {
        $variation_id = $this->variation_id($variation);
        $paths = $variation_id ? $this->normalize_paths(get_post_meta($variation_id, self::VARIATION_KEY, true)) : [];
        $name = self::VARIATION_FIELD . '[' . (int) $loop . ']';
        ?>
        <div class="form-row form-row-full">
            <label for="<?php echo esc_attr($name); ?>">Image server path</label>
            <input
                type="text"
                class="short"
                name="<?php echo esc_attr($name); ?>"
                id="<?php echo esc_attr($name); ?>"
                value="<?php echo esc_attr(isset($paths[0]) ? $paths[0] : ''); ?>"
                placeholder="BC/BCSB51.png"
            />
        </div>
        <?php
    }

    public function save_variation($variation_id, $loop)
    {
        $variation_id = (int) $variation_id;
        $loop = (int) $loop;

        if (!$variation_id || $loop < 0) {
            return;
        }

        $parent_id = (int) get_post_field('post_parent', $variation_id);

        if (!$parent_id || !current_user_can('edit_post', $parent_id)) {
            return;
        }

        $key = self::VARIATION_FIELD . '[' . $loop . ']';
        $raw = isset($_POST[self::VARIATION_FIELD][$loop]) ? wp_unslash($_POST[self::VARIATION_FIELD][$loop]) : '';
        $paths = $this->normalize_paths(is_string($raw) ? $raw : '');

        if ($paths) {
            update_post_meta($variation_id, self::VARIATION_KEY, $paths[0]);
        } else {
            delete_post_meta($variation_id, self::VARIATION_KEY);
        }
    }

    private function variation_id($variation)
    {
        if (is_object($variation) && isset($variation->ID)) {
            return (int) $variation->ID;
        }

        if (is_object($variation) && method_exists($variation, 'get_id')) {
            return (int) $variation->get_id();
        }

        return 0;
    }

    private function normalize_paths($value)
    {
        if (is_string($value)) {
            $decoded = json_decode($value, true);

            if (is_array($decoded)) {
                $value = $decoded;
            } else {
                $value = preg_split('/[\r\n;,|]+/', $value);
            }
        }

        if (!is_array($value)) {
            return [];
        }

        $paths = [];

        foreach ($value as $item) {
            if (!is_string($item) && !is_numeric($item)) {
                continue;
            }

            $path = trim((string) $item);

            if ($path === '' || in_array($path, $paths, true)) {
                continue;
            }

            $paths[] = $path;
        }

        return $paths;
    }
}
