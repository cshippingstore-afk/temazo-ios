<?php
/**
 * POST /api/admin/artist_edit_genres.php
 * Body: { artist_id: int, genre_ids: [int, int, ...] }
 *
 * Reescribe la lista de géneros del artista (artist_genres pivot).
 * genre_ids son IDs de la tabla `genres`. Máx 10 géneros por artista.
 *
 * GET /api/admin/artist_edit_genres.php?list=1
 *   → devuelve lista de géneros visibles disponibles ({id, name, slug, parent_id}).
 */
declare(strict_types=1);
require_once __DIR__ . '/admin_lib.php';

if ($_SERVER['REQUEST_METHOD'] === 'GET' && isset($_GET['list'])) {
    auth_require_admin();
    $rows = db()->query("SELECT id, name, slug, parent_id FROM genres WHERE is_visible=1 ORDER BY parent_id IS NULL DESC, name")
                ->fetchAll(PDO::FETCH_ASSOC);
    admin_json_ok(['genres' => $rows]);
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') admin_json_err(405, 'method_not_allowed');
auth_require_admin();

$in = admin_json_input();
$artistId = admin_get_int($in, 'artist_id', 1);
$artist = admin_fetch_artist($artistId);
if (!$artist) admin_json_err(404, 'artist_not_found');

if (!isset($in['genre_ids']) || !is_array($in['genre_ids'])) {
    admin_json_err(400, 'missing_field', 'genre_ids array');
}
$ids = array_values(array_unique(array_filter(array_map(fn($x) => filter_var($x, FILTER_VALIDATE_INT), $in['genre_ids']),
                                              fn($v) => $v !== false && $v > 0)));
if (count($ids) > 10) admin_json_err(400, 'too_many', 'max 10 géneros');

$db = db();
// Verify ids existen. NO exigimos is_visible=1 porque muchos artistas
// tienen géneros históricos ya asignados que ahora están ocultos (Blues, etc).
// Solo rechazamos si el ID no existe en absoluto en la tabla genres.
if ($ids) {
    $ph = implode(',', array_fill(0, count($ids), '?'));
    $valid = $db->prepare("SELECT id, name FROM genres WHERE id IN ($ph)");
    $valid->execute($ids);
    $validRows = $valid->fetchAll(PDO::FETCH_KEY_PAIR);
    if (count($validRows) !== count($ids)) {
        $missing = array_diff($ids, array_keys($validRows));
        admin_json_err(400, 'invalid_genre_ids', 'IDs inexistentes: ' . implode(',', $missing));
    }
    $nameList = array_values($validRows);
} else {
    $nameList = [];
}

$prev = $db->prepare("SELECT g.id, g.name FROM artist_genres ag JOIN genres g ON g.id=ag.genre_id WHERE ag.artist_id=?");
$prev->execute([$artistId]);
$prevPairs = $prev->fetchAll(PDO::FETCH_ASSOC);

$db->beginTransaction();
try {
    $db->prepare("DELETE FROM artist_genres WHERE artist_id=?")->execute([$artistId]);
    if ($ids) {
        $stIn = $db->prepare("INSERT INTO artist_genres (artist_id, genre_id) VALUES (?, ?)");
        foreach ($ids as $gid) $stIn->execute([$artistId, $gid]);
    }
    // También actualiza el legacy artists.genres (texto JSON de names)
    $legacy = $nameList ? json_encode($nameList, JSON_UNESCAPED_UNICODE) : null;
    $db->prepare("UPDATE artists SET genres=?, updated_at=NOW() WHERE id=?")->execute([$legacy, $artistId]);
    $db->commit();
} catch (Throwable $e) {
    $db->rollBack();
    admin_json_err(500, 'db_error', $e->getMessage());
}

admin_log('edit_genres', 'artist', $artistId,
    ['genres' => $prevPairs],
    ['genre_ids' => $ids, 'names' => $nameList]);
admin_json_ok(['artist_id' => $artistId, 'genre_ids' => $ids, 'names' => $nameList]);
