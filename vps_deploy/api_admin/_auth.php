<?php
/**
 * Temazo.es — Auth endpoint
 * POST /api/auth.php?a=register  {email, password, birth_date, gender, country_code, turnstile_token}
 * GET  /api/auth.php?a=verify&token=...
 * POST /api/auth.php?a=login     {email, password}
 * POST /api/auth.php?a=logout
 * GET  /api/auth.php?a=me
 * POST /api/auth.php?a=forgot    {email}
 * POST /api/auth.php?a=reset     {token, password}
 * POST /api/auth.php?a=delete_account  {password} (auth + CSRF)
 * GET  /api/auth.php?a=csrf      -> {csrf, user: {...}|null, turnstile_site_key}
 */
declare(strict_types=1);
require_once __DIR__ . '/auth_lib.php';

$action = $_GET['a'] ?? '';
$method = $_SERVER['REQUEST_METHOD'];

switch ($action) {
    case 'csrf':
        $u = auth_current_user();
        // Exponer el primer client_id de Google (Web) al frontend para Google Sign-In
        $google_cid = '';
        $gconf = @include __DIR__ . '/google_config.php';
        if (is_array($gconf) && !empty($gconf)) $google_cid = (string)$gconf[0];
        auth_json([
            'csrf' => auth_csrf_token(),
            'user' => $u ? ['id' => (int)$u['id'], 'email' => $u['email']] : null,
            'turnstile_site_key' => defined('TURNSTILE_SITE_KEY') ? TURNSTILE_SITE_KEY : '',
            'countries' => auth_countries_list(),
            'google_client_id' => $google_cid,
        ]);
        break;

    case 'register':
        if ($method !== 'POST') auth_json(['error' => 'method'], 405);
        if (!auth_rate_limit('register', 5, 900)) auth_json(['error' => 'rate_limit'], 429);
        $d = auth_read_json();
        $email  = strtolower(trim((string)($d['email'] ?? '')));
        $pw     = (string)($d['password'] ?? '');
        $uname  = strtolower(trim((string)($d['username'] ?? '')));
        $ts_tok = (string)($d['turnstile_token'] ?? '');

        if (!auth_validate_email($email))   { auth_log_attempt('register', false); auth_json(['error' => 'email_invalid'], 400); }
        if (!auth_validate_password($pw))   { auth_log_attempt('register', false); auth_json(['error' => 'password_weak', 'msg' => 'Mínimo 8 caracteres con al menos un número'], 400); }
        if (!preg_match('/^[a-z0-9_]{3,30}$/', $uname)) {
            auth_log_attempt('register', false);
            auth_json(['error' => 'username_format', 'msg' => 'El alias debe tener 3-30 caracteres: solo a-z, 0-9 y _'], 400);
        }
        $reserved = ['admin','root','temazo','api','null','undefined','soporte','support','mod','staff','system','www','help','contact'];
        if (in_array($uname, $reserved, true)) { auth_log_attempt('register', false); auth_json(['error' => 'username_reserved'], 400); }
        if (!auth_verify_turnstile($ts_tok)) { auth_log_attempt('register', false); auth_json(['error' => 'captcha_failed'], 400); }

        $pdo = db();
        // Username ya tomado → error claro (no es info sensible — perfil público)
        $chk = $pdo->prepare("SELECT 1 FROM users WHERE username=? LIMIT 1");
        $chk->execute([$uname]);
        if ($chk->fetchColumn()) { auth_log_attempt('register', false); auth_json(['error' => 'username_taken', 'msg' => 'Ese alias ya está en uso.'], 409); }

        // Email ya usado → mensaje genérico (no confirmamos existencia)
        $st = $pdo->prepare("SELECT id, email_verified_at FROM users WHERE email = ? LIMIT 1");
        $st->execute([$email]);
        $existing = $st->fetch(PDO::FETCH_ASSOC);
        if ($existing) {
            auth_log_attempt('register', false);
            auth_json(['ok' => true, 'msg' => 'Si este email es válido, te hemos enviado un correo de verificación.']);
        }
        try {
            $pdo->beginTransaction();
            $cc = auth_detect_country(); // ISO-2 de país soportado, fallback 'ES'
            $ins = $pdo->prepare("INSERT INTO users (email, password_hash, password_set, username, gender, country_code) VALUES (?,?,?,?,?,?)");
            $ins->execute([$email, auth_hash_password($pw), 1, $uname, 'NS', $cc]);
            $uid = (int)$pdo->lastInsertId();
            $token = auth_gen_token();
            $pdo->prepare("INSERT INTO email_verification_tokens (token, user_id, expires_at) VALUES (?, ?, DATE_ADD(NOW(), INTERVAL 24 HOUR))")
                ->execute([$token, $uid]);
            $pdo->commit();
        } catch (Throwable $e) {
            $pdo->rollBack();
            auth_log_attempt('register', false);
            auth_json(['error' => 'server', 'detail' => $e->getMessage()], 500);
        }

        $verify_url = auth_public_url('/api/auth.php?a=verify&token=' . $token);
        $html = auth_render_verify_email($verify_url);
        $text = auth_render_verify_email_text($verify_url);
        auth_send_email($email, 'Verifica tu cuenta en Temazo.es', $html, $text);
        auth_log_attempt('register', true);
        auth_json(['ok' => true, 'msg' => 'Revisa tu correo para confirmar la cuenta en las próximas 24 horas.']);
        break;

    case 'verify':
        $token = (string)($_GET['token'] ?? '');
        if (!preg_match('/^[a-f0-9]{64}$/', $token)) {
            header('Location: /login.php?verified=0&reason=bad_token'); exit;
        }
        $pdo = db();
        $st = $pdo->prepare("SELECT t.user_id FROM email_verification_tokens t WHERE t.token=? AND t.used_at IS NULL AND t.expires_at > NOW() LIMIT 1");
        $st->execute([$token]);
        $row = $st->fetch(PDO::FETCH_ASSOC);
        if (!$row) {
            header('Location: /login.php?verified=0&reason=expired'); exit;
        }
        $uid = (int)$row['user_id'];
        $pdo->prepare("UPDATE users SET email_verified_at = NOW() WHERE id = ? AND email_verified_at IS NULL")->execute([$uid]);
        $pdo->prepare("UPDATE email_verification_tokens SET used_at = NOW() WHERE token = ?")->execute([$token]);
        auth_login_user($uid);
        header('Location: /mi-cuenta.php?verified=1'); exit;
        break;

    case 'login':
        if ($method !== 'POST') auth_json(['error' => 'method'], 405);
        if (!auth_rate_limit('login', 8, 900)) auth_json(['error' => 'rate_limit'], 429);
        $d = auth_read_json();
        $email = strtolower(trim((string)($d['email'] ?? '')));
        $pw    = (string)($d['password'] ?? '');
        $remember = !empty($d['remember']);
        if (!auth_validate_email($email) || $pw === '') {
            auth_log_attempt('login', false);
            auth_json(['error' => 'invalid_credentials'], 400);
        }
        $st = db()->prepare("SELECT id, password_hash, email_verified_at FROM users WHERE email = ? LIMIT 1");
        $st->execute([$email]);
        $u = $st->fetch(PDO::FETCH_ASSOC);
        if (!$u || !auth_verify_password($pw, $u['password_hash'])) {
            auth_log_attempt('login', false);
            auth_json(['error' => 'invalid_credentials'], 401);
        }
        if (!$u['email_verified_at']) {
            auth_log_attempt('login', false);
            auth_json(['error' => 'not_verified', 'msg' => 'Debes verificar tu email antes de entrar.'], 403);
        }
        auth_login_user((int)$u['id'], $remember);
        auth_log_attempt('login', true);
        auth_json(['ok' => true, 'user' => ['id' => (int)$u['id'], 'email' => $email], 'remember' => $remember]);
        break;

    case 'logout':
        auth_check_csrf();
        auth_logout();
        auth_json(['ok' => true]);
        break;

    case 'me':
        $u = auth_current_user();
        auth_json(['user' => $u ? [
            'id' => (int)$u['id'], 'email' => $u['email'],
            'birth_date' => $u['birth_date'], 'gender' => $u['gender'],
            'country_code' => $u['country_code'],
        ] : null]);
        break;

    case 'google': {
        if ($method !== 'POST') auth_json(['error' => 'method'], 405);
        if (!auth_rate_limit('google_login', 30, 900)) auth_json(['error' => 'rate_limit'], 429);
        $d = auth_read_json();
        $id_token = (string)($d['id_token'] ?? '');
        if ($id_token === '') auth_json(['error' => 'bad_input'], 400);

        $allowed = @include __DIR__ . '/google_config.php';
        if (!is_array($allowed) || empty($allowed)) {
            auth_json(['error' => 'google_not_configured'], 503);
        }

        // Validar token contra Google
        $ch = curl_init('https://oauth2.googleapis.com/tokeninfo?id_token=' . urlencode($id_token));
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($ch, CURLOPT_TIMEOUT, 8);
        $resp = curl_exec($ch);
        $code = (int)curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);
        if ($code !== 200 || !$resp) auth_json(['error' => 'invalid_token'], 401);
        $info = json_decode($resp, true);
        if (!is_array($info) || empty($info['email'])) auth_json(['error' => 'invalid_token'], 401);
        $iss = (string)($info['iss'] ?? '');
        if ($iss !== 'accounts.google.com' && $iss !== 'https://accounts.google.com') auth_json(['error' => 'bad_issuer'], 401);
        if (empty($info['email_verified']) && $info['email_verified'] !== 'true' && $info['email_verified'] !== true) auth_json(['error' => 'email_not_verified'], 401);
        $aud = (string)($info['aud'] ?? '');
        if (!in_array($aud, $allowed, true)) auth_json(['error' => 'invalid_audience'], 401);
        if (!empty($info['exp']) && (int)$info['exp'] < time()) auth_json(['error' => 'token_expired'], 401);

        $email = strtolower(trim((string)$info['email']));
        if (!auth_validate_email($email)) auth_json(['error' => 'invalid_email'], 400);
        $picture = isset($info['picture']) ? (string)$info['picture'] : null;
        $name = isset($info['name']) ? (string)$info['name'] : null;

        $pdo = db();
        $st = $pdo->prepare("SELECT id, avatar_url, username, birth_date FROM users WHERE email=? LIMIT 1");
        $st->execute([$email]);
        $u = $st->fetch(PDO::FETCH_ASSOC);

        if ($u) {
            $uid = (int)$u['id'];
            $pdo->prepare("UPDATE users SET email_verified_at = COALESCE(email_verified_at, NOW()), last_login_at = NOW() WHERE id = ?")->execute([$uid]);
            if (empty($u['avatar_url']) && !empty($picture)) {
                $pdo->prepare("UPDATE users SET avatar_url=? WHERE id=?")->execute([$picture, $uid]);
            }
            $needs_profile = empty($u['username']) || empty($u['birth_date']);
        } else {
            // Cuenta nueva via Google. password_hash placeholder no-login.
            // Username, birth_date y password real quedan vacios → frontend pide complete-profile.
            $placeholder = password_hash(bin2hex(random_bytes(16)), PASSWORD_BCRYPT);
            $cc = auth_detect_country(); // ISO-2 soportado, fallback 'ES'
            $ins = $pdo->prepare("INSERT INTO users (email, password_hash, password_set, gender, country_code, email_verified_at, last_login_at, avatar_url) VALUES (?,?,?,?,?, NOW(), NOW(), ?)");
            $ins->execute([$email, $placeholder, 0, 'NS', $cc, $picture]);
            $uid = (int)$pdo->lastInsertId();
            $needs_profile = true;
        }

        auth_login_user($uid, true);
        auth_log_attempt('login_google', true);
        auth_json([
            'ok' => true,
            'user' => ['id' => $uid, 'email' => $email],
            'csrf' => auth_csrf_token(),
            'needs_profile' => (bool)$needs_profile,
        ]);
        break;
    }

    case 'forgot':
        if ($method !== 'POST') auth_json(['error' => 'method'], 405);
        if (!auth_rate_limit('forgot', 5, 900)) auth_json(['error' => 'rate_limit'], 429);
        $d = auth_read_json();
        $email = strtolower(trim((string)($d['email'] ?? '')));
        if (auth_validate_email($email)) {
            $pdo = db();
            $st = $pdo->prepare("SELECT id FROM users WHERE email = ? AND email_verified_at IS NOT NULL LIMIT 1");
            $st->execute([$email]);
            $u = $st->fetch(PDO::FETCH_ASSOC);
            if ($u) {
                $token = auth_gen_token();
                $pdo->prepare("INSERT INTO password_reset_tokens (token, user_id, expires_at) VALUES (?, ?, DATE_ADD(NOW(), INTERVAL 1 HOUR))")
                    ->execute([$token, (int)$u['id']]);
                $reset_url = auth_public_url('/reset.php?token=' . $token);
                auth_send_email($email, 'Restablece tu contraseña — Temazo.es',
                    auth_render_reset_email($reset_url),
                    auth_render_reset_email_text($reset_url));
            }
        }
        auth_log_attempt('forgot', true);
        auth_json(['ok' => true, 'msg' => 'Si la cuenta existe, te hemos enviado un email.']);
        break;

    case 'delete_account':
        if ($method !== 'POST') auth_json(['error' => 'method'], 405);
        $u = auth_require_login();
        auth_check_csrf();
        $d = auth_read_json();
        $pw = (string)($d['password'] ?? '');
        $uid = (int)$u['id'];
        $st = db()->prepare("SELECT password_hash FROM users WHERE id = ? LIMIT 1");
        $st->execute([$uid]);
        $hash = $st->fetchColumn();
        if (!$hash || !auth_verify_password($pw, (string)$hash)) auth_json(['error' => 'bad_password'], 403);
        db()->prepare("DELETE FROM users WHERE id = ?")->execute([$uid]);
        auth_logout();
        auth_json(['ok' => true]);
        break;

    case 'reset':
        if ($method !== 'POST') auth_json(['error' => 'method'], 405);
        $d = auth_read_json();
        $token = (string)($d['token'] ?? '');
        $pw    = (string)($d['password'] ?? '');
        if (!preg_match('/^[a-f0-9]{64}$/', $token)) auth_json(['error' => 'bad_token'], 400);
        if (!auth_validate_password($pw))           auth_json(['error' => 'password_weak'], 400);
        $pdo = db();
        $st = $pdo->prepare("SELECT user_id FROM password_reset_tokens WHERE token=? AND used_at IS NULL AND expires_at > NOW() LIMIT 1");
        $st->execute([$token]);
        $row = $st->fetch(PDO::FETCH_ASSOC);
        if (!$row) auth_json(['error' => 'expired'], 400);
        $uid = (int)$row['user_id'];
        $pdo->prepare("UPDATE users SET password_hash = ? WHERE id = ?")->execute([auth_hash_password($pw), $uid]);
        $pdo->prepare("UPDATE password_reset_tokens SET used_at = NOW() WHERE token = ?")->execute([$token]);
        auth_login_user($uid);
        auth_json(['ok' => true]);
        break;

    default:
        auth_json(['error' => 'unknown_action'], 400);
}

