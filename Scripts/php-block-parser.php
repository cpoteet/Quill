<?php
// Runs a WordPress install's own PHP block parser over a JSON array of strings (stdin → stdout).

$includes = rtrim($argv[1], '/') . '/wp-includes/';
require $includes . 'class-wp-block-parser-block.php';
require $includes . 'class-wp-block-parser-frame.php';
require $includes . 'class-wp-block-parser.php';

$parser = new WP_Block_Parser();
$out = [];
foreach (json_decode(stream_get_contents(STDIN), true) as $html) {
  $out[] = $parser->parse($html);
}
echo json_encode($out, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE | JSON_PRESERVE_ZERO_FRACTION | JSON_INVALID_UTF8_SUBSTITUTE);
