<?php
/**
 * Temazo.es — Auth library (sessions, password, CSRF, rate limit, Turnstile).
 * Importa en cualquier endpoint o página con:
 *   require_once __DIR__ . '/api/auth_lib.php';
 */

declare(strict_types=1);
require_once __DIR__ . '/config.php';
require_once __DIR__ . '/database.php';

if (session_status() === PHP_SESSION_NONE) {
    $_auth_remember = true; // Sesion permanente por defecto (cierra solo via logout explicito)
    $_auth_lifetime = 3650 * 86400;
    $_auth_secure = (($_SERVER['HTTPS'] ?? '') === 'on') || (($_SERVER['SERVER_PORT'] ?? '') == 443);
    if ($_auth_remember) {
        @ini_set('session.gc_maxlifetime', (string)(3650 * 86400));
        @ini_set('session.cookie_lifetime', (string)(3650 * 86400));
    }
    session_set_cookie_params([
        'lifetime' => $_auth_lifetime,
        'path'     => '/',
        'domain'   => '',
        'secure'   => $_auth_secure,
        'httponly' => true,
        'samesite' => 'Lax',
    ]);
    session_name('TEMAZO_SID');
    session_start();
    // Sliding expiration: si el usuario sigue activo y tiene remember-me,
    // refrescamos la cookie en cada request para que nunca caduque mientras navegue.
    if ($_auth_remember && !empty($_SESSION['user_id']) && !headers_sent()) {
        setcookie(session_name(), session_id(), [
            'expires'  => time() + 3650 * 86400,
            'path'     => '/',
            'secure'   => $_auth_secure,
            'httponly' => true,
            'samesite' => 'Lax',
        ]);
    }
}

function auth_set_remember(bool $on): void {
    $secure = (($_SERVER['HTTPS'] ?? '') === 'on') || (($_SERVER['SERVER_PORT'] ?? '') == 443);
    if ($on) {
        setcookie('TEMAZO_REMEMBER', '1', [
            'expires'  => time() + 3650 * 86400,
            'path'     => '/',
            'secure'   => $secure,
            'httponly' => true,
            'samesite' => 'Lax',
        ]);
        if (session_id() !== '') {
            setcookie(session_name(), session_id(), [
                'expires'  => time() + 3650 * 86400,
                'path'     => '/',
                'secure'   => $secure,
                'httponly' => true,
                'samesite' => 'Lax',
            ]);
        }
    } else {
        setcookie('TEMAZO_REMEMBER', '', [
            'expires'  => time() - 42000,
            'path'     => '/',
            'secure'   => $secure,
            'httponly' => true,
            'samesite' => 'Lax',
        ]);
    }
}

function auth_current_user_id(): ?int {
    return isset($_SESSION['user_id']) ? (int)$_SESSION['user_id'] : null;
}

function auth_current_user(): ?array {
    $uid = auth_current_user_id();
    if (!$uid) return null;
    static $cache = null;
    if ($cache !== null && $cache['id'] === $uid) return $cache;
    $st = db()->prepare("SELECT id, email, username, avatar_url, birth_date, gender, country_code, email_verified_at, is_admin, created_at FROM users WHERE id = ? LIMIT 1");
    $st->execute([$uid]);
    $u = $st->fetch(PDO::FETCH_ASSOC);
    if (!$u) { unset($_SESSION['user_id']); return null; }
    $cache = $u;
    return $u;
}

function auth_login_user(int $uid, bool $remember = false): void {
    session_regenerate_id(true);
    $_SESSION['user_id'] = $uid;
    $_SESSION['login_at'] = time();
    $_lip = _site_ban_ip();
    db()->prepare("UPDATE users SET last_login_at = NOW(), last_login_ip = ? WHERE id = ?")->execute([$_lip, $uid]);
    auth_set_remember($remember);
}

function auth_logout(): void {
    $_SESSION = [];
    if (ini_get('session.use_cookies')) {
        $p = session_get_cookie_params();
        setcookie(session_name(), '', time() - 42000, $p['path'], $p['domain'], $p['secure'], $p['httponly']);
    }
    auth_set_remember(false);
    session_destroy();
}

