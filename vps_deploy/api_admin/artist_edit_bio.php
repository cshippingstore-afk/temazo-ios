<?php
/**
 * POST /api/admin/artist_edit_bio.php
 * Body: { artist_id: int, bio: string (max 4000) }
 *
 * Actualiza artists.bio_ai. Es la bio "authoritative" (la que se muestra
 * primero al user). Las bio_lastfm/wiki/ytmusic quedan como fallback pero
 * no se tocan.
 */
declare(strict_types=1);
require_once __DIR__ . '/admin_lib.php';
if ($_SERVER['REQUEST_METHOD'] !== 'POST') admin_json_err(405, 'method_not_allowed');
auth_require_admin();

$in = admin_json_input();
$artistId = admin_get_int($in, 'artist_id', 1);
$artist = admin_fetch_artist($artistId);
if (!$artist) admin_json_err(404, 'artist_not_found');
$bio = admin_get_str($in, 'bio', 4000, true);

$prev = $artist['bio_ai'] ?? null;
if ($prev === $bio || ($prev === null && $bio === '')) admin_json_err(400, 'no_change');

$new = $bio === '' ? null : $bio;
db()->prepare("UPDATE artists SET bio_ai=?, updated_at=NOW() WHERE id=?")->execute([$new, $artistId]);

admin_log('edit_bio', 'artist', $artistId,
    ['bio_ai' => $prev !== null ? substr($prev, 0, 500) : null],
    ['bio_ai' => $new !== null ? substr($new, 0, 500) : null]);
admin_json_ok(['artist_id' => $artistId, 'bio_len' => strlen($bio)]);
