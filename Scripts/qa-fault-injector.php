<?php
// Throw-away mu-plugin for manual testing: see "Running the manual pass with an agent" in docs/testing-plan.md.
$qa_ctl_file = dirname(__DIR__) . '/qa-fault.json';
$qa_log_file = dirname(__DIR__) . '/qa-fault.log';
$qa_uri = isset($_SERVER['REQUEST_URI']) ? $_SERVER['REQUEST_URI'] : '';
$qa_is_rest = (strpos($qa_uri, '/wp-json/') !== false) || isset($_GET['rest_route']);
if ($qa_is_rest && file_exists($qa_ctl_file)) {
    $qa_ctl = json_decode(file_get_contents($qa_ctl_file), true);
    if (!is_array($qa_ctl)) { $qa_ctl = array(); }
    $qa_method = isset($_SERVER['REQUEST_METHOD']) ? $_SERVER['REQUEST_METHOD'] : '';
    if (!empty($qa_ctl['log'])) {
        @file_put_contents($qa_log_file, sprintf("%.3f %s %s\n", microtime(true), $qa_method, $qa_uri), FILE_APPEND);
    }
    $qa_match = isset($qa_ctl['match']) ? $qa_ctl['match'] : '';
    $qa_hit = ($qa_match === '' || strpos($qa_uri, $qa_match) !== false);
    if ($qa_hit && !empty($qa_ctl['method']) && $qa_ctl['method'] !== $qa_method) { $qa_hit = false; }
    if ($qa_hit) {
        if (!empty($qa_ctl['delay_ms'])) { usleep((int)$qa_ctl['delay_ms'] * 1000); }
        if (!empty($qa_ctl['status'])) {
            http_response_code((int)$qa_ctl['status']);
            header('Content-Type: application/json');
            echo json_encode(array('code' => 'qa_injected', 'message' => 'QA injected failure', 'data' => array('status' => (int)$qa_ctl['status'])));
            exit;
        }
        if (!empty($qa_ctl['warn'])) {
            add_filter('rest_pre_serve_request', function ($served) {
                echo "<br />\n<b>Warning</b>:  Undefined variable \$qa in <b>/wp-content/plugins/qa/qa.php</b> on line <b>3</b><br />\n";
                return $served;
            }, 10, 1);
        }
    }
}