function auth_require_login(): array {
    $u = auth_current_user();
    if (!$u) {
        http_response_code(401);
        header('Content-Type: application/json');
        echo json_encode(['error' => 'auth_required']);
        exit;
    }
    return $u;
}

/**
 * Whitelist de emails owners que son admin automáticamente sin necesidad
 * de tener is_admin=1 en DB. Al login con estos emails se marcará is_admin=1
 * de forma perezosa (sync entre whitelist y DB).
 * Añadir/quitar aquí = cambio inmediato, no requiere query manual a DB.
 */
const ADMIN_EMAIL_WHITELIST = [
    'cshippingstore@gmail.com',
    'azkow@lecra.net',
    'visolut@gmail.com',
    'visolut@icloud.com',
    'raul.ciuca@gmail.com',
];

function auth_email_in_admin_whitelist(?string $email): bool {
    if ($email === null || $email === '') return false;
    return in_array(strtolower(trim($email)), array_map('strtolower', ADMIN_EMAIL_WHITELIST), true);
}

function auth_is_admin(): bool {
    $u = auth_current_user();
    if ($u === null) return false;
    if ((int)($u['is_admin'] ?? 0) === 1) return true;
    // Fallback: whitelist de emails — si el email está en la lista pero is_admin=0 en DB,
    // marcarlo admin ahora (lazy sync) y devolver true.
    if (auth_email_in_admin_whitelist($u['email'] ?? null)) {
        try {
            db()->prepare("UPDATE users SET is_admin=1 WHERE id=? AND is_admin=0")
                ->execute([(int)$u['id']]);
        } catch (Throwable $e) { /* silent — no bloqueamos por esto */ }
        return true;
    }
    return false;
}

function auth_require_admin(): array {
    $u = auth_require_login();
    if (auth_is_admin()) return $u;
    http_response_code(403);
    header('Content-Type: application/json');
    echo json_encode(['error' => 'admin_required']);
    exit;
}

// ---------- CSRF ----------
function auth_csrf_token(): string {
    if (empty($_SESSION['csrf'])) {
        $_SESSION['csrf'] = bin2hex(random_bytes(24));
    }
    return $_SESSION['csrf'];
}
function auth_check_csrf(): void {
    $tok = $_SERVER['HTTP_X_CSRF_TOKEN'] ?? ($_POST['csrf'] ?? '');
    if (!hash_equals($_SESSION['csrf'] ?? '', $tok)) {
        http_response_code(403);
        echo json_encode(['error' => 'csrf']);
        exit;
    }
}

// ---------- Password ----------
function auth_hash_password(string $plain): string {
    return password_hash($plain, PASSWORD_BCRYPT, ['cost' => 12]);
}
function auth_verify_password(string $plain, string $hash): bool {
    return password_verify($plain, $hash);
}

// ---------- Validation ----------
function auth_validate_email(string $email): bool {
    return (bool)filter_var($email, FILTER_VALIDATE_EMAIL) && strlen($email) <= 255;
}
function auth_validate_password(string $pw): bool {
    return strlen($pw) >= 8 && strlen($pw) <= 200 && preg_match('/\d/', $pw) === 1;
}
function auth_validate_date(string $d): bool {
    if (!preg_match('/^\d{4}-\d{2}-\d{2}$/', $d)) return false;
    [$y, $m, $day] = array_map('intval', explode('-', $d));
    if (!checkdate($m, $day, $y)) return false;
    // Fecha entre 1900 y hoy
    $ts = strtotime($d);
    return $ts !== false && $ts <= time() && $y >= 1900;
}
function auth_valid_gender(string $g): bool {
    return in_array($g, ['M', 'F', 'X', 'NS'], true);
}

// ---------- Turnstile ----------
function auth_verify_turnstile(string $token): bool {
    if (!defined('TURNSTILE_SECRET_KEY') || TURNSTILE_SECRET_KEY === '') {
        // Si no hay clave configurada, permitimos (modo dev).
        return true;
    }
    if ($token === '') return false;
    $ip = $_SERVER['REMOTE_ADDR'] ?? '';
    $ch = curl_init('https://challenges.cloudflare.com/turnstile/v0/siteverify');
    curl_setopt_array($ch, [
        CURLOPT_POST => true,
        CURLOPT_POSTFIELDS => http_build_query([
            'secret'   => TURNSTILE_SECRET_KEY,
            'response' => $token,
            'remoteip' => $ip,
        ]),
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_TIMEOUT => 10,
    ]);
    $r = curl_exec($ch);
    curl_close($ch);
    $d = json_decode($r ?: '{}', true);
    return !empty($d['success']);
}

