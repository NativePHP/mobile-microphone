# Microphone Plugin for NativePHP Mobile

Audio recording plugin for NativePHP Mobile with pause/resume support, background recording, and native permission handling.

## Overview

The Microphone API provides access to the device's microphone for recording audio. It offers a fluent interface for starting and managing recordings, tracking them with unique identifiers, and responding to completion events.

## Installation

```bash
composer require nativephp/mobile-microphone
```

## Usage

### PHP (Livewire/Blade)

```php
use Native\Mobile\Facades\Microphone;

// Start recording
Microphone::record()->start();

// Stop recording
Microphone::stop();

// Pause recording
Microphone::pause();

// Resume recording
Microphone::resume();

// Get status
$status = Microphone::getStatus();
// Returns: "idle", "recording", or "paused"

// Get last recording path
$path = Microphone::getRecording();

// How loud the microphone has been since the last call, 0 to 1, for a level meter
$level = Microphone::level();
```

### JavaScript (Vue/React/Inertia)

```js
import { Microphone, On, Off, Events } from '#nativephp';

// Basic recording
await Microphone.record();

// With identifier for tracking
await Microphone.record()
    .id('voice-memo');

// Stop recording
await Microphone.stop();

// Pause/resume
await Microphone.pause();
await Microphone.resume();

// Get status
const result = await Microphone.getStatus();
if (result.status === 'recording') {
    // Recording in progress
}

// Get last recording
const result = await Microphone.getRecording();
if (result.path) {
    // Process the recording
}
```

## PendingMicrophone API

### `id(string $id)`

Set a unique identifier for this recording.

```php
Microphone::record()
    ->id('voice-note-123')
    ->start();
```

### `event(string $eventClass)`

Set a custom event class to dispatch when recording completes.

```php
use App\Events\VoiceMessageRecorded;

Microphone::record()
    ->event(VoiceMessageRecorded::class)
    ->start();
```

### `wav(int $sampleRate = 16000)`

Record mono 16-bit PCM WAV at the given sample rate instead of AAC. Use it when the recording goes to a server that
takes uncompressed audio, or one that only takes a few formats. `MicrophoneRecorded` then reports `audio/wav`. A
minute at 16 kHz is about 1.9 MB.

```php
Microphone::record()
    ->wav()
    ->start();
```

### `maxDuration(float $seconds)`

Stop recording by itself after this many seconds. `MicrophoneRecorded` is dispatched with what was recorded, as if
`Microphone::stop()` had been called.

```php
Microphone::record()
    ->wav()
    ->maxDuration(60)
    ->start();
```

### `remember()`

Store the recorder's ID in the session for later retrieval.

```php
Microphone::record()
    ->id('voice-note')
    ->remember()
    ->start();
```

### `start()`

Explicitly start the audio recording. Returns `true` if recording started successfully.

## Events

### `MicrophoneRecorded`

Dispatched when an audio recording completes.

**Payload:**
- `string $path` - File path to the recorded audio
- `string $mimeType` - MIME type of the audio (default: `'audio/m4a'`)
- `?string $id` - The recorder's ID, if one was set

#### PHP

```php
use Native\Mobile\Attributes\OnNative;
use Native\Mobile\Events\Microphone\MicrophoneRecorded;

#[OnNative(MicrophoneRecorded::class)]
public function handleAudioRecorded(string $path, string $mimeType, ?string $id)
{
    $this->recordings[] = [
        'path' => $path,
        'mimeType' => $mimeType,
        'id' => $id,
    ];
}
```

#### Vue

```js
import { On, Off, Events } from '#nativephp';
import { ref, onMounted, onUnmounted } from 'vue';

const recordings = ref([]);

const handleAudioRecorded = (payload) => {
    const { path, mimeType, id } = payload;
    recordings.value.push({ path, mimeType, id });
};

onMounted(() => {
    On(Events.Microphone.MicrophoneRecorded, handleAudioRecorded);
});

onUnmounted(() => {
    Off(Events.Microphone.MicrophoneRecorded, handleAudioRecorded);
});
```

#### React

```jsx
import { On, Off, Events } from '#nativephp';
import { useState, useEffect } from 'react';

const [recordings, setRecordings] = useState([]);

const handleAudioRecorded = (payload) => {
    const { path, mimeType, id } = payload;
    setRecordings(prev => [...prev, { path, mimeType, id }]);
};

useEffect(() => {
    On(Events.Microphone.MicrophoneRecorded, handleAudioRecorded);

    return () => {
        Off(Events.Microphone.MicrophoneRecorded, handleAudioRecorded);
    };
}, []);
```

### `MicrophoneCancelled`

Dispatched when a recording can't start or breaks off.

**Payload:**
- `bool $cancelled` - Always `true`
- `?string $id` - The recorder's ID, if one was set
- `string $reason` - `permission_denied`, `start_failed` or `recording_failed`

```php
use Native\Mobile\Attributes\On;
use Native\Mobile\Events\Microphone\MicrophoneCancelled;

#[On(MicrophoneCancelled::class)]
public function recordingCancelled(?string $id = null, string $reason = '')
{
    $this->error = $reason === 'permission_denied' ? 'Allow the microphone in Settings.' : 'Could not record.';
}
```

## Testing

The plugin extends the NativePHP testing suite with microphone-specific helpers, so your app tests can fake recordings and assert recording activity without knowing any bridge internals:

```php
use Native\Mobile\Testing\Native;

it('saves a voice memo', function () {
    Native::fakeBridge()->withRecording('/storage/emulated/0/audio/note.m4a');

    Native::test(VoiceMemo::class)
        ->tap('Record')
        ->assertRecordingStarted();
});

it('shows the paused state in the UI', function () {
    Native::fakeBridge()->withMicrophoneStatus('paused');

    Native::test(VoiceMemo::class)
        ->assertSet('status', 'paused');
});
```

### Helpers

- `withRecording(?string $path = null)` — fake a completed recording. `getStatus()` reports `"idle"` and `getRecording()` reports `$path` (a generic `.m4a` path when omitted) — the state right after a real recording session ends.
- `withMicrophoneStatus(string $status)` — script `getStatus()` directly (e.g. `"recording"` or `"paused"`), without a completed recording on disk.
- `assertRecordingStarted()` — assert a recording was started.
- `assertRecordingStopped()` — assert the recording was stopped.
- `assertNothingRecorded()` — assert no recording was ever started.

The helpers are available on `Native::fakeBridge()` and chain directly off `Native::test(...)`. They register automatically while running tests (requires a core with a macroable FakeBridge; on older cores they simply don't register).

## Notes

- **Microphone Permission:** The first time your app requests microphone access, users will be prompted for permission. If it's denied, `MicrophoneCancelled` is dispatched with the reason `permission_denied`.

- **Background Recording:** You can allow your app to record audio while the device is locked by toggling `microphone_background` to true in the config.

- **File Format:** Recordings are stored as M4A/AAC audio files (`.m4a`) unless you ask for `wav()`, which writes mono 16-bit PCM (`.wav`).

- **Audio Session (iOS):** Recording switches the shared audio session to play-and-record, and puts back the category it had once the recording ends, so audio played afterwards doesn't come out of the earpiece.

- **Recording State:** Only one recording can be active at a time. Calling `start()` while a recording is in progress will return `false`.

- **Auto-Start Behavior:** If you don't explicitly call `start()`, the recording will automatically start when the `PendingMicrophone` is destroyed.
