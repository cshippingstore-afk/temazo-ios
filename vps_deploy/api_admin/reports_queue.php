<?php
/**
 * GET  /api/admin/reports_queue.php?status=open&limit=50&offset=0
 *      → { ok, total, entries: [{id, reporter_id, reporter_email, target_type, target_id,
 *          target_name, reason, note, status, created_at}] }
 *
 * POST /api/admin/reports_queue.php  { report_id: int, action: 'resolve'|'dismiss'|'in_review', note?: string }
 *      → cierra o marca el reporte. Loguea en admin_actions.
 */
declare(strict_types=1);
require_once __DIR__ . '/admin_lib.php';
$u = auth_require_admin();
$db = db();

if ($_SERVER['REQUEST_METHOD'] === 'GET') {
    $status = $_GET['status'] ?? 'open';
    $validStatuses = ['open','in_review','resolved','dismissed','all'];
    if (!in_array($status, $validStatuses, true)) admin_json_err(400, 'invalid_status');
    $limit = min(200, max(1, (int)($_GET['limit'] ?? 50)));
    $offset = max(0, (int)($_GET['offset'] ?? 0));

    $where = $status === 'all' ? '1=1' : "r.status = ?";
    $params = $status === 'all' ? [] : [$status];
    $total = (int)$db->prepare("SELECT COUNT(*) FROM content_reports r WHERE $where")
                    ->execute($params) === false ? 0 :
             (int)($db->query("SELECT COUNT(*) FROM content_reports r WHERE " .
                              ($status === 'all' ? '1=1' : "status='" . addslashes($status) . "'"))
                    ->fetchColumn() ?? 0);
    $sql = "SELECT r.id, r.reporter_id, u.email reporter_email,
            r.target_type, r.target_id, r.reason, r.note, r.status,
            r.resolved_by, r.resolved_at, r.created_at
            FROM content_reports r LEFT JOIN users u ON u.id=r.reporter_id
            WHERE $where ORDER BY r.id DESC LIMIT ? OFFSET ?";
    $allParams = array_merge($params, [$limit, $offset]);
    $st = $db->prepare($sql);
    foreach ($allParams as $i => $v) {
        $st->bindValue($i + 1, $v, is_int($v) ? PDO::PARAM_INT : PDO::PARAM_STR);
    }
    $st->execute();
    $entries = $st->fetchAll(PDO::FETCH_ASSOC);

    // Enriquecer con target_name (title del track / name del artist/album)
    foreach ($entries as &$e) {
        $tt = $e['target_type']; $tid = (int)$e['target_id'];
        $tn = null;
        if ($tt === 'track') {
            $r = $db->prepare("SELECT title, artist_name FROM tracks WHERE id=?");
            $r->execute([$tid]); $x = $r->fetch(PDO::FETCH_ASSOC);
            $tn = $x ? "{$x['title']} · {$x['artist_name']}" : "(deleted)";
        } elseif ($tt === 'artist') {
            $r = $db->prepare("SELECT name FROM artists WHERE id=?");
            $r->execute([$tid]); $tn = $r->fetchColumn() ?: '(deleted)';
        } elseif ($tt === 'album') {
            $r = $db->prepare("SELECT name FROM albums WHERE id=?");
            $r->execute([$tid]); $tn = $r->fetchColumn() ?: '(deleted)';
        }
        $e['target_name'] = $tn;
    }
    admin_json_ok(['total' => $total, 'entries' => $entries]);
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') admin_json_err(405, 'method_not_allowed');

$in = admin_json_input();
$reportId = admin_get_int($in, 'report_id', 1);
$action = admin_get_str($in, 'action', 16);
if (!in_array($action, ['resolve','dismiss','in_review'], true)) admin_json_err(400, 'invalid_action');
$note = isset($in['note']) ? substr(trim((string)$in['note']), 0, 500) : null;

$status = ['resolve'=>'resolved','dismiss'=>'dismissed','in_review'=>'in_review'][$action];
$db->prepare("UPDATE content_reports SET status=?, resolved_by=?, resolved_at=NOW() WHERE id=?")
   ->execute([$status, (int)$u['id'], $reportId]);

admin_log("report_$action", 'report', $reportId, null, ['status' => $status, 'note' => $note]);
admin_json_ok(['report_id' => $reportId, 'status' => $status]);
