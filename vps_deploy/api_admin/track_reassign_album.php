<?php
/**
 * POST /api/admin/track_reassign_album.php
 * Body: { track_id: int, album_id: int|null }  (null = quitar álbum)
 *
 * Reasigna el track a otro álbum. Verifica que el álbum destino existe
 * y actualiza también tracks.album (texto) desde el álbum destino.
 */
declare(strict_types=1);
require_once __DIR__ . '/admin_lib.php';
if ($_SERVER['REQUEST_METHOD'] !== 'POST') admin_json_err(405, 'method_not_allowed');
auth_require_admin();

$in = admin_json_input();
$trackId = admin_get_int($in, 'track_id', 1);
$track = admin_fetch_track($trackId);
if (!$track) admin_json_err(404, 'track_not_found');
$prevAlbumId = $track['album_id'] === null ? null : (int)$track['album_id'];
$prevAlbumName = $track['album'];

$newAlbumId = null; $newAlbumName = null;
if (array_key_exists('album_id', $in) && $in['album_id'] !== null) {
    $newAlbumId = admin_get_int($in, 'album_id', 1);
    $album = admin_fetch_album($newAlbumId);
    if (!$album) admin_json_err(404, 'album_not_found');
    $newAlbumName = $album['name'];
} elseif (!array_key_exists('album_id', $in)) {
    admin_json_err(400, 'missing_field', 'album_id (int o null)');
}

if ($prevAlbumId === $newAlbumId) admin_json_err(400, 'no_change');

db()->prepare("UPDATE tracks SET album_id=?, album=?, updated_at=NOW() WHERE id=?")
    ->execute([$newAlbumId, $newAlbumName, $trackId]);

admin_log('reassign_album', 'track', $trackId,
    ['album_id' => $prevAlbumId, 'album' => $prevAlbumName],
    ['album_id' => $newAlbumId, 'album' => $newAlbumName]);
admin_json_ok(['track_id' => $trackId, 'album_id' => $newAlbumId, 'album' => $newAlbumName]);
