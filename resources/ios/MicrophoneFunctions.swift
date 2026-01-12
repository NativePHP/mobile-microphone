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
    /// Returns:
    ///   - status: string - "success" or "error"
    /// Events:
    ///   - Fires "Native\Mobile\Events\Microphone\MicrophoneRecorded" when recording is stopped
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

            MicrophoneRecorder.shared.start()

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

            guard let path = MicrophoneRecorder.shared.stop() else {
                return [:]
            }

            // Retrieve stored id and event class from UserDefaults
            let id = UserDefaults.standard.string(forKey: "pending_microphone_id")
            let eventClass = UserDefaults.standard.string(forKey: "pending_microphone_event")
                ?? "Native\\Mobile\\Events\\Microphone\\MicrophoneRecorded"

            print("📤 Dispatching \(eventClass) with path=\(path), id=\(id ?? "nil")")

            // Clean up stored values
            UserDefaults.standard.removeObject(forKey: "pending_microphone_id")
            UserDefaults.standard.removeObject(forKey: "pending_microphone_event")

            // Build payload
            var payload: [String: Any] = [
                "path": path,
                "mimeType": "audio/m4a"
            ]
            if let id = id {
                payload["id"] = id
            }

            // Dispatch event directly to Livewire via JavaScript (same as photo/video)
            LaravelBridge.shared.send?(eventClass, payload)

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
}