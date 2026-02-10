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

## Notes

- **Microphone Permission:** The first time your app requests microphone access, users will be prompted for permission. If denied, recording functions will fail silently.

- **Background Recording:** You can allow your app to record audio while the device is locked by toggling `microphone_background` to true in the config.

- **File Format:** Recordings are stored as M4A/AAC audio files (`.m4a`). This format is optimized for small file sizes while maintaining quality.

- **Recording State:** Only one recording can be active at a time. Calling `start()` while a recording is in progress will return `false`.

- **Auto-Start Behavior:** If you don't explicitly call `start()`, the recording will automatically start when the `PendingMicrophone` is destroyed.
