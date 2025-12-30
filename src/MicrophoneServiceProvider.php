<?php

namespace Native\Mobile\Providers;

use Illuminate\Support\ServiceProvider;
use Native\Mobile\Microphone;

class MicrophoneServiceProvider extends ServiceProvider
{
    public function register(): void
    {
        $this->app->singleton(Microphone::class, function () {
            return new Microphone;
        });
    }
}