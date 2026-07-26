<?php
/**
 * POST /api/admin/track_edit_meta.php
 * Body JSON (todos opcionales excepto track_id):
 *   { track_id: int, title?: string, artist_name?: string,
 *     release_date?: "YYYY-MM-DD" | "YYYY",
 *     cover_url?: "https://..." (imagen) | null-para-no-tocar }
 *
 * Actualiza metadata. Solo campos presentes en el body son modificados.
 * cover_url substituye cover_large; cover_medium/small quedan igual (usuario
 * puede regenerar con force-rehydrate mas tarde). Si quieres borrar la cover,
 * pasa cover_url: "" (string vacia).
 */
declare(strict_types=1);
require_once __DIR__ . '/admin_lib.php';

if ($_SERVER['REQUEST_METHOD'] !== 'POST') admin_json_err(405, 'method_not_allowed');
$u = auth_require_admin();

$in = admin_json_input();
$trackId = admin_get_int($in, 'track_id', 1);
$track = admin_fetch_track($trackId);
if (!$track) admin_json_err(404, 'track_not_found');

$updates = [];
$params = [];
$before = [];
$after = [];

if (array_key_exists('title', $in)) {
    $title = admin_get_str($in, 'title', 255);
    $updates[] = 'title=?';
    $params[] = $title;
    $before['title'] = $track['title'];
    $after['title'] = $title;
}
if (array_key_exists('artist_name', $in)) {
    $artist = admin_get_str($in, 'artist_name', 255);
    $updates[] = 'artist_name=?';
    $params[] = $artist;
    $before['artist_name'] = $track['artist_name'];
    $after['artist_name'] = $artist;
}
if (array_key_exists('release_date', $in)) {
    $rd = trim((string)$in['release_date']);
    if ($rd !== '' && !preg_match('/^\d{4}(-\d{2}-\d{2})?$/', $rd)) {
        admin_json_err(400, 'invalid_release_date', 'YYYY o YYYY-MM-DD');
    }
    $updates[] = 'release_date=?';
    $params[] = $rd === '' ? null : $rd;
    $before['release_date'] = $track['release_date'];
    $after['release_date'] = $rd === '' ? null : $rd;
}
if (array_key_exists('cover_url', $in)) {
    $cu = trim((string)$in['cover_url']);
    if ($cu !== '' && !filter_var($cu, FILTER_VALIDATE_URL)) {
        admin_json_err(400, 'invalid_cover_url');
    }
    $updates[] = 'cover_large=?';
    $params[] = $cu === '' ? null : $cu;
    $before['cover_large'] = $track['cover_large'];
    $after['cover_large'] = $cu === '' ? null : $cu;
}

if (empty($updates)) admin_json_err(400, 'no_changes');

$params[] = $trackId;
$sql = "UPDATE tracks SET " . implode(', ', $updates) . ", updated_at=NOW() WHERE id=?";
try {
    db()->prepare($sql)->execute($params);
} catch (Throwable $e) {
    admin_json_err(500, 'db_error', $e->getMessage());
}

admin_log('edit_meta', 'track', $trackId, $before, $after);
admin_json_ok(['track_id' => $trackId, 'updated' => array_keys($after)]);
