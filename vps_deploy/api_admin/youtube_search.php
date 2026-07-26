<?php
/**
 * GET /api/admin/youtube_search.php?q=texto&limit=10
 *   → { ok, results: [{id, title, uploader, duration, thumbnail}] }
 *
 * Busca en YouTube usando yt-dlp ytsearchN:query. Sirve para el picker de
 * "reemplazar YT" en el UI iOS: el owner escribe "despacito official" y
 * ve los top 10 videos con miniatura + duración para elegir.
 *
 * El PREVIEW real (audio 15s) se sirve desde /api/yt_proxy.php?id=... con
 * Range 0-500000 (~15s de audio a 128kbps).
 */
declare(strict_types=1);
require_once __DIR__ . '/admin_lib.php';
if ($_SERVER['REQUEST_METHOD'] !== 'GET') admin_json_err(405, 'method_not_allowed');
auth_require_admin();
set_time_limit(30);

$q = trim((string)($_GET['q'] ?? ''));
if ($q === '') admin_json_err(400, 'missing_query');
$limit = max(1, min(20, (int)($_GET['limit'] ?? 10)));

$cookieDir = '/var/www/vhosts/temazo.es/private/cookies';
$cookies = glob("$cookieDir/owner_*.txt") ?: [];
shuffle($cookies);
$cookieArg = $cookies ? ('--cookies ' . escapeshellarg($cookies[0]) . ' ') : '';

$cmd = '/usr/local/bin/yt-dlp ' . $cookieArg .
       '--dump-json --flat-playlist --no-warnings ' .
       escapeshellarg("ytsearch${limit}:$q") . ' 2>&1';
$out = @shell_exec($cmd);
$lines = array_filter(array_map('trim', explode("\n", (string)$out)));

$results = [];
foreach ($lines as $l) {
    $j = json_decode($l, true);
    if (!is_array($j) || empty($j['id']) || !admin_yt_id_valid($j['id'])) continue;
    $thumb = null;
    if (!empty($j['thumbnails']) && is_array($j['thumbnails'])) {
        usort($j['thumbnails'], fn($a, $b) => (int)($b['width'] ?? 0) - (int)($a['width'] ?? 0));
        $thumb = $j['thumbnails'][0]['url'] ?? null;
    }
    if (!$thumb && !empty($j['thumbnail'])) $thumb = $j['thumbnail'];
    $results[] = [
        'id' => $j['id'],
        'title' => $j['title'] ?? '',
        'uploader' => $j['uploader'] ?? $j['channel'] ?? '',
        'duration' => isset($j['duration']) ? (int)$j['duration'] : null,
        'view_count' => isset($j['view_count']) ? (int)$j['view_count'] : null,
        'thumbnail' => $thumb,
    ];
    if (count($results) >= $limit) break;
}

admin_json_ok(['query' => $q, 'count' => count($results), 'results' => $results]);