// ------- Email templates -------
// Mantenemos el diseño bonito: lang="es" (para que Gmail no ofrezca traducir), hero con gradiente, botón con gradiente.
// Quitamos el preheader oculto (clásico disparador de spam) y enviamos en multipart con alternativa de texto plano.
function auth_email_layout(string $hero_title, string $body_html): string {
    $safe_hero = htmlspecialchars($hero_title, ENT_QUOTES);
    return '<!doctype html>
<html lang="es" xml:lang="es" xmlns="http://www.w3.org/1999/xhtml">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta http-equiv="Content-Language" content="es-ES">
<meta name="color-scheme" content="light dark">
<meta name="supported-color-schemes" content="light dark">
<title>Temazo.es</title>
</head>
<body lang="es" style="margin:0;padding:0;background:#f3f1fb;font-family:-apple-system,BlinkMacSystemFont,\'Segoe UI\',Roboto,Helvetica,Arial,sans-serif;color:#1a1a2e;-webkit-text-size-adjust:100%;">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background:#f3f1fb;padding:24px 12px;">
  <tr><td align="center">
    <table role="presentation" width="560" cellpadding="0" cellspacing="0" border="0" style="max-width:560px;width:100%;border-radius:18px;overflow:hidden;background:#ffffff;">
      <!-- Hero -->
      <tr><td style="background:linear-gradient(135deg,#e74c8b 0%,#a855f7 50%,#6366f1 100%);padding:36px 32px;text-align:center;">
        <div style="font-size:28px;font-weight:800;color:#ffffff;letter-spacing:-.5px;margin:0 0 4px;">Temazo<span style="opacity:.85;">.es</span></div>
        <div style="font-size:13px;color:rgba(255,255,255,.85);letter-spacing:.4px;text-transform:uppercase;">Los temazos del momento</div>
      </td></tr>
      <!-- Body -->
      <tr><td style="padding:36px 36px 12px;">
        <h1 style="margin:0 0 14px;font-size:22px;line-height:1.25;color:#1a1a2e;font-weight:700;">'.$safe_hero.'</h1>
        '.$body_html.'
      </td></tr>
      <!-- Footer -->
      <tr><td style="padding:24px 36px 32px;border-top:1px solid #ececf5;">
        <p style="margin:0 0 6px;font-size:12px;color:#8a8aa6;line-height:1.5;">Este mensaje fue enviado automáticamente desde <strong style="color:#6a5acd;">Temazo.es</strong>. Si no lo esperabas, puedes ignorarlo sin problema.</p>
        <p style="margin:0;font-size:12px;color:#8a8aa6;">© '.date('Y').' Temazo.es · <a href="https://temazo.es" style="color:#a855f7;text-decoration:none;">temazo.es</a></p>
      </td></tr>
    </table>
  </td></tr>
</table>
</body></html>';
}

