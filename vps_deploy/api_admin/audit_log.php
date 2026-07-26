<?php
/**
 * GET  /api/admin/audit_log.php?limit=50&offset=0&action=&target_type=&admin_id=
 *      → { ok, total, entries: [{id, admin_id, admin_email, action, target_type, target_id,
 *          before_json, after_json, note, reverted, created_at}] }
 *
 * POST /api/admin/audit_log.php  { action_id: int }
 *      → intenta revertir la acción (usa before_json). Marca reverted=1.
 *      Actualmente soportado revert de:
 *        - hide/unhide (togglea hidden)
 *        - edit_meta (restaura title/artist/etc)
 *        - replace_youtube (restaura youtube_id previo)
 *        - boost_popularity (restaura popularity previa)
 *        - edit_bio (restaura bio_ai)
 *        - reassign_album (restaura album_id previo)
 *
 * Los merges y ban recursivos requieren rollback manual (complejo).
 */
declare(strict_types=1);
require_once __DIR__ . '/admin_lib.php';
auth_require_admin();
$db = db();

if ($_SERVER['REQUEST_METHOD'] === 'GET') {
    $limit = min(200, max(1, (int)($_GET['limit'] ?? 50)));
    $offset = max(0, (int)($_GET['offset'] ?? 0));
    $where = ['1=1']; $params = [];
    foreach (['action','target_type'] as $f) {
        if (!empty($_GET[$f])) { $where[] = "$f = ?"; $params[] = $_GET[$f]; }
    }
    if (!empty($_GET['admin_id'])) { $where[] = "admin_id = ?"; $params[] = (int)$_GET['admin_id']; }
    $whereSql = implode(' AND ', $where);
    $total = (int)$db->prepare("SELECT COUNT(*) FROM admin_actions WHERE $whereSql")
                ->execute($params) === false ? 0 : (int)($db->query("SELECT COUNT(*) FROM admin_actions WHERE $whereSql")->fetchColumn() ?? 0);
    $st = $db->prepare("SELECT a.id, a.admin_id, u.email admin_email, a.action, a.target_type,
                        a.target_id, a.before_json, a.after_json, a.note, a.reverted, a.reverted_at,
                        a.created_at
                        FROM admin_actions a LEFT JOIN users u ON u.id=a.admin_id
                        WHERE $whereSql
                        ORDER BY a.id DESC LIMIT ? OFFSET ?");
    $allParams = array_merge($params, [$limit, $offset]);
    // PDO: bind mode auto — funciona
    foreach ($allParams as $i => $v) {
        $st->bindValue($i + 1, $v, is_int($v) ? PDO::PARAM_INT : PDO::PARAM_STR);
    }
    $st->execute();
    $rows = $st->fetchAll(PDO::FETCH_ASSOC);
    admin_json_ok(['total' => $total, 'entries' => $rows]);
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') admin_json_err(405, 'method_not_allowed');
$u = auth_require_admin();
$in = admin_json_input();
$actionId = admin_get_int($in, 'action_id', 1);
$row = $db->prepare("SELECT * FROM admin_actions WHERE id=? LIMIT 1");
$row->execute([$actionId]);
$a = $row->fetch(PDO::FETCH_ASSOC);
if (!$a) admin_json_err(404, 'action_not_found');
if ((int)$a['reverted'] === 1) admin_json_err(400, 'already_reverted');

$before = $a['before_json'] ? json_decode($a['before_json'], true) : [];
if (!is_array($before)) $before = [];
$type = $a['target_type']; $id = (int)$a['target_id'];
$action = $a['action'];

try {
    $db->beginTransaction();
    switch ($action) {
        case 'hide':
        case 'unhide':
            $table = ['track'=>'tracks','artist'=>'artists','album'=>'albums'][$type] ?? null;
            if (!$table) throw new Exception("unknown target_type $type");
            $prev = isset($before['hidden']) ? (int)$before['hidden'] : 0;
            $db->prepare("UPDATE $table SET hidden=? WHERE id=?")->execute([$prev, $id]);
            break;
        case 'edit_meta':
            $set = []; $params = [];
            foreach (['title','artist_name','release_date','cover_large'] as $f) {
                if (array_key_exists($f, $before)) {
                    $set[] = "$f=?"; $params[] = $before[$f];
                }
            }
            if (!$set) throw new Exception("no revertable fields");
            $params[] = $id;
            $db->prepare("UPDATE tracks SET " . implode(',', $set) . " WHERE id=?")->execute($params);
            break;
        case 'replace_youtube':
            $prevYt = $before['youtube_id'] ?? null;
            if (!$prevYt) throw new Exception("no previous youtube_id");
            $db->prepare("UPDATE tracks SET youtube_id=? WHERE id=?")->execute([$prevYt, $id]);
            // Purge caches
            @unlink("/tmp/_yt_stream_cache/" . preg_replace('/[^A-Za-z0-9_-]/', '', $prevYt) . ".url");
            break;
        case 'boost_popularity':
            $prev = isset($before['popularity']) ? (int)$before['popularity'] : 0;
            $db->prepare("UPDATE tracks SET popularity=? WHERE id=?")->execute([$prev, $id]);
            break;
        case 'edit_bio':
            $prev = $before['bio_ai'] ?? null;
            $db->prepare("UPDATE artists SET bio_ai=? WHERE id=?")->execute([$prev, $id]);
            break;
        case 'reassign_album':
            $prevAid = isset($before['album_id']) ? ($before['album_id'] === null ? null : (int)$before['album_id']) : null;
            $prevAn = $before['album'] ?? null;
            $db->prepare("UPDATE tracks SET album_id=?, album=? WHERE id=?")->execute([$prevAid, $prevAn, $id]);
            break;
        default:
            throw new Exception("action '$action' no soporta rollback automatico");
    }
    $db->prepare("UPDATE admin_actions SET reverted=1, reverted_at=NOW(), reverted_by=? WHERE id=?")
       ->execute([(int)$u['id'], $actionId]);
    $db->commit();
} catch (Throwable $e) {
    $db->rollBack();
    admin_json_err(500, 'rollback_failed', $e->getMessage());
}

admin_log('rollback', 'report', $actionId, null,
    ['reverted_action' => $action, 'reverted_target' => "$type:$id"]);
admin_json_ok(['reverted' => true, 'action_id' => $actionId, 'was_action' => $action]);
