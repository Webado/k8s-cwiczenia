<?php

require __DIR__ . '/../vendor/autoload.php';

use Symfony\Component\HttpFoundation\Response;

$yesNo = fn (bool $v) => $v ? 'TAK' : 'nie';

$devPackages = is_dir(__DIR__ . '/../vendor/phpunit') ? 'TAK (phpunit w vendor/)' : 'nie';

$body = implode("\n", [
    'Sklep działa!',
    '',
    'PHP:             ' . PHP_VERSION,
    'xdebug:          ' . $yesNo(extension_loaded('xdebug')),
    'opcache:         ' . $yesNo(function_exists('opcache_get_status') && (opcache_get_status(false)['opcache_enabled'] ?? false)),
    'paczki dev:      ' . $devPackages,
    'display_errors:  ' . (ini_get('display_errors') ?: 'off'),
    'użytkownik:      ' . (function_exists('posix_geteuid') ? posix_getpwuid(posix_geteuid())['name'] : get_current_user()),
    '',
]);

(new Response($body, 200, ['Content-Type' => 'text/plain; charset=utf-8']))->send();
