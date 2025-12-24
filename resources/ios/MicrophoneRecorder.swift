import Foundation
import AVFoundation

/// MicrophoneRecorder manages audio recording functionality for NativePHP iOS
/// Handles recording state, file management, and AVAudioRecorder lifecycle
class MicrophoneRecorder: NSObject, AVAudioRecorderDelegate {

    static let shared = MicrophoneRecorder()

    private var audioRecorder: AVAudioRecorder?
    private var recordingState: RecordingState = .idle
    private var lastRecordingPath: String?
    private var currentRecordingFilename: String?

    enum RecordingState {
        case idle
        case recording
        case paused
    }

    private override init() {
        super.init()
    }

    /// Start a new audio recording
    /// - Returns: true if recording started successfully, false otherwise
    func start() -> Bool {
        if recordingState != .idle {
            print("⚠️ Cannot start recording - current state: \(recordingState)")
            return false
        }

        // Request microphone permission if needed
        if #available(iOS 17.0, *) {
            let permission = AVAudioApplication.shared.recordPermission

            switch permission {
            case .granted:
                return startRecording()
            case .denied:
                print("❌ Microphone permission denied")
                return false
            case .undetermined:
                // Request permission
                AVAudioApplication.requestRecordPermission { [weak self] granted in
                    if granted {
                        DispatchQueue.main.async {
                            _ = self?.startRecording()
                        }
                    } else {
                        print("❌ User denied microphone permission")
                    }
                }
                return false
            @unknown default:
                print("❌ Unknown microphone permission state")
                return false
            }
        } else {
            let permission = AVAudioSession.sharedInstance().recordPermission

            switch permission {
            case .granted:
                return startRecording()
            case .denied:
                print("❌ Microphone permission denied")
                return false
            case .undetermined:
                // Request permission
                AVAudioSession.sharedInstance().requestRecordPermission { [weak self] allowed in
                    if allowed {
                        DispatchQueue.main.async {
                            _ = self?.startRecording()
                        }
                    } else {
                        print("❌ User denied microphone permission")
                    }
                }
                return false
            @unknown default:
                print("❌ Unknown microphone permission state")
                return false
            }
        }
    }

    private func startRecording() -> Bool {
        do {
            // Configure audio session for background recording support
            // Using .mixWithOthers allows recording alongside other audio
            // Using .allowBluetooth enables Bluetooth audio devices
            // The audio background mode in Info.plist allows recording while device is locked
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try audioSession.setActive(true)

            // Generate unique timestamped filename
            let timestamp = Int(Date().timeIntervalSince1970)
            let filename = "NativePHP_\(timestamp).m4a"
            currentRecordingFilename = filename

            // Save to temporary directory
            let fm = FileManager.default
            let tempDir = fm.temporaryDirectory

            let audioFilename = tempDir.appendingPathComponent(filename)

            print("📝 Creating recording file: \(audioFilename.path)")

            // Configure recording settings
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44100.0,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
                AVEncoderBitRateKey: 128000
            ]

            // Create and start recorder
            audioRecorder = try AVAudioRecorder(url: audioFilename, settings: settings)
            audioRecorder?.delegate = self
            audioRecorder?.prepareToRecord()

            if audioRecorder?.record() == true {
                recordingState = .recording
                print("🎤 Recording started successfully")
                return true
            } else {
                print("❌ Failed to start recording")
                cleanup()
                return false
            }

        } catch {
            print("❌ Error starting recording: \(error.localizedDescription)")
            cleanup()
            return false
        }
    }

    /// Stop the current recording
    /// - Returns: absolute path to the recorded file, or nil if no recording or error
    func stop() -> String? {
        if recordingState == .idle {
            print("⚠️ Cannot stop recording - no active recording")
            return nil
        }

        audioRecorder?.stop()

        let filePath = audioRecorder?.url.path
        lastRecordingPath = filePath
        recordingState = .idle

        // Deactivate audio session
        do {
            try AVAudioSession.sharedInstance().setActive(false)
        } catch {
            print("⚠️ Error deactivating audio session: \(error.localizedDescription)")
        }

        audioRecorder = nil

        print("⏹️ Recording stopped: \(filePath ?? "nil")")
        return filePath
    }

    /// Pause the current recording
    func pause() {
        if recordingState != .recording {
            print("⚠️ Cannot pause - not currently recording")
            return
        }

        audioRecorder?.pause()
        recordingState = .paused
        print("⏸️ Recording paused")
    }

    /// Resume a paused recording
    func resume() {
        if recordingState != .paused {
            print("⚠️ Cannot resume - not currently paused")
            return
        }

        if audioRecorder?.record() == true {
            recordingState = .recording
            print("▶️ Recording resumed")
        } else {
            print("❌ Failed to resume recording")
        }
    }

    /// Get the current recording status
    /// - Returns: "idle", "recording", or "paused"
    func getStatus() -> String {
        switch recordingState {
        case .idle:
            return "idle"
        case .recording:
            return "recording"
        case .paused:
            return "paused"
        }
    }

    /// Get the path to the last recorded audio file
    /// - Returns: absolute path to the last recording, or nil if none exists
    func getLastRecording() -> String? {
        return lastRecordingPath
    }

    /// Clean up resources in case of error
    private func cleanup() {
        audioRecorder?.stop()
        audioRecorder = nil
        recordingState = .idle

        do {
            try AVAudioSession.sharedInstance().setActive(false)
        } catch {
            print("⚠️ Error deactivating audio session: \(error.localizedDescription)")
        }
    }

    // MARK: - AVAudioRecorderDelegate

    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if !flag {
            print("❌ Recording finished unsuccessfully")
            cleanup()
        }
    }

    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        print("❌ Audio recorder encode error: \(error?.localizedDescription ?? "unknown")")
        cleanup()
    }
}