<?php
/**
 * /api/yt_proxy.php?id=YOUTUBE_VIDEO_ID
 *
 * Estrategia v5 (2026-07-26):
 *   YouTube ahora IP-locka las URLs de googlevideo — 302 redirect al cliente
 *   da 403 porque la IP del iPhone != IP del VPS que firmó la URL.
 *   Solución: descargar el m4a al VPS con yt-dlp -o y servir localmente
 *   con Range. Lento primera vez (~5-10s), instantáneo después.
 *
 * Niveles:
 *  Nivel 1: /tmp/_yt_audio_cache/<id>.m4a — bytes descargados (por warmer o request previo)
 *           Si existe Y es > 500KB, sirve con Range headers.
 *  Nivel 2: Download síncrono con yt-dlp (cookie pool round-robin) al mismo
 *           path del cache, luego sirve.
 *
 * Cookies pool: /var/www/vhosts/temazo.es/private/cookies/owner_*.txt
 * Auto-sync desde Firefox TemazoBot del owner (Task Scheduler cada 12h).
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

function serve_file(string $path): void {
    $size = filesize($path);
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
    $f = fopen($path, 'rb');
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
}

$audioCache = '/tmp/_yt_audio_cache';
@mkdir($audioCache, 0755, true);
$audioFile = "$audioCache/$id.m4a";

// === Nivel 1: disk cache hit — servir directo ===
if (is_file($audioFile) && filesize($audioFile) >= 500_000) {
    log_line("CACHE_HIT id=$id size=" . filesize($audioFile));
    serve_file($audioFile);
    exit;
}

// === Nivel 2: download síncrono con yt-dlp ===
// Lock por video para evitar 2 requests bajando el mismo archivo
$lockFile = "$audioCache/$id.lock";
$lockHandle = @fopen($lockFile, 'c');
if ($lockHandle) {
    // Wait blocking (max 30s por SIGALRM fallback)
    if (flock($lockHandle, LOCK_EX)) {
        // Otro proceso puede haber terminado la descarga — re-check
        if (is_file($audioFile) && filesize($audioFile) >= 500_000) {
            flock($lockHandle, LOCK_UN); fclose($lockHandle); @unlink($lockFile);
            log_line("CACHE_HIT_AFTER_LOCK id=$id");
            serve_file($audioFile);
            exit;
        }

        // Cookie pool
        $cookieDir = '/var/www/vhosts/temazo.es/private/cookies';
        $cookieFiles = is_dir($cookieDir) ? glob("$cookieDir/owner_*.txt") : [];
        shuffle($cookieFiles);
        $attempts = $cookieFiles;
        $attempts[] = null;  // último fallback sin cookies

        $ytdlp = '/usr/local/bin/yt-dlp';
        $tmpOut = "$audioFile.tmp";
        $downloaded = false;

        foreach ($attempts as $cookieFile) {
            $cookieArg = $cookieFile ? ('--cookies ' . escapeshellarg($cookieFile) . ' ') : '';
            @unlink($tmpOut);
            $cmd = $ytdlp . ' '
                 . $cookieArg
                 . '-f "bestaudio[ext=m4a]/bestaudio" '
                 . '-o ' . escapeshellarg($tmpOut) . ' '
                 . '--no-warnings --no-playlist --no-part '
                 . escapeshellarg("https://www.youtube.com/watch?v=$id")
                 . ' 2>&1';
            $out = @shell_exec($cmd);
            if (is_file($tmpOut) && filesize($tmpOut) >= 500_000) {
                @rename($tmpOut, $audioFile);
                $tag = $cookieFile ? basename($cookieFile) : 'no-cookies';
                log_line("DL_OK id=$id via=$tag size=" . filesize($audioFile));
                $downloaded = true;
                break;
            } else {
                $tag = $cookieFile ? basename($cookieFile) : 'no-cookies';
                $err = substr(str_replace(["\n","\r"], ' ', (string)$out), 0, 200);
                log_line("DL_FAIL id=$id via=$tag err=$err");
            }
        }

        flock($lockHandle, LOCK_UN);
        fclose($lockHandle);
        @unlink($lockFile);

        if ($downloaded) {
            serve_file($audioFile);
            exit;
        }
    } else {
        fclose($lockHandle);
    }
}

http_response_code(502);
echo 'ytdlp_failed';
exit;
