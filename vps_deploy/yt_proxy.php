<?php
/**
 * yt_proxy.php v2 — resolutor YouTube sin yt-dlp
 *
 * Estrategia:
 *   1. Fetch https://www.youtube.com/watch?v={id} desde IP del VPS con UA iPhone
 *   2. Parse ytInitialPlayerResponse JSON del HTML
 *   3. Extraer adaptiveFormats[].url (audio-only, mejor bitrate)
 *   4. 302 redirect a esa URL de googlevideo
 *   5. Cache el 302 en /tmp por 5 min (googlevideo URLs caducan a los 6h pero refresh cada 5 es seguro)
 *
 * Ventajas vs yt-dlp:
 *   - Cero dependencias binarias (yt-dlp puede estar caducado/roto)
 *   - Menos memory footprint (yt-dlp fork/exec pesa)
 *   - Más rápido (parse directo, sin proceso hijo)
 *
 * Limitaciones:
 *   - Si YouTube añade signatureCipher para el video → falla (raro, casi todos audio-only son directos)
 *   - Si YouTube cambia el formato del JSON → falla (poco frecuente, meses)
 *
 * Uso:
 *   GET /api/yt_proxy.php?id={video_id}
 *   → 302 Location: https://...googlevideo.com/videoplayback?...&mime=audio/mp4
 *   Errores:
 *   → 400 si id vacío
 *   → 502 si YouTube devuelve error o no se puede parsear
 *   → 503 si no hay audio (signatureCipher only o video privado)
 */

declare(strict_types=1);

// --- Config
const CACHE_DIR = '/tmp/yt_proxy_cache';
const CACHE_TTL_SEC = 300;                    // 5 min
const YT_FETCH_TIMEOUT_SEC = 8;
const USER_AGENT = 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1';

// --- Helpers
function json_error(int $status, string $msg): void {
    http_response_code($status);
    header('Content-Type: application/json');
    echo json_encode(['error' => $msg]);
    exit;
}

function log_line(string $msg): void {
    @file_put_contents('/tmp/yt_proxy.log',
        date('Y-m-d H:i:s') . ' ' . $msg . "\n",
        FILE_APPEND | LOCK_EX);
}

// --- 1. Validar input
$id = $_GET['id'] ?? '';
if (!preg_match('/^[a-zA-Z0-9_-]{11}$/', $id)) {
    json_error(400, 'invalid id');
}

// --- 2. Cache hit
@mkdir(CACHE_DIR, 0755, true);
$cache_file = CACHE_DIR . '/' . $id . '.txt';
if (is_file($cache_file) && (time() - filemtime($cache_file)) < CACHE_TTL_SEC) {
    $url = trim((string)@file_get_contents($cache_file));
    if ($url && str_starts_with($url, 'https://')) {
        header('Cache-Control: private, max-age=' . (CACHE_TTL_SEC - (time() - filemtime($cache_file))));
        header('X-Cache: HIT');
        header('Location: ' . $url, true, 302);
        exit;
    }
}

// --- 3. Fetch YouTube watch page
$watch_url = 'https://www.youtube.com/watch?' . http_build_query([
    'v' => $id,
    'bpctr' => '9999999999',
    'has_verified' => '1',
]);

$ch = curl_init($watch_url);
curl_setopt_array($ch, [
    CURLOPT_RETURNTRANSFER => true,
    CURLOPT_FOLLOWLOCATION => true,      // seguir redirects (consent, etc.)
    CURLOPT_MAXREDIRS => 5,
    CURLOPT_TIMEOUT => YT_FETCH_TIMEOUT_SEC,
    CURLOPT_USERAGENT => USER_AGENT,
    CURLOPT_HTTPHEADER => [
        'Accept-Language: es-ES,es;q=0.9,en;q=0.8',
        'Accept: text/html,application/xhtml+xml',
        // Cookie CONSENT evita página consent EU
        'Cookie: CONSENT=YES+cb.20210328-17-p0.en+FX+800; VISITOR_INFO1_LIVE=oKckVSqvaGQ',
    ],
    CURLOPT_ENCODING => '',              // aceptar gzip/br
]);

$html = curl_exec($ch);
$http_code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
$err = curl_error($ch);
curl_close($ch);

if ($html === false || $http_code >= 400) {
    log_line("YT fetch fail id=$id http=$http_code err=$err");
    json_error(502, "yt fetch $http_code");
}

// --- 4. Extraer ytInitialPlayerResponse JSON
// Formato típico: var ytInitialPlayerResponse = {...};
$marker = 'ytInitialPlayerResponse';
$start = strpos($html, $marker);
if ($start === false) {
    log_line("no marker id=$id html_size=" . strlen($html));
    json_error(502, 'no playerResponse');
}

// Buscar primera "{" después del marker
$brace_start = strpos($html, '{', $start);
if ($brace_start === false) {
    json_error(502, 'no json start');
}

// Balance de llaves (contando strings)
$depth = 0;
$in_string = false;
$escape = false;
$end = null;
$len = strlen($html);
for ($i = $brace_start; $i < $len; $i++) {
    $c = $html[$i];
    if ($escape) { $escape = false; continue; }
    if ($c === '\\' && $in_string) { $escape = true; continue; }
    if ($c === '"') { $in_string = !$in_string; continue; }
    if ($in_string) continue;
    if ($c === '{') $depth++;
    elseif ($c === '}') {
        $depth--;
        if ($depth === 0) { $end = $i; break; }
    }
}
if ($end === null) {
    json_error(502, 'json unbalanced');
}

$json_str = substr($html, $brace_start, $end - $brace_start + 1);
$player = json_decode($json_str, true);
if (!is_array($player)) {
    json_error(502, 'json parse fail');
}

// --- 5. Filtrar audio adaptativo (itag 140 = m4a 128kbps preferido)
$streaming = $player['streamingData'] ?? null;
if (!is_array($streaming)) {
    json_error(503, 'no streamingData (private/deleted?)');
}
$formats = array_merge(
    $streaming['adaptiveFormats'] ?? [],
    $streaming['formats'] ?? []
);
if (empty($formats)) {
    json_error(503, 'no formats');
}

// Preferir audio-only, ordenar por bitrate desc
$audios = array_filter($formats, fn($f) => str_starts_with($f['mimeType'] ?? '', 'audio/'));
if (empty($audios)) {
    $audios = $formats;  // fallback: cualquier formato
}
usort($audios, fn($a, $b) => ($b['bitrate'] ?? 0) - ($a['bitrate'] ?? 0));

// El primero con URL directa (no signatureCipher)
$chosen_url = null;
foreach ($audios as $f) {
    if (!empty($f['url'])) {
        $chosen_url = $f['url'];
        break;
    }
}

if (!$chosen_url) {
    json_error(503, 'all formats have signatureCipher');
}

// --- 6. Guardar en cache + 302
@file_put_contents($cache_file, $chosen_url, LOCK_EX);
header('Cache-Control: private, max-age=' . CACHE_TTL_SEC);
header('X-Cache: MISS');
header('Location: ' . $chosen_url, true, 302);
exit;
