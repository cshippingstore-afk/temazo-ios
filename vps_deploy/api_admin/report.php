<?php
/**
 * POST /api/admin/report.php
 * Body JSON: { target_type: 'track'|'artist'|'album', target_id: int,
 *              reason: string, note?: string }
 *
 * Reporta un problema con contenido. Cualquier usuario logueado puede reportar
 * (no requiere admin — es la puerta de entrada del queue de moderacion).
 * Solo admins pueden LEER/RESOLVER (endpoints separados).
 *
 * Reasons validas:
 *   no_reproduce, sounds_bad, wrong_version, bad_cover, bad_lyrics_sync,
 *   wrong_title, wrong_artist, wrong_album, offensive, other
 */
declare(strict_types=1);
require_once __DIR__ . '/admin_lib.php';

if ($_SERVER['REQUEST_METHOD'] !== 'POST') admin_json_err(405, 'method_not_allowed');
$u = auth_require_login();  // solo login, no admin

$in = admin_json_input();
$targetType = admin_get_str($in, 'target_type', 16);
if (!in_array($targetType, ['track', 'artist', 'album'], true)) {
    admin_json_err(400, 'invalid_target_type');
}
$targetId = admin_get_int($in, 'target_id', 1);
$reason = admin_get_str($in, 'reason', 64);
$note = isset($in['note']) ? substr(trim((string)$in['note']), 0, 500) : null;

$validReasons = ['no_reproduce','sounds_bad','wrong_version','bad_cover','bad_lyrics_sync',
                 'wrong_title','wrong_artist','wrong_album','offensive','other'];
if (!in_array($reason, $validReasons, true)) admin_json_err(400, 'invalid_reason');

// Verify target existe
$exists = false;
if ($targetType === 'track') $exists = (bool)admin_fetch_track($targetId);
elseif ($targetType === 'artist') $exists = (bool)admin_fetch_artist($targetId);
elseif ($targetType === 'album') $exists = (bool)admin_fetch_album($targetId);
if (!$exists) admin_json_err(404, 'target_not_found');

// Rate limit: 1 reporte por user por target por hora (evita spam)
$rl = db()->prepare("SELECT COUNT(*) FROM content_reports WHERE reporter_id=? AND target_type=? AND target_id=? AND created_at > NOW() - INTERVAL 1 HOUR");
$rl->execute([(int)$u['id'], $targetType, $targetId]);
if ((int)$rl->fetchColumn() > 0) admin_json_err(429, 'rate_limited', 'Ya reportaste eso en la ultima hora');

db()->prepare("INSERT INTO content_reports (reporter_id, target_type, target_id, reason, note) VALUES (?, ?, ?, ?, ?)")
    ->execute([(int)$u['id'], $targetType, $targetId, $reason, $note]);
$reportId = (int)db()->lastInsertId();

admin_json_ok(['report_id' => $reportId]);