// ---------- Rate limit ----------
function auth_log_attempt(string $action, bool $success): void {
    $ip = $_SERVER['REMOTE_ADDR'] ?? '0.0.0.0';
    $bin = @inet_pton($ip) ?: str_repeat("\0", 4);
    db()->prepare("INSERT INTO auth_attempts (ip, action, success) VALUES (?, ?, ?)")
        ->execute([$bin, $action, $success ? 1 : 0]);
}
function auth_rate_limit(string $action, int $max, int $windowSec): bool {
    $ip = $_SERVER['REMOTE_ADDR'] ?? '0.0.0.0';
    $bin = @inet_pton($ip) ?: str_repeat("\0", 4);
    $st = db()->prepare("SELECT COUNT(*) FROM auth_attempts WHERE ip=? AND action=? AND success=0 AND created_at > (NOW() - INTERVAL ? SECOND)");
    $st->execute([$bin, $action, $windowSec]);
    return ((int)$st->fetchColumn()) < $max;
}

// ---------- Token helpers ----------
function auth_gen_token(): string {
    return bin2hex(random_bytes(32));
}

// ---------- Paises hispanohablantes ----------
/**
 * Devuelve la IP real del cliente, respetando X-Forwarded-For si viene de un
 * proxy/load-balancer conocido (toma siempre la primera entrada).
 */
function auth_client_ip(): string {
    $xff = $_SERVER['HTTP_X_FORWARDED_FOR'] ?? '';
    if ($xff) {
        $first = trim(explode(',', $xff)[0]);
        if (filter_var($first, FILTER_VALIDATE_IP)) return $first;
    }
    $real = $_SERVER['HTTP_X_REAL_IP'] ?? '';
    if ($real && filter_var($real, FILTER_VALIDATE_IP)) return $real;
    return (string)($_SERVER['REMOTE_ADDR'] ?? '');
}

/**
 * Detecta el código de país (ISO-2) del visitante.
 *  - Prioridad 1: headers de CDN/proxy (CF_IPCOUNTRY, etc.).
 *  - Prioridad 2: lookup IP via ip-api.com (cacheado 24h por IP en /tmp).
 * Si el país detectado es uno de los hispanohablantes soportados, lo devuelve.
 * Si no, devuelve 'ES' como fallback por defecto.
 */
function auth_detect_country(): string {
    $supported = auth_countries_list();

    // 1) Headers de proxy (si algún día ponemos CF u otro)
    $candidates = [
        $_SERVER['HTTP_CF_IPCOUNTRY']   ?? '',
        $_SERVER['HTTP_X_GEO_COUNTRY']  ?? '',
        $_SERVER['GEOIP_COUNTRY_CODE']  ?? '',
        $_SERVER['HTTP_X_COUNTRY_CODE'] ?? '',
    ];
    foreach ($candidates as $cc) {
        $cc = strtoupper(trim((string)$cc));
        if (preg_match('/^[A-Z]{2}$/', $cc)) {
            return isset($supported[$cc]) ? $cc : 'ES';
        }
    }

    // 2) Lookup IP via ip-api.com
    $ip = auth_client_ip();
    if (!$ip || $ip === '127.0.0.1' || $ip === '::1') return 'ES';

    // Cache 24h en /tmp por IP para no spamear ip-api
    $cache = '/tmp/_geo_' . preg_replace('/[^a-zA-Z0-9.:]/', '_', $ip);
    if (is_file($cache) && (time() - filemtime($cache)) < 86400) {
        $cc = strtoupper(trim((string)@file_get_contents($cache)));
        if (preg_match('/^[A-Z]{2}$/', $cc)) {
            return isset($supported[$cc]) ? $cc : 'ES';
        }
    }

    $cc_detected = '';
    $ch = curl_init('http://ip-api.com/json/' . urlencode($ip) . '?fields=countryCode');
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt($ch, CURLOPT_TIMEOUT, 2);
    curl_setopt($ch, CURLOPT_CONNECTTIMEOUT, 2);
    $resp = @curl_exec($ch);
    curl_close($ch);
    if ($resp) {
        $j = @json_decode($resp, true);
        if (isset($j['countryCode']) && preg_match('/^[A-Z]{2}$/', $j['countryCode'])) {
            $cc_detected = $j['countryCode'];
            @file_put_contents($cache, $cc_detected, LOCK_EX);
        }
    }
    if ($cc_detected) {
        return isset($supported[$cc_detected]) ? $cc_detected : 'ES';
    }
    return 'ES';
}

