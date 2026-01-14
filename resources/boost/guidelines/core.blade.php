## nativephp/microphone

Audio recording plugin for NativePHP Mobile with pause/resume support and background recording.

### PHP Usage (Livewire/Blade)

@verbatim
<code-snippet name="Recording Audio" lang="php">
use Native\Mobile\Facades\Microphone;

// Start recording
Microphone::record()->start();

// Stop recording
Microphone::stop();

// Pause/resume
Microphone::pause();
Microphone::resume();

// Get status: "idle", "recording", or "paused"
$status = Microphone::getStatus();

// Get last recording path
$path = Microphone::getRecording();
</code-snippet>
@endverbatim

### JavaScript Usage (Vue/React/Inertia)

@verbatim
<code-snippet name="Recording in JavaScript" lang="javascript">
import { microphone, on, Events } from '#nativephp';

// Start recording with identifier
await microphone.record().id('voice-memo');

// Stop recording
await microphone.stop();

// Pause/resume
await microphone.pause();
await microphone.resume();

// Get status
const result = await microphone.getStatus();
// result.status: "idle", "recording", or "paused"
</code-snippet>
@endverbatim

### Handling Recording Events

@verbatim
<code-snippet name="Recording Events" lang="php">
use Native\Mobile\Attributes\OnNative;
use Native\Mobile\Events\Microphone\MicrophoneRecorded;

#[OnNative(MicrophoneRecorded::class)]
public function handleAudioRecorded(string $path, string $mimeType, ?string $id)
{
    // Process the recording
    // $path - File path to recorded audio
    // $mimeType - 'audio/m4a'
    // $id - Recorder ID if set
}
</code-snippet>
@endverbatim

### Methods

- `Microphone::record()` - Returns PendingMicrophone for fluent configuration
- `Microphone::stop()` - Stop current recording
- `Microphone::pause()` - Pause current recording
- `Microphone::resume()` - Resume paused recording
- `Microphone::getStatus()` - Get current status
- `Microphone::getRecording()` - Get path to last recording

### PendingMicrophone Methods

- `->id(string $id)` - Set unique identifier for tracking
- `->event(string $class)` - Set custom event class
- `->remember()` - Store ID in session
- `->start()` - Explicitly start recording

### Notes

- Only one recording can be active at a time
- Audio stored as M4A/AAC files
- Enable `microphone_background` in config for background recording