function auth_render_verify_email(string $url): string {
    $safe = htmlspecialchars($url, ENT_QUOTES);
    $body = '
<p style="margin:0 0 14px;font-size:15px;line-height:1.6;color:#3a3a55;">¡Hola y bienvenido! Estás a un clic de empezar a descubrir los <strong>temazos</strong> que están petándolo en España y Latinoamérica.</p>
<p style="margin:0 0 22px;font-size:15px;line-height:1.6;color:#3a3a55;">Solo necesitamos que confirmes tu correo para activar tu cuenta. El enlace estará disponible durante <strong>24 horas</strong>; después la cuenta se elimina automáticamente si no la verificas.</p>
<table role="presentation" cellpadding="0" cellspacing="0" border="0" align="center" style="margin:12px auto 22px;">
  <tr><td style="border-radius:28px;background:linear-gradient(135deg,#e74c8b,#a855f7);">
    <a href="'.$safe.'" style="display:inline-block;padding:14px 34px;font-size:15px;font-weight:700;color:#ffffff;text-decoration:none;border-radius:28px;">Verificar mi cuenta</a>
  </td></tr>
</table>
<p style="margin:0 0 8px;font-size:13px;color:#8a8aa6;">Una vez verificado podrás:</p>
<ul style="margin:0 0 22px;padding:0 0 0 20px;font-size:14px;line-height:1.7;color:#3a3a55;">
  <li>Guardar canciones favoritas con un clic</li>
  <li>Crear playlists privadas con tus temazos</li>
  <li>Seguir los rankings actualizados cada pocas horas</li>
</ul>
<p style="margin:18px 0 0;font-size:12px;color:#8a8aa6;line-height:1.5;">¿El botón no funciona? Copia y pega este enlace en el navegador:<br><a href="'.$safe.'" style="color:#a855f7;word-break:break-all;">'.$safe.'</a></p>';
    return auth_email_layout('Confirma tu correo', $body);
}

