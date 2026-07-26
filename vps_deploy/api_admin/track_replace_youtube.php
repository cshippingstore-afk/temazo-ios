<?php
/**
 * POST /api/admin/track_replace_youtube.php
 * Body JSON: { track_id: int, youtube: "URL o 11-char id", note?: string }
 *
 * Reemplaza el youtube_id de un track. Guarda el youtube_id anterior en
 * track_youtube_alternatives (is_active=0) y el nuevo con is_active=1.
 * Purga el cache local del m4a (/tmp/_yt_audio_cache/<old>.m4a).
 *
 * Auditoria en admin_actions.
 */
declare(strict_types=1);
require_once __DIR__ . '/admin_lib.php';

if ($_SERVER['REQUEST_METHOD'] !== 'POST') admin_json_err(405, 'method_not_allowed');
$u = auth_require_admin();

$in = admin_json_input();
$trackId = admin_get_int($in, 'track_id', 1);
$raw = admin_get_str($in, 'youtube', 500);
$note = isset($in['note']) ? substr(trim((string)$in['note']), 0, 500) : null;

$newYt = admin_yt_id_from_url_or_id($raw);
if (!$newYt) admin_json_err(400, 'invalid_youtube', 'Not a valid YouTube URL or id');

$track = admin_fetch_track($trackId);
if (!$track) admin_json_err(404, 'track_not_found');

$oldYt = $track['youtube_id'] ?? null;
if ($oldYt === $newYt) admin_json_err(400, 'same_youtube', 'youtube_id unchanged');

// Comprobar unicidad — youtube_id es UNIQUE en tracks
$dup = db()->prepare("SELECT id, title, artist_name FROM tracks WHERE youtube_id=? AND id<>? LIMIT 1");
$dup->execute([$newYt, $trackId]);
if ($conflict = $dup->fetch(PDO::FETCH_ASSOC)) {
    admin_json_err(409, 'youtube_in_use', 'Ese YouTube ID ya lo usa otro track', ['conflict' => $conflict]);
}

$db = db();
$db->beginTransaction();
try {
    // Marcar el youtube_id antiguo como no activo (si existia)
    if ($oldYt) {
        $db->prepare("INSERT INTO track_youtube_alternatives (track_id, youtube_id, is_active, added_by, note)
                      VALUES (?, ?, 0, ?, 'auto-archived on replace')
                      ON DUPLICATE KEY UPDATE is_active=0")
           ->execute([$trackId, $oldYt, (int)$u['id']]);
    }
    // Insertar/actualizar el nuevo como activo
    $db->prepare("INSERT INTO track_youtube_alternatives (track_id, youtube_id, is_active, added_by, note)
                  VALUES (?, ?, 1, ?, ?)
                  ON DUPLICATE KEY UPDATE is_active=1, added_by=VALUES(added_by), note=VALUES(note)")
       ->execute([$trackId, $newYt, (int)$u['id'], $note]);
    // Actualizar tracks.youtube_id + reset yt_blocked
    $db->prepare("UPDATE tracks SET youtube_id=?, yt_blocked=0, updated_at=NOW() WHERE id=?")
       ->execute([$newYt, $trackId]);
    $db->commit();
} catch (Throwable $e) {
    $db->rollBack();
    admin_json_err(500, 'db_error', $e->getMessage());
}

// Purga cache proxy del viejo (opcional del nuevo por si hubo pruebas previas)
if ($oldYt && admin_yt_id_valid($oldYt)) {
    @unlink("/tmp/_yt_audio_cache/{$oldYt}.m4a");
    @unlink("/tmp/_yt_stream_cache/{$oldYt}.url");
}
@unlink("/tmp/_yt_audio_cache/{$newYt}.m4a");
@unlink("/tmp/_yt_stream_cache/{$newYt}.url");

admin_log('replace_youtube', 'track', $trackId,
    ['youtube_id' => $oldYt],
    ['youtube_id' => $newYt],
    $note);

admin_json_ok(['track_id' => $trackId, 'youtube_id' => $newYt, 'previous' => $oldYt]);
