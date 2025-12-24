<?php

namespace NativePHP\Microphone;

use Illuminate\Support\ServiceProvider;

class MicrophoneServiceProvider extends ServiceProvider
{
    public function register(): void
    {
        $this->app->singleton(Microphone::class, function () {
            return new Microphone;
        });
    }

    public function boot(): void
    {
        //
    }
}