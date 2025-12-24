<?php

namespace NativePHP\Microphone\Facades;

use Illuminate\Support\Facades\Facade;

/**
 * @method static \NativePHP\Microphone\PendingMicrophone record()
 * @method static void stop()
 * @method static void pause()
 * @method static void resume()
 * @method static string getStatus()
 * @method static string|null getRecording()
 */
class Microphone extends Facade
{
    protected static function getFacadeAccessor()
    {
        return \NativePHP\Microphone\Microphone::class;
    }
}