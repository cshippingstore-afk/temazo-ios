<?php
/**
 * CLI helper para el worker del import_playlist_youtube.
 * Uso: php _import_single_yt.php <youtube_id> <admin_user_id>
 *
 * Reutiliza la misma logica de import_youtube.php pero sin auth session
 * (corremos como worker background, no como request web).
 */
declare(strict_types=1);
require_once __DIR__ . '/../auth_lib.php';

$vid = $argv[1] ?? '';
$adminUid = (int)($argv[2] ?? 0);
if (strlen($vid) !== 11 || !preg_match('/^[a-zA-Z0-9_-]{11}$/', $vid)) {
    fwrite(STDERR, "invalid yt id: $vid\n"); exit(2);
}
if ($adminUid <= 0) { fwrite(STDERR, "missing admin uid\n"); exit(2); }

// Ya existe?
$st = db()->prepare("SELECT id FROM tracks WHERE youtube_id=? LIMIT 1");
$st->execute([$vid]);
if ($st->fetchColumn()) { echo "[$vid] exists\n"; exit(0); }

$cookieDir = '/var/www/vhosts/temazo.es/private/cookies';
$cookieFiles = glob("$cookieDir/owner_*.txt") ?: [];
shuffle($cookieFiles);
$cookieArg = $cookieFiles ? ('--cookies ' . escapeshellarg($cookieFiles[0]) . ' ') : '';

$cmd = '/usr/local/bin/yt-dlp ' . $cookieArg .
       '--dump-single-json --no-warnings --no-playlist --skip-download ' .
       escapeshellarg("https://www.youtube.com/watch?v=$vid") . ' 2>&1';
$out = @shell_exec($cmd);
$info = json_decode((string)$out, true);
if (!is_array($info) || !isset($info['id'])) {
    echo "[$vid] ytdlp_failed: " . substr((string)$out, 0, 100) . "\n";
    exit(1);
}

$title = trim((string)($info['track'] ?? $info['title'] ?? 'Untitled'));
$artistNm = trim((string)($info['artist'] ?? $info['creator'] ?? $info['uploader'] ?? 'Unknown'));
$albumNm = trim((string)($info['album'] ?? ''));
$durationSec = (int)round((float)($info['duration'] ?? 0));
$durationStr = sprintf('%d:%02d', intdiv($durationSec, 60), $durationSec % 60);
$coverLarge = null;
if (!empty($info['thumbnails']) && is_array($info['thumbnails'])) {
    usort($info['thumbnails'], fn($a, $b) => (int)($b['width'] ?? 0) - (int)($a['width'] ?? 0));
    $coverLarge = $info['thumbnails'][0]['url'] ?? null;
}
$releaseDate = null;
if (!empty($info['upload_date']) && preg_match('/^(\d{4})(\d{2})(\d{2})$/', $info['upload_date'], $m)) {
    $releaseDate = "{$m[1]}-{$m[2]}-{$m[3]}";
}
$viewCount = (int)($info['view_count'] ?? 0);
$ytChannelId = $info['channel_id'] ?? null;

$slugify = function(string $s): string {
    $s = mb_strtolower($s, 'UTF-8');
    $s = preg_replace('/[^\p{L}\p{N}]+/u', '-', $s);
    $s = trim($s ?? '', '-');
    return $s === '' ? 'untitled' : substr($s, 0, 250);
};

$db = db();
try {
    $db->beginTransaction();
    $stA = $db->prepare("SELECT id FROM artists WHERE _name_lc = LOWER(?) LIMIT 1");
    $stA->execute([$artistNm]);
    $artistId = $stA->fetchColumn();
    if (!$artistId) {
        $slug = $slugify($artistNm);
        $stX = $db->prepare("SELECT 1 FROM artists WHERE slug=?");
        $stX->execute([$slug]);
        if ($stX->fetchColumn()) $slug .= '-' . substr(bin2hex(random_bytes(2)), 0, 4);
        $db->prepare("INSERT INTO artists (name, slug, yt_channel_id, image_large, popularity, followers) VALUES (?, ?, ?, ?, 0, 0)")
           ->execute([$artistNm, $slug, $ytChannelId, $coverLarge]);
        $artistId = (int)$db->lastInsertId();
    }
    $artistId = (int)$artistId;

    $albumId = null;
    if ($albumNm !== '') {
        $stAl = $db->prepare("SELECT id FROM albums WHERE artist_id=? AND name=? LIMIT 1");
        $stAl->execute([$artistId, $albumNm]);
        $albumId = $stAl->fetchColumn();
        if (!$albumId) {
            $db->prepare("INSERT INTO albums (artist_id, name, slug, image_large, release_date) VALUES (?, ?, ?, ?, ?)")
               ->execute([$artistId, $albumNm, $slugify($albumNm), $coverLarge, $releaseDate]);
            $albumId = (int)$db->lastInsertId();
        }
        $albumId = (int)$albumId;
    }

    $slug = $slugify($title);
    $stD = $db->prepare("SELECT 1 FROM tracks WHERE slug=? AND artist_id=?");
    $stD->execute([$slug, $artistId]);
    if ($stD->fetchColumn()) $slug .= '-' . substr(bin2hex(random_bytes(2)), 0, 4);

    $db->prepare("INSERT INTO tracks (title, slug, artist_id, album_id, artist_name, album,
                                       cover_large, youtube_id, duration, duration_sec, view_count, release_date)
                  VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)")
       ->execute([$title, $slug, $artistId, $albumId, $artistNm, $albumNm ?: null,
                  $coverLarge, $vid, $durationStr, $durationSec, $viewCount, $releaseDate]);
    $trackId = (int)$db->lastInsertId();

    $db->prepare("INSERT INTO track_youtube_alternatives (track_id, youtube_id, is_active, added_by, note) VALUES (?, ?, 1, ?, 'playlist-imported')")
       ->execute([$trackId, $vid, $adminUid]);
    $db->commit();

    // Audit log entry
    $db->prepare("INSERT INTO admin_actions (admin_id, action, target_type, target_id, after_json, note) VALUES (?, 'import_youtube_playlist_item', 'track', ?, ?, ?)")
       ->execute([$adminUid, $trackId,
                  json_encode(['title' => $title, 'artist' => $artistNm, 'yt' => $vid], JSON_UNESCAPED_UNICODE),
                  'from playlist worker']);
    echo "[$vid] OK track_id=$trackId title=\"$title\" artist=\"$artistNm\"\n";
} catch (Throwable $e) {
    $db->rollBack();
    echo "[$vid] db_error: " . $e->getMessage() . "\n";
    exit(1);
}
