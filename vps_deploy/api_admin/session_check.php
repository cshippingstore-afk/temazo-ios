<?php
/**
 * /api/admin/session_check.php
 * GET → devuelve si el user actual es admin (para que la app iOS decida si
 * pinta o no la UI de admin).
 *
 *   { ok: true, is_admin: bool, user: {id, email, username} }
 */
declare(strict_types=1);
require_once __DIR__ . '/../auth_lib.php';
require_once __DIR__ . '/admin_lib.php';

header('Content-Type: application/json');

$u = auth_current_user();
if (!$u) {
    echo json_encode(['ok' => true, 'is_admin' => false, 'user' => null]);
    exit;
}
echo json_encode([
    'ok' => true,
    'is_admin' => (int)($u['is_admin'] ?? 0) === 1,
    'user' => [
        'id' => (int)$u['id'],
        'email' => $u['email'] ?? '',
        'username' => $u['username'] ?? null,
    ],
]);
