<?php
/**
 * /api/yt_proxy.php?id=YOUTUBE_VIDEO_ID
 *
 * Estrategia v4 (2026-07-25):
 *   YouTube requiere LOGIN para música protegida. Usamos pool de cookies
 *   auto-syncronizadas desde el/los Chrome de los owners (Task Scheduler
 *   sube /opt/piped-prod/cookies/owner_<host>.txt cada 12h).
 *
 * Niveles:
 *  Nivel 1: /tmp/_yt_audio_cache/<id>.m4a — bytes descargados (warmer)
 *           Sirve con Range si >2MB (no corrupto).
 *  Nivel 2: /tmp/_yt_stream_cache/<id>.url — URL googlevideo cacheada (4h)
 *           302 redirect. AVPlayer tira directo a googlevideo.
 *  Nivel 3: yt-dlp con cookie pool round-robin
 *           - Elige owner_*.txt aleatorio del pool
 *           - Retry con siguiente cookie si falla
 *           - Fallback sin cookies (videos "safe" universales)
 *  Nivel 4: bgutil PO_TOKEN provider (127.0.0.1:4416) para videos que
 *           necesiten POT extra (activado auto por plugin yt-dlp).
 */
set_time_limit(0);
ignore_user_abort(true);

$id = isset($_GET['id']) ? trim((string)$_GET['id']) : '';
if (!preg_match('/^[A-Za-z0-9_-]{6,20}$/', $id)) {
    http_response_code(400);
    echo 'invalid_id';
    exit;
}

function log_line(string $msg): void {
    @file_put_contents('/tmp/yt_proxy.log',
        date('Y-m-d H:i:s') . ' ' . $msg . "\n",
        FILE_APPEND | LOCK_EX);
}

// === Nivel 1: disk cache (BYTES descargados) — sólo si NO está truncado ===
$audioCache = '/tmp/_yt_audio_cache';
$audioFile = "$audioCache/$id.m4a";
if (is_file($audioFile) && filesize($audioFile) >= 2_000_000) {
    $size = filesize($audioFile);
    $start = 0; $end = $size - 1;
    if (!empty($_SERVER['HTTP_RANGE']) && preg_match('/bytes=(\d*)-(\d*)/', $_SERVER['HTTP_RANGE'], $m)) {
        $start = $m[1] === '' ? 0 : (int)$m[1];
        $end = $m[2] === '' ? $size - 1 : min((int)$m[2], $size - 1);
        http_response_code(206);
        header("Content-Range: bytes $start-$end/$size");
    } else {
        http_response_code(200);
    }
    header('Content-Type: audio/mp4');
    header('Accept-Ranges: bytes');
    header('Content-Length: ' . ($end - $start + 1));
    header('Cache-Control: public, max-age=14400');
    $f = fopen($audioFile, 'rb');
    if ($f) {
        fseek($f, $start);
        $remaining = $end - $start + 1;
        while ($remaining > 0 && !feof($f) && !connection_aborted()) {
            $chunk = fread($f, min(65536, $remaining));
            if ($chunk === false || $chunk === '') break;
            echo $chunk; @ob_flush(); @flush();
            $remaining -= strlen($chunk);
        }
        fclose($f);
    }
    exit;
}

// === Nivel 2: URL cache (4h) — 302 redirect ===
$urlCache = '/tmp/_yt_stream_cache';
@mkdir($urlCache, 0775, true);
$urlCacheFile = "$urlCache/$id.url";
$streamUrl = null;
if (is_file($urlCacheFile) && (time() - filemtime($urlCacheFile)) < 14400) {
    $cached = trim((string)@file_get_contents($urlCacheFile));
    if (filter_var($cached, FILTER_VALIDATE_URL)) {
        $streamUrl = $cached;
    }
}

// === Nivel 3: yt-dlp con cookie pool ===
if (!$streamUrl) {
    // Pool de cookies de owners (subidos por sync_cookies.py cada 12h)
    $cookieDir = '/var/www/vhosts/temazo.es/private/cookies';
    $cookieFiles = is_dir($cookieDir) ? glob("$cookieDir/owner_*.txt") : [];
    // Shuffle para round-robin real entre calls
    shuffle($cookieFiles);
    // Añadir null al final = último intento sin cookies (por si es un video "universal")
    $attempts = $cookieFiles;
    $attempts[] = null;

    // yt-dlp binario: hardcoded al /usr/local/bin (v2026.07 con plugin bgutil POT).
    // No usar is_executable() — open_basedir restringe a paths del sitio,
    // pero shell_exec sí puede ejecutar binarios en cualquier path absoluto.
    $ytdlp = '/usr/local/bin/yt-dlp';

    foreach ($attempts as $cookieFile) {
        $cookieArg = $cookieFile ? ('--cookies ' . escapeshellarg($cookieFile) . ' ') : '';
        $cmd = $ytdlp . ' '
             . $cookieArg
             . '-f "bestaudio[ext=m4a]/bestaudio" '
             . '-g --no-warnings '
             . '--no-playlist --skip-download '
             . escapeshellarg("https://www.youtube.com/watch?v=$id")
             . ' 2>&1';
        $out = @shell_exec($cmd);
        // Parse: coger la ULTIMA linea que sea URL https:// (yt-dlp puede emitir info
        // lines antes de la URL, ej "Downloading m3u8 information")
        $line = '';
        foreach (array_reverse(explode("\n", trim((string)$out))) as $l) {
            $l = trim($l);
            if (str_starts_with($l, 'https://') && filter_var($l, FILTER_VALIDATE_URL)) {
                $line = $l;
                break;
            }
        }
        if ($line !== '') {
            $streamUrl = $line;
            @file_put_contents($urlCacheFile, $streamUrl);
            $tag = $cookieFile ? basename($cookieFile) : 'no-cookies';
            log_line("OK id=$id via=$tag");
            break;
        } else {
            $tag = $cookieFile ? basename($cookieFile) : 'no-cookies';
            $err = substr(str_replace(["\n","\r"], ' ', (string)$out), 0, 200);
            log_line("FAIL id=$id via=$tag err=$err");
        }
    }

    if (!$streamUrl) {
        http_response_code(502);
        echo 'ytdlp_failed';
        exit;
    }
}

// 302 redirect — AVPlayer hace TLS directo a googlevideo.
header('Cache-Control: private, max-age=300');
header('Location: ' . $streamUrl, true, 302);
exit;
