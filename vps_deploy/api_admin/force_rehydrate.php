<?php
/**
 * POST /api/admin/force_rehydrate.php
 * Body: { target_type: 'track'|'artist', target_id: int }
 *
 * Fuerza re-hidratación desde YouTube:
 *   - track: usa _yt_hydrate_test.py con el yt_id → refresca title/album/duration/cover
 *   - artist: usa _yt_full_artist.py → refresca tracks/albums/bio del artista
 *
 * Ejecución background (nohup + &). Devuelve inmediatamente con task_id.
 * El resultado se ve en /tmp/_rehydrate_<id>.log
 */
declare(strict_types=1);
require_once __DIR__ . '/admin_lib.php';
if ($_SERVER['REQUEST_METHOD'] !== 'POST') admin_json_err(405, 'method_not_allowed');
auth_require_admin();

$in = admin_json_input();
$type = admin_get_str($in, 'target_type', 16);
if (!in_array($type, ['track', 'artist'], true)) admin_json_err(400, 'invalid_target_type');
$id = admin_get_int($in, 'target_id', 1);

if ($type === 'track') {
    $track = admin_fetch_track($id);
    if (!$track) admin_json_err(404, 'track_not_found');
    $yt = $track['youtube_id'] ?? '';
    if (!admin_yt_id_valid($yt)) admin_json_err(400, 'track_missing_youtube_id');
    $script = '/var/www/vhosts/temazo.es/httpdocs/api/_yt_hydrate_test.py';
    $cmd = escapeshellcmd("/opt/temazo_venv/bin/python $script $id") . ' > /tmp/_rehydrate_track_' . (int)$id . '.log 2>&1 &';
} else {
    $artist = admin_fetch_artist($id);
    if (!$artist) admin_json_err(404, 'artist_not_found');
    $script = '/var/www/vhosts/temazo.es/httpdocs/api/_yt_full_artist.py';
    $cmd = escapeshellcmd("/opt/temazo_venv/bin/python $script $id") . ' > /tmp/_rehydrate_artist_' . (int)$id . '.log 2>&1 &';
}

// Ejecutar en background
@shell_exec("nohup bash -c " . escapeshellarg($cmd));

admin_log('force_rehydrate', $type, $id, null, ['queued' => true]);
admin_json_ok(['target_type' => $type, 'target_id' => $id, 'queued' => true,
               'log_file' => "/tmp/_rehydrate_${type}_${id}.log"]);
