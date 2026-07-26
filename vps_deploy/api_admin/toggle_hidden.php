<?php
/**
 * POST /api/admin/toggle_hidden.php
 * Body JSON: { target_type: 'track'|'artist'|'album', target_id: int, hidden: bool }
 *
 * Soft delete: marca hidden=1 (o 0 para desocultar). Los queries publicos del
 * frontend deben filtrar por hidden=0. Nada se borra realmente; los favs de
 * usuarios siguen apuntando al mismo id.
 */
declare(strict_types=1);
require_once __DIR__ . '/admin_lib.php';

if ($_SERVER['REQUEST_METHOD'] !== 'POST') admin_json_err(405, 'method_not_allowed');
$u = auth_require_admin();

$in = admin_json_input();
$targetType = admin_get_str($in, 'target_type', 16);
if (!in_array($targetType, ['track', 'artist', 'album'], true)) admin_json_err(400, 'invalid_target_type');
$targetId = admin_get_int($in, 'target_id', 1);
if (!isset($in['hidden'])) admin_json_err(400, 'missing_field', 'hidden');
$hidden = filter_var($in['hidden'], FILTER_VALIDATE_BOOLEAN) ? 1 : 0;

$table = ['track'=>'tracks','artist'=>'artists','album'=>'albums'][$targetType];

// Fetch current state
$st = db()->prepare("SELECT id, hidden FROM $table WHERE id=? LIMIT 1");
$st->execute([$targetId]);
$row = $st->fetch(PDO::FETCH_ASSOC);
if (!$row) admin_json_err(404, 'target_not_found');
$prevHidden = (int)$row['hidden'];
if ($prevHidden === $hidden) admin_json_err(400, 'no_change', "Already hidden=$hidden");

db()->prepare("UPDATE $table SET hidden=?, updated_at=NOW() WHERE id=?")
    ->execute([$hidden, $targetId]);

admin_log($hidden ? 'hide' : 'unhide', $targetType, $targetId,
    ['hidden' => $prevHidden], ['hidden' => $hidden]);

admin_json_ok(['target_type' => $targetType, 'target_id' => $targetId, 'hidden' => $hidden]);
