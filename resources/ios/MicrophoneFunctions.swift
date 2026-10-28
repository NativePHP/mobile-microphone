import Foundation

// MARK: - Microphone Function Namespace

/// Functions related to microphone recording operations
/// Namespace: "Microphone.*"
enum MicrophoneFunctions {

    // MARK: - Microphone.Start

    /// Start microphone recording
    /// Parameters:
    ///   - id: (optional) string - Unique identifier for this recording
    ///   - event: (optional) string - Custom event class to dispatch when recording completes
    ///   - format: (optional) string - "m4a" (AAC, the default) or "wav" (mono 16-bit PCM)
    ///   - sampleRate: (optional) number - the WAV's sample rate in Hz, 16000 unless given
    ///   - maxDuration: (optional) number - seconds after which the recording stops by itself
    /// Returns:
    ///   - status: string - "success" or "error"
    /// Events:
    ///   - Fires "Native\Mobile\Events\Microphone\MicrophoneRecorded" when recording is stopped, or reaches maxDuration
    ///   - Fires "Native\Mobile\Events\Microphone\MicrophoneCancelled" when the microphone can't be used
    class Start: BridgeFunction {
        func execute(parameters: [String: Any]) throws -> [String: Any] {
            let id = parameters["id"] as? String
            let event = parameters["event"] as? String

            print("🎤 Starting microphone recording with id=\(id ?? "nil"), event=\(event ?? "nil")")

            // Store id and event for later use when stop is called
            if let id = id {
                UserDefaults.standard.set(id, forKey: "pending_microphone_id")
            }
            if let event = event {
                UserDefaults.standard.set(event, forKey: "pending_microphone_event")
            }

            _ = MicrophoneRecorder.shared.start(options: RecordingOptions(parameters: parameters))

            return [:]
        }
    }

    // MARK: - Microphone.Stop

    /// Stop microphone recording
    /// Events:
    ///   - Fires "Native\Mobile\Events\Microphone\MicrophoneRecorded" via Livewire dispatch when stopped
    class Stop: BridgeFunction {
        func execute(parameters: [String: Any]) throws -> [String: Any] {
            print("⏹️ Stopping microphone recording")

            if let path = MicrophoneRecorder.shared.stop() {
                MicrophoneFunctions.dispatchRecorded(path: path, mimeType: MicrophoneRecorder.shared.mimeType)
            }

            return [:]
        }
    }

    // MARK: - Microphone.Pause

    /// Pause microphone recording
    class Pause: BridgeFunction {
        func execute(parameters: [String: Any]) throws -> [String: Any] {
            print("⏸️ Pausing microphone recording")
            MicrophoneRecorder.shared.pause()
            return [:]
        }
    }

    // MARK: - Microphone.Resume

    /// Resume microphone recording
    class Resume: BridgeFunction {
        func execute(parameters: [String: Any]) throws -> [String: Any] {
            print("▶️ Resuming microphone recording")
            MicrophoneRecorder.shared.resume()
            return [:]
        }
    }

    // MARK: - Microphone.GetStatus

    /// Get current recording status
    class GetStatus: BridgeFunction {
        func execute(parameters: [String: Any]) throws -> [String: Any] {
            let status = MicrophoneRecorder.shared.getStatus()
            return ["status": status]
        }
    }

    // MARK: - Microphone.GetLevel

    /// How loud the microphone has been since this was last called, from 0 to 1
    class GetLevel: BridgeFunction {
        func execute(parameters: [String: Any]) throws -> [String: Any] {
            return ["level": MicrophoneRecorder.shared.level()]
        }
    }

    // MARK: - Microphone.GetRecording

    /// Get path to last recording
    class GetRecording: BridgeFunction {
        func execute(parameters: [String: Any]) throws -> [String: Any] {
            if let path = MicrophoneRecorder.shared.getLastRecording() {
                return ["path": path]
            } else {
                return ["path": ""]
            }
        }
    }

    // MARK: - Events

    /// Dispatches the recording's event (MicrophoneRecorded unless Start named another) with its path, and the id
    /// Start was given, which it then forgets.
    static func dispatchRecorded(path: String, mimeType: String) {
        let id = UserDefaults.standard.string(forKey: "pending_microphone_id")
        let eventClass = UserDefaults.standard.string(forKey: "pending_microphone_event")
            ?? "Native\\Mobile\\Events\\Microphone\\MicrophoneRecorded"

        print("📤 Dispatching \(eventClass) with path=\(path), id=\(id ?? "nil")")

        UserDefaults.standard.removeObject(forKey: "pending_microphone_id")
        UserDefaults.standard.removeObject(forKey: "pending_microphone_event")

        var payload: [String: Any] = [
            "path": path,
            "mimeType": mimeType
        ]
        if let id = id {
            payload["id"] = id
        }

        // Dispatch event directly to Livewire via JavaScript (same as photo/video)
        LaravelBridge.shared.send?(eventClass, payload)
    }

    /// Dispatches MicrophoneCancelled when a recording couldn't start or broke off, with why: "permission_denied",
    /// "start_failed" or "recording_failed".
    static func dispatchCancelled(reason: String) {
        let id = UserDefaults.standard.string(forKey: "pending_microphone_id")

        print("📤 Dispatching MicrophoneCancelled (\(reason)), id=\(id ?? "nil")")

        UserDefaults.standard.removeObject(forKey: "pending_microphone_id")
        UserDefaults.standard.removeObject(forKey: "pending_microphone_event")

        var payload: [String: Any] = [
            "cancelled": true,
            "reason": reason
        ]
        if let id = id {
            payload["id"] = id
        }

        LaravelBridge.shared.send?("Native\\Mobile\\Events\\Microphone\\MicrophoneCancelled", payload)
    }
}