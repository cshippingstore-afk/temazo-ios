<?php
/**
 * POST /api/admin/track_boost.php
 * Body: { track_id: int, popularity: int (0-100) }
 * o    : { track_id: int, delta: int (+/-) }
 *
 * Ajusta tracks.popularity (0-100). Sirve para promocionar lanzamientos
 * propios o bajar canciones que suenan por accidente. Los charts/trending
 * usan popularity DESC.
 */
declare(strict_types=1);
require_once __DIR__ . '/admin_lib.php';
if ($_SERVER['REQUEST_METHOD'] !== 'POST') admin_json_err(405, 'method_not_allowed');
auth_require_admin();

$in = admin_json_input();
$id = admin_get_int($in, 'track_id', 1);
$track = admin_fetch_track($id);
if (!$track) admin_json_err(404, 'track_not_found');
$prev = (int)($track['popularity'] ?? 0);

if (isset($in['popularity'])) {
    $new = admin_get_int($in, 'popularity', 0, 100);
} elseif (isset($in['delta'])) {
    $delta = admin_get_int($in, 'delta', -100, 100);
    $new = max(0, min(100, $prev + $delta));
} else {
    admin_json_err(400, 'missing_field', 'popularity o delta');
}

if ($new === $prev) admin_json_err(400, 'no_change');

db()->prepare("UPDATE tracks SET popularity=?, updated_at=NOW() WHERE id=?")->execute([$new, $id]);
admin_log('boost_popularity', 'track', $id, ['popularity' => $prev], ['popularity' => $new]);
admin_json_ok(['track_id' => $id, 'popularity' => $new, 'previous' => $prev]);