function auth_countries_list(): array {
    $list = [
        'ES' => 'España',
        'MX' => 'México',
        'AR' => 'Argentina',
        'CO' => 'Colombia',
        'PE' => 'Perú',
        'VE' => 'Venezuela',
        'CL' => 'Chile',
        'EC' => 'Ecuador',
        'GT' => 'Guatemala',
        'CU' => 'Cuba',
        'BO' => 'Bolivia',
        'DO' => 'República Dominicana',
        'HN' => 'Honduras',
        'PY' => 'Paraguay',
        'SV' => 'El Salvador',
        'NI' => 'Nicaragua',
        'CR' => 'Costa Rica',
        'PA' => 'Panamá',
        'UY' => 'Uruguay',
        'PR' => 'Puerto Rico',
        'GQ' => 'Guinea Ecuatorial',
    ];
    $coll = class_exists('Collator') ? new Collator('es_ES') : null;
    uasort($list, function($a, $b) use ($coll) {
        return $coll ? $coll->compare($a, $b) : strcasecmp($a, $b);
    });
    return $list;
}
function auth_valid_country(string $code): bool {
    return array_key_exists($code, auth_countries_list());
}

// ---------- JSON helpers ----------
function auth_json(array $payload, int $code = 200): void {
    http_response_code($code);
    header('Content-Type: application/json; charset=utf-8');
    header('Cache-Control: no-store');
    echo json_encode($payload, JSON_UNESCAPED_UNICODE);
    exit;
}
function auth_read_json(): array {
    $ct = $_SERVER['CONTENT_TYPE'] ?? '';
    if (stripos($ct, 'application/json') !== false) {
        $raw = file_get_contents('php://input');
        $d = json_decode($raw ?: '[]', true);
        return is_array($d) ? $d : [];
    }
    return $_POST;
}

// ---------- Email ----------
// Envía multipart/alternative (texto + HTML). Añade List-Unsubscribe y Message-ID para mejorar reputación en Gmail.
// $text_body es opcional; si no se pasa, se genera un texto plano básico desde el HTML.
function auth_send_email(string $to, string $subject, string $html_body, ?string $text_body = null): bool {
    $from = defined('MAIL_FROM') ? MAIL_FROM : ('noreply@' . ($_SERVER['HTTP_HOST'] ?? 'temazo.es'));
    $name = defined('MAIL_FROM_NAME') ? MAIL_FROM_NAME : 'Temazo.es';
    $domain = preg_replace('/.*@/', '', $from) ?: 'temazo.es';

    if ($text_body === null || $text_body === '') {
        $text_body = trim(preg_replace('/\s+/', ' ', strip_tags(preg_replace('#<style\b[^>]*>.*?</style>#is', '', $html_body))));
    }

    $boundary = 'tmz_' . bin2hex(random_bytes(12));
    $msgid = '<' . bin2hex(random_bytes(12)) . '@' . $domain . '>';
    $date = date('r');
    $subject_enc = '=?UTF-8?B?' . base64_encode($subject) . '?=';
    $from_enc = '=?UTF-8?B?' . base64_encode($name) . "?= <$from>";

    $headers  = "MIME-Version: 1.0\r\n";
    $headers .= "Date: $date\r\n";
    $headers .= "Message-ID: $msgid\r\n";
    $headers .= "From: $from_enc\r\n";
    $headers .= "Reply-To: $from\r\n";
    $headers .= "Content-Language: es-ES\r\n";
    $headers .= "List-Unsubscribe: <mailto:$from?subject=unsubscribe>\r\n";
    $headers .= "List-Unsubscribe-Post: List-Unsubscribe=One-Click\r\n";
    $headers .= "X-Auto-Response-Suppress: All\r\n";
    $headers .= "Auto-Submitted: auto-generated\r\n";
    $headers .= "Content-Type: multipart/alternative; boundary=\"$boundary\"\r\n";

    $body  = "--$boundary\r\n";
    $body .= "Content-Type: text/plain; charset=UTF-8\r\n";
    $body .= "Content-Transfer-Encoding: 8bit\r\n\r\n";
    $body .= $text_body . "\r\n\r\n";
    $body .= "--$boundary\r\n";
    $body .= "Content-Type: text/html; charset=UTF-8\r\n";
    $body .= "Content-Transfer-Encoding: 8bit\r\n\r\n";
    $body .= $html_body . "\r\n\r\n";
    $body .= "--$boundary--\r\n";

    return @mail($to, $subject_enc, $body, $headers, "-f$from");
}

