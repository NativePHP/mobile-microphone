<?php

namespace NativePHP\Microphone\Events;

use Illuminate\Foundation\Events\Dispatchable;
use Illuminate\Queue\SerializesModels;

/**
 * Microphone recording completed event
 *
 * This event is dispatched from native code (Kotlin/Swift) via JavaScript injection,
 * directly triggering Livewire listeners with #[On('native:NativePHP\Microphone\Events\MicrophoneRecorded')]
 */
class MicrophoneRecorded
{
    use Dispatchable, SerializesModels;

    /**
     * Create a new event instance.
     */
    public function __construct(
        public string $path,
        public string $mimeType = 'audio/m4a',
        public ?string $id = null
    ) {}
}