<?php
/**
 * POST /api/admin/track_merge.php
 * Body: { source_id: int, target_id: int, note?: string }
 *
 * Fusiona 2 tracks duplicados:
 *   - Migra user_favorites del source al target (IGNORE duplicados)
 *   - Migra user_playlist_tracks del source al target
 *   - Migra play_history del source al target
 *   - Marca source como hidden=1 (soft delete, no borra por si algún user lo tiene en favs)
 *
 * Auditable + reversible via admin_actions.before_json (guarda counts).
 */
declare(strict_types=1);
require_once __DIR__ . '/admin_lib.php';
if ($_SERVER['REQUEST_METHOD'] !== 'POST') admin_json_err(405, 'method_not_allowed');
auth_require_admin();

$in = admin_json_input();
$src = admin_get_int($in, 'source_id', 1);
$tgt = admin_get_int($in, 'target_id', 1);
if ($src === $tgt) admin_json_err(400, 'same_track');
$note = isset($in['note']) ? substr(trim((string)$in['note']), 0, 500) : null;

$srcTrack = admin_fetch_track($src);
$tgtTrack = admin_fetch_track($tgt);
if (!$srcTrack) admin_json_err(404, 'source_not_found');
if (!$tgtTrack) admin_json_err(404, 'target_not_found');

$db = db();
$db->beginTransaction();
try {
    // 1) fav counts before
    $favsBefore = (int)$db->query("SELECT COUNT(*) FROM user_favorites WHERE track_id=$src")->fetchColumn();
    $ptrBefore  = (int)$db->query("SELECT COUNT(*) FROM user_playlist_tracks WHERE track_id=$src")->fetchColumn();
    $histBefore = (int)$db->query("SELECT COUNT(*) FROM play_history WHERE track_id=$src")->fetchColumn();

    // 2) migrar favs (IGNORE si el user ya tiene el target)
    $db->prepare("INSERT IGNORE INTO user_favorites (user_id, track_id, added_at)
                  SELECT user_id, ?, added_at FROM user_favorites WHERE track_id=?")
       ->execute([$tgt, $src]);
    $db->prepare("DELETE FROM user_favorites WHERE track_id=?")->execute([$src]);

    // 3) migrar playlist tracks: si el user ya tiene el target en la misma playlist, saltar
    $db->prepare("UPDATE IGNORE user_playlist_tracks SET track_id=? WHERE track_id=?")
       ->execute([$tgt, $src]);
    // Los remanentes (que colisionaron) se eliminan
    $db->prepare("DELETE FROM user_playlist_tracks WHERE track_id=?")->execute([$src]);

    // 4) migrar play_history (no colisiona, se acumula)
    $db->prepare("UPDATE play_history SET track_id=? WHERE track_id=?")->execute([$tgt, $src]);

    // 5) hide source
    $db->prepare("UPDATE tracks SET hidden=1, updated_at=NOW() WHERE id=?")->execute([$src]);

    $db->commit();
} catch (Throwable $e) {
    $db->rollBack();
    admin_json_err(500, 'db_error', $e->getMessage());
}

admin_log('merge_tracks', 'track', $tgt,
    ['source_id' => $src, 'source_title' => $srcTrack['title'],
     'favs' => $favsBefore, 'playlist_entries' => $ptrBefore, 'plays' => $histBefore],
    ['target_id' => $tgt, 'target_title' => $tgtTrack['title']],
    $note);

admin_json_ok([
    'source_id' => $src, 'target_id' => $tgt,
    'migrated' => ['favs' => $favsBefore, 'playlist_entries' => $ptrBefore, 'plays' => $histBefore]
]);