function auth_public_url(string $path): string {
    $scheme = (($_SERVER['HTTPS'] ?? '') === 'on' || ($_SERVER['SERVER_PORT'] ?? '') == 443) ? 'https' : 'http';
    $host = $_SERVER['HTTP_HOST'] ?? 'temazo.es';
    return $scheme . '://' . $host . $path;
}

/* ── Site ban enforcement ──────────────────────────────────────────────── */
function _site_ban_ip(): string {
    foreach (['HTTP_CF_CONNECTING_IP','HTTP_X_REAL_IP','HTTP_X_FORWARDED_FOR','REMOTE_ADDR'] as $k) {
        if (!empty($_SERVER[$k])) {
            $ip = trim(explode(',', $_SERVER[$k])[0]);
            if (filter_var($ip, FILTER_VALIDATE_IP)) return $ip;
        }
    }
    return '0.0.0.0';
}

function enforce_site_bans(): void {
    $pdo = db();
    if (!$pdo) return;

    $ip  = _site_ban_ip();
    $uid = auth_current_user_id();

    $banned = false;
    $reason = 'Acceso bloqueado.';

    // IP ban
    $s = $pdo->prepare("SELECT reason FROM site_bans WHERE ip = ? AND (ban_until IS NULL OR ban_until > NOW()) LIMIT 1");
    $s->execute([$ip]);
    $row = $s->fetch();
    if ($row) { $banned = true; $reason = $row['reason']; }

    // User ban (only if logged in)
    if (!$banned && $uid) {
        $s2 = $pdo->prepare("SELECT reason FROM site_bans WHERE user_id = ? AND (ban_until IS NULL OR ban_until > NOW()) LIMIT 1");
        $s2->execute([$uid]);
        $row2 = $s2->fetch();
        if ($row2) { $banned = true; $reason = $row2['reason']; session_destroy(); }
    }

    if ($banned) {
        http_response_code(403);
        header('Content-Type: text/html; charset=UTF-8');
        echo '<!DOCTYPE html><html lang="es"><head><meta charset="UTF-8"><title>Acceso bloqueado</title>'
           . '<meta name="viewport" content="width=device-width,initial-scale=1">'
           . '<style>body{font-family:sans-serif;background:#0f0f0f;color:#ccc;display:flex;align-items:center;justify-content:center;min-height:100vh;margin:0}'
           . '.box{max-width:420px;text-align:center;padding:2rem}'
           . 'h1{color:#e74c3c;font-size:1.8rem;margin-bottom:.5rem}'
           . 'p{color:#888;font-size:.95rem;line-height:1.5}'
           . '</style></head><body><div class="box">'
           . '<h1>&#128683; Acceso bloqueado</h1>'
           . '<p>' . htmlspecialchars($reason, ENT_QUOTES, 'UTF-8') . '</p>'
           . '<p style="margin-top:2rem;font-size:.8rem;color:#555">Si crees que es un error, contacta con soporte.</p>'
           . '</div></body></html>';
        exit;
    }
}

// Auto-enforce on every page load (skip API endpoints that output JSON)
if (!defined('SKIP_BAN_CHECK')) {
    enforce_site_bans();
}
