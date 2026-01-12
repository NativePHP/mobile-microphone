## nativephp/microphone

Audio recording plugin for NativePHP Mobile with pause/resume support, background recording, and native permission handling.

### Installation

```bash
composer require nativephp/microphone
php artisan native:plugin:register nativephp/microphone
```

### PHP Usage (Livewire/Blade)

Use the `Microphone` facade:

@verbatim
<code-snippet name="Recording Audio" lang="php">
use Native\Mobile\Facades\Microphone;

// Start recording
Microphone::record()->start();

// Stop recording
Microphone::stop();

// Pause recording
Microphone::pause();

// Resume recording
Microphone::resume();

// Get status: "idle", "recording", or "paused"
$status = Microphone::getStatus();

// Get last recording path
$path = Microphone::getRecording();
</code-snippet>
@endverbatim

@verbatim
<code-snippet name="Recording with Options" lang="php">
use Native\Mobile\Facades\Microphone;

// With custom ID for tracking
Microphone::record()
    ->id('voice-note-123')
    ->remember()
    ->start();

// With custom event class
Microphone::record()
    ->event(MyRecordingEvent::class)
    ->start();
</code-snippet>
@endverbatim

### Handling Recording Events

@verbatim
<code-snippet name="Listening for Recording Events" lang="php">
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
</code-snippet>
@endverbatim

### JavaScript Usage

@verbatim
<code-snippet name="Recording in JavaScript" lang="js">
import { microphone, on, off, Events } from '#nativephp';

// Basic recording
await microphone.record();

// With identifier for tracking
await microphone.record()
    .id('voice-memo');

// Stop recording
await microphone.stop();

// Pause/resume
await microphone.pause();
await microphone.resume();

// Get status
const result = await microphone.getStatus();
if (result.status === 'recording') {
    // Recording in progress
}

// Listen for recording complete
on(Events.Microphone.MicrophoneRecorded, (payload) => {
    const { path, mimeType, id } = payload;
    // Process the recording
});
</code-snippet>
@endverbatim

### Available Methods

#### Microphone Facade

- `Microphone::record()` - Returns PendingMicrophone for fluent configuration
- `Microphone::stop()` - Stop current recording
- `Microphone::pause()` - Pause current recording
- `Microphone::resume()` - Resume paused recording
- `Microphone::getStatus()` - Get current status: "idle", "recording", "paused"
- `Microphone::getRecording()` - Get path to last recording

#### PendingMicrophone Methods

- `->id(string $id)` - Set unique identifier
- `->event(string $class)` - Set custom event class
- `->remember()` - Flash ID to session
- `->start()` - Explicitly start recording

### Events

- `Native\Mobile\Events\Microphone\MicrophoneRecorded` - Recording completed
  - `string $path` - File path to the recorded audio
  - `string $mimeType` - MIME type (default: `'audio/m4a'`)
  - `?string $id` - The recorder's ID if set

### Notes

- **File Format:** Recordings are stored as M4A/AAC audio files (`.m4a`)
- **Recording State:** Only one recording can be active at a time
- **Background Recording:** Enable `microphone_background` in config for background recording
- **Auto-Start:** Recording starts automatically when PendingMicrophone is destroyed if not explicitly started

### Platform Details

- **iOS**: Uses AVAudioRecorder with AAC encoding
- **Android**: Uses MediaRecorder with AAC encoding
- Requires microphone permission in `config/nativephp.php`
