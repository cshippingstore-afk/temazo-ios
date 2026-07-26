<?php
/**
 * POST /api/admin/import_youtube.php
 * Body JSON: { youtube: "URL o id 11-char",
 *              artist_name?: string,      // override si el auto es malo
 *              album_name?: string }
 *
 * Importa un track nuevo desde YouTube al catalogo.
 *   1. Extrae YT id.
 *   2. Si ya existe en tracks.youtube_id → devuelve el track existente.
 *   3. Extrae metadata con yt-dlp (--dump-json + cookies pool).
 *   4. Reusa/crea artist (match por _name_lc, sino insert con slug único).
 *   5. Reusa/crea album (match por artist+name, sino insert).
 *   6. Inserta track y devuelve el nuevo track_id.
 */
declare(strict_types=1);
require_once __DIR__ . '/admin_lib.php';

if ($_SERVER['REQUEST_METHOD'] !== 'POST') admin_json_err(405, 'method_not_allowed');
$u = auth_require_admin();

set_time_limit(60);
ignore_user_abort(true);

$in = admin_json_input();
$raw = admin_get_str($in, 'youtube', 500);
$overrideArtist = isset($in['artist_name']) ? trim((string)$in['artist_name']) : '';
$overrideAlbum  = isset($in['album_name']) ? trim((string)$in['album_name']) : '';

$ytId = admin_yt_id_from_url_or_id($raw);
if (!$ytId) admin_json_err(400, 'invalid_youtube');

// 1) ya existe?
$existing = db()->prepare("SELECT * FROM tracks WHERE youtube_id=? LIMIT 1");
$existing->execute([$ytId]);
if ($row = $existing->fetch(PDO::FETCH_ASSOC)) {
    admin_json_ok(['track_id' => (int)$row['id'], 'existed' => true, 'title' => $row['title'], 'artist' => $row['artist_name']]);
}

// 2) extraer metadata con yt-dlp (cookie pool round-robin, mismo enfoque que yt_proxy)
$cookieDir = '/var/www/vhosts/temazo.es/private/cookies';
$cookieFiles = is_dir($cookieDir) ? glob("$cookieDir/owner_*.txt") : [];
shuffle($cookieFiles);
$attempts = $cookieFiles; $attempts[] = null;

$info = null; $lastErr = '';
foreach ($attempts as $cf) {
    $cookieArg = $cf ? ('--cookies ' . escapeshellarg($cf) . ' ') : '';
    $cmd = '/usr/local/bin/yt-dlp ' . $cookieArg .
           '--dump-single-json --no-warnings --no-playlist --skip-download ' .
           escapeshellarg("https://www.youtube.com/watch?v=$ytId") . ' 2>&1';
    $out = @shell_exec($cmd);
    $decoded = json_decode((string)$out, true);
    if (is_array($decoded) && isset($decoded['id'])) { $info = $decoded; break; }
    $lastErr = substr((string)$out, 0, 200);
}
if (!$info) admin_json_err(502, 'ytdlp_failed', $lastErr);

$title    = trim((string)($info['track'] ?? $info['title'] ?? '')) ?: 'Untitled';
$artistNm = $overrideArtist !== '' ? $overrideArtist
             : trim((string)($info['artist'] ?? $info['creator'] ?? $info['uploader'] ?? 'Unknown'));
$albumNm  = $overrideAlbum !== '' ? $overrideAlbum
             : trim((string)($info['album'] ?? ''));
$durationSec = (int)round((float)($info['duration'] ?? 0));
$durationStr = sprintf('%d:%02d', intdiv($durationSec, 60), $durationSec % 60);
$coverLarge = null;
if (!empty($info['thumbnails']) && is_array($info['thumbnails'])) {
    // Elegir la más grande
    usort($info['thumbnails'], fn($a, $b) => (int)($b['width'] ?? 0) - (int)($a['width'] ?? 0));
    $coverLarge = $info['thumbnails'][0]['url'] ?? null;
}
$releaseDate = null;
if (!empty($info['upload_date']) && preg_match('/^(\d{4})(\d{2})(\d{2})$/', $info['upload_date'], $m)) {
    $releaseDate = "{$m[1]}-{$m[2]}-{$m[3]}";
}
$viewCount = (int)($info['view_count'] ?? 0);
$ytChannelId = $info['channel_id'] ?? null;