function auth_render_verify_email_text(string $url): string {
    return "Hola y bienvenido a Temazo.es.\r\n\r\n"
         . "Para activar tu cuenta, confirma tu correo visitando el siguiente enlace (válido durante 24 horas):\r\n\r\n"
         . $url . "\r\n\r\n"
         . "Una vez verificado podrás guardar favoritos, crear playlists y seguir los rankings.\r\n\r\n"
         . "Si no te registraste en Temazo.es, ignora este mensaje.\r\n\r\n"
         . "— Equipo Temazo.es\r\n";
}

function auth_render_reset_email(string $url): string {
    $safe = htmlspecialchars($url, ENT_QUOTES);
    $body = '
<p style="margin:0 0 14px;font-size:15px;line-height:1.6;color:#3a3a55;">Hemos recibido una solicitud para restablecer la contraseña de tu cuenta en Temazo.es.</p>
<p style="margin:0 0 22px;font-size:15px;line-height:1.6;color:#3a3a55;">Haz clic en el botón para elegir una nueva contraseña. El enlace es válido durante <strong>1 hora</strong>.</p>
<table role="presentation" cellpadding="0" cellspacing="0" border="0" align="center" style="margin:12px auto 22px;">
  <tr><td style="border-radius:28px;background:linear-gradient(135deg,#e74c8b,#a855f7);">
    <a href="'.$safe.'" style="display:inline-block;padding:14px 34px;font-size:15px;font-weight:700;color:#ffffff;text-decoration:none;border-radius:28px;">Cambiar mi contraseña</a>
  </td></tr>
</table>
<p style="margin:18px 0 10px;font-size:13px;color:#8a8aa6;line-height:1.5;">Si no has solicitado este cambio, puedes ignorar este correo tranquilamente — tu contraseña no se modificará y nadie ha accedido a tu cuenta.</p>
<p style="margin:0;font-size:12px;color:#8a8aa6;line-height:1.5;">Enlace directo:<br><a href="'.$safe.'" style="color:#a855f7;word-break:break-all;">'.$safe.'</a></p>';
    return auth_email_layout('Restablece tu contraseña', $body);
}

function auth_render_reset_email_text(string $url): string {
    return "Hemos recibido una solicitud para restablecer la contraseña de tu cuenta en Temazo.es.\r\n\r\n"
         . "Para elegir una nueva contraseña, visita el siguiente enlace (válido durante 1 hora):\r\n\r\n"
         . $url . "\r\n\r\n"
         . "Si no has solicitado este cambio, puedes ignorar este correo; tu contraseña no se modificará.\r\n\r\n"
         . "— Equipo Temazo.es\r\n";
}
