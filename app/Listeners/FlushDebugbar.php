<?php

declare(strict_types=1);

namespace App\Listeners;

use Fruitcake\LaravelDebugbar\LaravelDebugbar;
use Laravel\Octane\Events\RequestTerminated;

final class FlushDebugbar
{
    /**
     * Handle the event.
     */
    public function handle(RequestTerminated $event): void
    {
        try {
            // Tentar resetar antes de remover do container (se o método existir)
            if (app()->bound('debugbar')) {
                $debugbar = app('debugbar');
                if ($debugbar instanceof LaravelDebugbar && method_exists($debugbar, 'reset')) {
                    $debugbar->reset();
                }
            }
            
            // Remover o Debugbar do container para forçar recriação na próxima requisição
            // Isso garante que o estado seja limpo entre requisições no Octane
            app()->forgetInstance('debugbar');
            app()->forgetInstance(LaravelDebugbar::class);
        } catch (\Throwable $e) {
            // Silenciosamente falhar se o Debugbar não estiver disponível
        }
    }
}