// Helper slug
$slugify = function(string $s): string {
    $s = mb_strtolower($s, 'UTF-8');
    $s = preg_replace('/[^\p{L}\p{N}]+/u', '-', $s);
    $s = trim($s ?? '', '-');
    return $s === '' ? 'untitled' : substr($s, 0, 250);
};

$db = db();
$db->beginTransaction();
try {
    // Artist: buscar por nombre (case insensitive)
    $stA = $db->prepare("SELECT id FROM artists WHERE _name_lc = LOWER(?) LIMIT 1");
    $stA->execute([$artistNm]);
    $artistId = $stA->fetchColumn();
    if (!$artistId) {
        // Slug unico: intentar slug, y si colisiona añadir sufijo random
        $slug = $slugify($artistNm);
        $stX = $db->prepare("SELECT 1 FROM artists WHERE slug=? LIMIT 1");
        $stX->execute([$slug]);
        if ($stX->fetchColumn()) $slug .= '-' . substr(bin2hex(random_bytes(2)), 0, 4);
        $ins = $db->prepare("INSERT INTO artists (name, slug, yt_channel_id, image_large, popularity, followers) VALUES (?, ?, ?, ?, 0, 0)");
        $ins->execute([$artistNm, $slug, $ytChannelId, $coverLarge]);
        $artistId = (int)$db->lastInsertId();
    }
    $artistId = (int)$artistId;

    // Album (opcional)
    $albumId = null;
    if ($albumNm !== '') {
        $stAl = $db->prepare("SELECT id FROM albums WHERE artist_id=? AND name=? LIMIT 1");
        $stAl->execute([$artistId, $albumNm]);
        $albumId = $stAl->fetchColumn();
        if (!$albumId) {
            $stIns = $db->prepare("INSERT INTO albums (artist_id, name, slug, image_large, release_date) VALUES (?, ?, ?, ?, ?)");
            $stIns->execute([$artistId, $albumNm, $slugify($albumNm), $coverLarge, $releaseDate]);
            $albumId = (int)$db->lastInsertId();
        }
        $albumId = (int)$albumId;
    }

    // Track
    $slug = $slugify($title);
    $st = $db->prepare("SELECT 1 FROM tracks WHERE slug=? AND artist_id=? LIMIT 1");
    $st->execute([$slug, $artistId]);
    if ($st->fetchColumn()) $slug .= '-' . substr(bin2hex(random_bytes(2)), 0, 4);

    $ins = $db->prepare("INSERT INTO tracks
        (title, slug, artist_id, album_id, artist_name, album,
         cover_large, youtube_id, duration, duration_sec, view_count, release_date)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)");
    $ins->execute([$title, $slug, $artistId, $albumId, $artistNm, $albumNm ?: null,
                   $coverLarge, $ytId, $durationStr, $durationSec, $viewCount, $releaseDate]);
    $trackId = (int)$db->lastInsertId();

    // Registrar el youtube_id como active en alternatives
    $db->prepare("INSERT INTO track_youtube_alternatives (track_id, youtube_id, is_active, added_by, note) VALUES (?, ?, 1, ?, 'imported')")
       ->execute([$trackId, $ytId, (int)$u['id']]);

    $db->commit();
} catch (Throwable $e) {
    $db->rollBack();
    admin_json_err(500, 'db_error', $e->getMessage());
}

admin_log('import_youtube', 'track', $trackId, null,
    ['track_id' => $trackId, 'youtube_id' => $ytId, 'title' => $title,
     'artist_id' => $artistId, 'artist_name' => $artistNm, 'album_id' => $albumId]);

admin_json_ok([
    'track_id' => $trackId, 'existed' => false,
    'title' => $title, 'artist' => $artistNm, 'album' => $albumNm ?: null,
    'youtube_id' => $ytId,
]);
