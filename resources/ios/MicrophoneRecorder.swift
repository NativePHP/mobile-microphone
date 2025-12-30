import Foundation
import AVFoundation
import UIKit

/// MicrophoneRecorder manages audio recording functionality for NativePHP iOS
/// Handles recording state, file management, and AVAudioRecorder lifecycle
/// Supports background recording when the device screen is locked
class MicrophoneRecorder: NSObject, AVAudioRecorderDelegate {

    static let shared = MicrophoneRecorder()

    private var audioRecorder: AVAudioRecorder?
    private var recordingState: RecordingState = .idle
    private var lastRecordingPath: String?
    private var currentRecordingFilename: String?
    private var wasRecordingBeforeInterruption = false

    enum RecordingState {
        case idle
        case recording
        case paused
    }

    private override init() {
        super.init()
        setupInterruptionHandling()
    }

    /// Set up notification observers for audio session interruptions and app lifecycle
    /// This handles cases where iOS temporarily interrupts audio (phone calls, Siri, etc.)
    private func setupInterruptionHandling() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )

        // Handle route changes (headphones plugged/unplugged, etc.)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange),
            name: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance()
        )

        // Handle app going to background - ensure audio session stays active
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )

        // Handle app coming back to foreground
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )

        print("🎧 Audio session interruption and lifecycle handling configured")
    }

    @objc private func handleAppDidEnterBackground() {
        print("📱 App entered background")
        if recordingState == .recording {
            print("🎤 Recording continues in background...")
            // Ensure audio session is still active
            do {
                try AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
                print("✅ Audio session reconfirmed active for background")
            } catch {
                print("⚠️ Failed to reconfirm audio session: \(error.localizedDescription)")
            }
        }
    }

    @objc private func handleAppWillEnterForeground() {
        print("📱 App will enter foreground")
        if recordingState == .recording || recordingState == .paused {
            print("🎤 Recording state: \(recordingState)")
        }
    }

    @objc private func handleInterruption(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }

        switch type {
        case .began:
            // Audio session was interrupted (e.g., incoming call, Siri)
            print("⚠️ Audio session interrupted")
            if recordingState == .recording {
                wasRecordingBeforeInterruption = true
                audioRecorder?.pause()
                recordingState = .paused
                print("⏸️ Recording paused due to interruption")
            }

        case .ended:
            // Interruption ended, check if we should resume
            print("✅ Audio session interruption ended")
            guard let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt else {
                return
            }
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            if options.contains(.shouldResume) && wasRecordingBeforeInterruption {
                // Re-activate audio session and resume recording
                do {
                    try AVAudioSession.sharedInstance().setActive(true)
                    if audioRecorder?.record() == true {
                        recordingState = .recording
                        print("▶️ Recording resumed after interruption")
                    }
                } catch {
                    print("❌ Failed to resume after interruption: \(error.localizedDescription)")
                }
            }
            wasRecordingBeforeInterruption = false

        @unknown default:
            break
        }
    }

    @objc private func handleRouteChange(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }

        switch reason {
        case .oldDeviceUnavailable:
            // Headphones were unplugged - recording continues via speaker
            print("🎧 Audio route changed: device unavailable, continuing recording")
        case .newDeviceAvailable:
            print("🎧 Audio route changed: new device available")
        default:
            break
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
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
            // Using .allowBluetooth enables Bluetooth audio devices
            // NOT using .defaultToSpeaker - it can interfere with background recording
            // The audio background mode in Info.plist allows recording while device is locked
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(
                .playAndRecord,
                mode: .default,
                options: [.allowBluetooth, .allowBluetoothA2DP]
            )
            // Use notifyOthersOnDeactivation to be a good citizen
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

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