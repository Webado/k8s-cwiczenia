<?php

// Symulacja konsumenta kolejki (jak messenger:consume) z poprawną obsługą SIGTERM.
// UWAGA: handler zadziała tylko wtedy, gdy SIGTERM faktycznie DOTRZE do tego procesu (patrz README, krok 7).

require __DIR__ . '/../vendor/autoload.php';

use Monolog\Handler\StreamHandler;
use Monolog\Logger;

$log = new Logger('worker');
$log->pushHandler(new StreamHandler('php://stdout'));

$running = true;
pcntl_async_signals(true);
pcntl_signal(SIGTERM, function () use (&$running, $log) {
    $log->info('SIGTERM: kończę bieżącą wiadomość i wychodzę');
    $running = false;
});

$log->info('Worker wystartował, PID ' . getmypid());

$i = 0;
while ($running) {
    $i++;
    $log->info("Przetwarzam wiadomość #$i");
    sleep(1);
}

$log->info('Worker zakończony czysto');
