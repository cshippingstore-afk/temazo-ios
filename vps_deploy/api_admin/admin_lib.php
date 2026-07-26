<?php
/**
 * Temazo.es — Admin library.
 * Helpers reutilizables por todos los endpoints /api/admin/*.
 *   - admin_log()          → audit trail en tabla admin_actions
 *   - admin_json_input()   → parsea JSON body con validacion
 *   - admin_json_ok/err    → responses tipadas
 *   - admin_fetch_track/artist/album (bypass hidden filter)
 *   - admin_get_int/str    → validacion de inputs
 *   - admin_yt_id_valid    → regex 11-char YouTube id
 *
 * Todos los endpoints admin DEBEN llamar auth_require_admin() al inicio.
 */

declare(strict_types=1);
require_once __DIR__ . '/../auth_lib.php';

function admin_json_ok(array $data = []): void {
    header('Content-Type: application/json');
    echo json_encode(['ok' => true] + $data);
    exit;
}

function admin_json_err(int $status, string $code, string $msg = '', array $extra = []): void {
    http_response_code($status);
    header('Content-Type: application/json');
    echo json_encode(['ok' => false, 'error' => $code, 'msg' => $msg] + $extra);
    exit;
}

function admin_json_input(): array {
    $raw = file_get_contents('php://input');
    if ($raw === '' || $raw === false) return [];
    $data = json_decode($raw, true);
    if (!is_array($data)) admin_json_err(400, 'invalid_json', 'Body must be JSON object');
    return $data;
}

function admin_get_int(array $src, string $key, ?int $min = null, ?int $max = null): int {
    if (!isset($src[$key])) admin_json_err(400, 'missing_field', "Missing $key");
    $v = filter_var($src[$key], FILTER_VALIDATE_INT);
    if ($v === false) admin_json_err(400, 'invalid_int', "$key must be int");
    if ($min !== null && $v < $min) admin_json_err(400, 'out_of_range', "$key < $min");
    if ($max !== null && $v > $max) admin_json_err(400, 'out_of_range', "$key > $max");
    return $v;
}

function admin_get_str(array $src, string $key, int $maxLen = 500, bool $allowEmpty = false): string {
    if (!isset($src[$key])) admin_json_err(400, 'missing_field', "Missing $key");
    $v = trim((string)$src[$key]);
    if (!$allowEmpty && $v === '') admin_json_err(400, 'empty_field', "$key empty");
    if (strlen($v) > $maxLen) admin_json_err(400, 'too_long', "$key > $maxLen chars");
    return $v;
}

function admin_yt_id_valid(string $id): bool {
    return (bool)preg_match('/^[a-zA-Z0-9_-]{11}$/', $id);
}

/**
 * Extrae videoId de cualquier URL YouTube o de un id "11-char pelado".
 * Devuelve null si no lo encuentra.
 */
function admin_yt_id_from_url_or_id(string $input): ?string {
    $s = trim($input);
    if ($s === '') return null;
    if (admin_yt_id_valid($s)) return $s;
    // watch?v=, youtu.be/, /embed/, /shorts/
    if (preg_match('~(?:youtube\.com/(?:watch\?v=|embed/|shorts/|v/)|youtu\.be/|music\.youtube\.com/watch\?v=)([a-zA-Z0-9_-]{11})~', $s, $m)) {
        return $m[1];
    }
    return null;
}

function admin_fetch_track(int $id): ?array {
    $st = db()->prepare("SELECT * FROM tracks WHERE id=? LIMIT 1");
    $st->execute([$id]);
    $r = $st->fetch(PDO::FETCH_ASSOC);
    return $r ?: null;
}

function admin_fetch_artist(int $id): ?array {
    $st = db()->prepare("SELECT * FROM artists WHERE id=? LIMIT 1");
    $st->execute([$id]);
    $r = $st->fetch(PDO::FETCH_ASSOC);
    return $r ?: null;
}

function admin_fetch_album(int $id): ?array {
    $st = db()->prepare("SELECT * FROM albums WHERE id=? LIMIT 1");
    $st->execute([$id]);
    $r = $st->fetch(PDO::FETCH_ASSOC);
    return $r ?: null;
}

/**
 * Loguea una acción admin en admin_actions.
 * @param string $action      Slug corto: 'replace_youtube', 'edit_meta', 'hide', 'merge', ...
 * @param string $targetType  'track' | 'artist' | 'album' | 'playlist' | 'user' | 'report'
 * @param int|null $targetId
 * @param array|null $before  Estado previo (para rollback). Solo campos relevantes.
 * @param array|null $after   Estado nuevo.
 * @param string|null $note   Descripcion humana breve.
 * @return int  ID de la accion insertada (para permitir rollback puntual).
 */
function admin_log(string $action, string $targetType, ?int $targetId,
                   ?array $before = null, ?array $after = null, ?string $note = null): int {
    $u = auth_require_admin();
    $st = db()->prepare(
        "INSERT INTO admin_actions (admin_id, action, target_type, target_id, before_json, after_json, note)
         VALUES (?, ?, ?, ?, ?, ?, ?)"
    );
    $st->execute([
        (int)$u['id'], $action, $targetType, $targetId,
        $before !== null ? json_encode($before, JSON_UNESCAPED_UNICODE) : null,
        $after !== null ? json_encode($after, JSON_UNESCAPED_UNICODE) : null,
        $note,
    ]);
    return (int)db()->lastInsertId();
}
