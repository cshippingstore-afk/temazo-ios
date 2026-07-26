<?php
/**
 * POST /api/admin/artist_ban.php
 * Body: { artist_id: int, note?: string }  → hidden=1 artist + todos sus tracks + todos sus albums
 * DELETE                                    → unban (hidden=0)
 *
 * "Ban" es soft delete recursivo (protección legal / contenido ofensivo).
 * Reversible via admin_actions.before_json (counts).
 */
declare(strict_types=1);
require_once __DIR__ . '/admin_lib.php';
$method = $_SERVER['REQUEST_METHOD'];
if (!in_array($method, ['POST', 'DELETE'], true)) admin_json_err(405, 'method_not_allowed');
auth_require_admin();

$in = admin_json_input();
$artistId = admin_get_int($in, 'artist_id', 1);
$artist = admin_fetch_artist($artistId);
if (!$artist) admin_json_err(404, 'artist_not_found');
$note = isset($in['note']) ? substr(trim((string)$in['note']), 0, 500) : null;
$hidden = $method === 'POST' ? 1 : 0;

$db = db();
$db->beginTransaction();
try {
    $trackCount = (int)$db->prepare("SELECT COUNT(*) FROM tracks WHERE artist_id=?")->execute([$artistId])
                  === false ? 0 : (int)($db->query("SELECT COUNT(*) FROM tracks WHERE artist_id=$artistId")->fetchColumn() ?? 0);
    $albumCount = (int)$db->query("SELECT COUNT(*) FROM albums WHERE artist_id=$artistId")->fetchColumn();

    $db->prepare("UPDATE artists SET hidden=?, updated_at=NOW() WHERE id=?")->execute([$hidden, $artistId]);
    $db->prepare("UPDATE tracks SET hidden=?, updated_at=NOW() WHERE artist_id=?")->execute([$hidden, $artistId]);
    $db->prepare("UPDATE albums SET hidden=?, updated_at=NOW() WHERE artist_id=?")->execute([$hidden, $artistId]);
    $db->commit();
} catch (Throwable $e) {
    $db->rollBack();
    admin_json_err(500, 'db_error', $e->getMessage());
}

admin_log($hidden ? 'ban_artist' : 'unban_artist', 'artist', $artistId,
    ['hidden' => (int)$artist['hidden']],
    ['hidden' => $hidden, 'affected_tracks' => $trackCount, 'affected_albums' => $albumCount],
    $note);
admin_json_ok(['artist_id' => $artistId, 'hidden' => $hidden,
               'affected' => ['tracks' => $trackCount, 'albums' => $albumCount]]);
