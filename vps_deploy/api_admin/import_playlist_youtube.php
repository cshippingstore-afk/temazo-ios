<?php
/**
 * POST /api/admin/import_playlist_youtube.php
 * Body: { playlist_url: "https://youtube.com/playlist?list=..." }
 *
 * Extrae todos los video IDs de la playlist con yt-dlp --flat-playlist,
 * y los encola para importarlos uno a uno (background). Devuelve el
 * conteo y un task_id para monitorear.
 *
 * Log: /tmp/_import_playlist_<task_id>.log
 */
declare(strict_types=1);
require_once __DIR__ . '/admin_lib.php';
if ($_SERVER['REQUEST_METHOD'] !== 'POST') admin_json_err(405, 'method_not_allowed');
$u = auth_require_admin();

set_time_limit(60);
$in = admin_json_input();
$url = admin_get_str($in, 'playlist_url', 500);
if (!preg_match('~[?&]list=([A-Za-z0-9_-]+)~', $url, $m)) {
    admin_json_err(400, 'invalid_playlist_url', 'URL debe contener ?list=PLAYLIST_ID');
}
$listId = $m[1];

// Cookie pool para bypass LOGIN_REQUIRED
$cookieDir = '/var/www/vhosts/temazo.es/private/cookies';
$cookies = glob("$cookieDir/owner_*.txt") ?: [];
shuffle($cookies);
$cookieArg = $cookies ? ('--cookies ' . escapeshellarg($cookies[0]) . ' ') : '';

// Flat playlist para sacar solo IDs (rápido)
$cmd = '/usr/local/bin/yt-dlp ' . $cookieArg .
       '--flat-playlist --print id --no-warnings ' .
       escapeshellarg("https://www.youtube.com/playlist?list=$listId") . ' 2>&1';
$out = @shell_exec($cmd);
$lines = array_filter(array_map('trim', explode("\n", (string)$out)));
$ids = array_values(array_filter($lines, fn($l) => admin_yt_id_valid($l)));
if (empty($ids)) admin_json_err(502, 'playlist_empty_or_failed', substr((string)$out, 0, 200));

// Guardar cola en archivo + lanzar worker background
$taskId = bin2hex(random_bytes(6));
$queueFile = "/tmp/_import_playlist_$taskId.queue";
file_put_contents($queueFile, implode("\n", $ids));

// Worker script inline (llama import_youtube.php via php CLI para cada id)
$workerCmd = "nohup bash -c '" .
    "while IFS= read -r vid; do " .
    "  /usr/bin/php " . escapeshellarg(__DIR__ . '/_import_single_yt.php') . " \"\$vid\" " . (int)$u['id'] . " " .
    "  sleep 2 " .   // pacing anti-rate-limit
    "done < " . escapeshellarg($queueFile) . " > " . escapeshellarg("/tmp/_import_playlist_$taskId.log") . " 2>&1'  &";
@shell_exec($workerCmd);

admin_log('import_playlist_youtube', 'playlist', null, null,
    ['list_id' => $listId, 'count' => count($ids), 'task_id' => $taskId]);
admin_json_ok(['task_id' => $taskId, 'list_id' => $listId, 'total_tracks' => count($ids),
               'log_file' => "/tmp/_import_playlist_$taskId.log"]);
