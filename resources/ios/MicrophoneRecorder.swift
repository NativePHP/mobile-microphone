import Foundation
import AVFoundation
import UIKit

/// How a recording is made, from the parameters `Microphone.Start` was called with.
///
/// - `format`: "m4a" (AAC, the default) or "wav" (mono 16-bit PCM)
/// - `sampleRate`: the WAV's sample rate in Hz, 16000 unless given
/// - `maxDuration`: seconds after which the recording stops by itself, as if `Microphone.Stop` was called; 0 for no limit
struct RecordingOptions {
    let format: String
    let sampleRate: Double
    let maxDuration: TimeInterval

    static let standard = RecordingOptions(parameters: [:])

    init(parameters: [String: Any]) {
        format = (parameters["format"] as? String)?.lowercased() == "wav" ? "wav" : "m4a"
        sampleRate = (parameters["sampleRate"] as? NSNumber)?.doubleValue ?? 16000
        maxDuration = max(0, (parameters["maxDuration"] as? NSNumber)?.doubleValue ?? 0)
    }

    var isWav: Bool { format == "wav" }

    var mimeType: String { isWav ? "audio/wav" : "audio/m4a" }

    var settings: [String: Any] {
        if isWav {
            return [
                AVFormatIDKey: Int(kAudioFormatLinearPCM),
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false,
            ]
        }

        return [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            AVEncoderBitRateKey: 128000
        ]
    }
}

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
    private var options = RecordingOptions.standard

    /// Start is waiting on the permission prompt. Stop meanwhile cancels it, so granting
    /// afterwards doesn't start a recording nobody is waiting for.
    private var startsOnPermission = false

    /// The audio session as it was before recording, put back when the recording ends, so audio
    /// played afterwards doesn't come out of the earpiece.
    private var previousSession: (category: AVAudioSession.Category, mode: AVAudioSession.Mode, options: AVAudioSession.CategoryOptions)?

    /// The loudest the microphone has been since `level()` was last asked, from 0 to 1, sampled
    /// from the recorder's meter twenty times a second.
    private var loudest: Float = 0
    private let loudestLock = NSLock()
    private var meterTimer: Timer?

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
                    if record() {
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

    /// Start a new audio recording. When the microphone can't be used (permission denied, or the
    /// recorder failed to start), MicrophoneCancelled is dispatched with the reason.
    /// - Returns: true if recording started successfully, false otherwise
    func start(options: RecordingOptions = .standard) -> Bool {
        if recordingState != .idle {
            print("⚠️ Cannot start recording - current state: \(recordingState)")
            return false
        }

        self.options = options

        // Request microphone permission if needed
        if #available(iOS 17.0, *) {
            let permission = AVAudioApplication.shared.recordPermission

            switch permission {
            case .granted:
                return startRecording()
            case .denied:
                print("❌ Microphone permission denied")
                MicrophoneFunctions.dispatchCancelled(reason: "permission_denied")
                return false
            case .undetermined:
                // Request permission
                startsOnPermission = true
                AVAudioApplication.requestRecordPermission { [weak self] granted in
                    DispatchQueue.main.async {
                        guard let self = self, self.startsOnPermission else { return }
                        self.startsOnPermission = false

                        if granted {
                            _ = self.startRecording()
                        } else {
                            print("❌ User denied microphone permission")
                            MicrophoneFunctions.dispatchCancelled(reason: "permission_denied")
                        }
                    }
                }
                return false
            @unknown default:
                print("❌ Unknown microphone permission state")
                MicrophoneFunctions.dispatchCancelled(reason: "permission_denied")
                return false
            }
        } else {
            let permission = AVAudioSession.sharedInstance().recordPermission

            switch permission {
            case .granted:
                return startRecording()
            case .denied:
                print("❌ Microphone permission denied")
                MicrophoneFunctions.dispatchCancelled(reason: "permission_denied")
                return false
            case .undetermined:
                // Request permission
                startsOnPermission = true
                AVAudioSession.sharedInstance().requestRecordPermission { [weak self] allowed in
                    DispatchQueue.main.async {
                        guard let self = self, self.startsOnPermission else { return }
                        self.startsOnPermission = false

                        if allowed {
                            _ = self.startRecording()
                        } else {
                            print("❌ User denied microphone permission")
                            MicrophoneFunctions.dispatchCancelled(reason: "permission_denied")
                        }
                    }
                }
                return false
            @unknown default:
                print("❌ Unknown microphone permission state")
                MicrophoneFunctions.dispatchCancelled(reason: "permission_denied")
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
            previousSession = (audioSession.category, audioSession.mode, audioSession.categoryOptions)
            try audioSession.setCategory(
                .playAndRecord,
                mode: .default,
                options: [.allowBluetooth, .allowBluetoothA2DP]
            )
            // Use notifyOthersOnDeactivation to be a good citizen
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

            // A unique timestamped filename, to the millisecond so two recordings in the same second don't collide
            let timestamp = Int(Date().timeIntervalSince1970 * 1000)
            let filename = "NativePHP_\(timestamp).\(options.format)"
            currentRecordingFilename = filename

            // Save to temporary directory
            let fm = FileManager.default
            let tempDir = fm.temporaryDirectory

            let audioFilename = tempDir.appendingPathComponent(filename)

            print("📝 Creating recording file: \(audioFilename.path)")

            // Create and start recorder
            audioRecorder = try AVAudioRecorder(url: audioFilename, settings: options.settings)
            audioRecorder?.delegate = self
            audioRecorder?.isMeteringEnabled = true
            audioRecorder?.prepareToRecord()

            if record() {
                recordingState = .recording
                startMetering()
                print("🎤 Recording started successfully")
                return true
            } else {
                print("❌ Failed to start recording")
                cleanup()
                MicrophoneFunctions.dispatchCancelled(reason: "start_failed")
                return false
            }

        } catch {
            print("❌ Error starting recording: \(error.localizedDescription)")
            cleanup()
            MicrophoneFunctions.dispatchCancelled(reason: "start_failed")
            return false
        }
    }

    /// Records, or carries on after a pause, for whatever is left of the limit.
    private func record() -> Bool {
        guard let recorder = audioRecorder else { return false }

        if options.maxDuration > 0 {
            let remaining = options.maxDuration - recorder.currentTime
            return remaining > 0 && recorder.record(forDuration: remaining)
        }

        return recorder.record()
    }

    /// Stop the current recording
    /// - Returns: absolute path to the recorded file, or nil if no recording or error
    func stop() -> String? {
        if recordingState == .idle {
            if startsOnPermission {
                print("⏹️ Recording cancelled before the permission prompt was answered")
                startsOnPermission = false
            } else {
                print("⚠️ Cannot stop recording - no active recording")
            }
            return nil
        }

        // Idle first: stopping makes the recorder call its delegate, which must not take this for the limit.
        recordingState = .idle
        audioRecorder?.stop()

        let filePath = audioRecorder?.url.path
        lastRecordingPath = filePath

        stopMetering()
        releaseSession()

        audioRecorder = nil

        print("⏹️ Recording stopped: \(filePath ?? "nil")")
        return filePath
    }

    /// The MIME type of the recording made last, or under way.
    var mimeType: String {
        options.mimeType
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

        if record() {
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

    /// How loud the microphone has been since this was last asked, from 0 to 1 (the loudest
    /// sample's amplitude), then starts over. 0 while nothing is recording.
    func level() -> Float {
        loudestLock.lock()
        defer { loudestLock.unlock() }

        let level = loudest
        loudest = 0

        return level
    }

    private func startMetering() {
        stopMetering()

        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self = self, let recorder = self.audioRecorder, self.recordingState == .recording else { return }

            recorder.updateMeters()
            let peak = min(1, max(0, pow(10, recorder.peakPower(forChannel: 0) / 20)))

            self.loudestLock.lock()
            self.loudest = max(self.loudest, peak)
            self.loudestLock.unlock()
        }

        RunLoop.main.add(timer, forMode: .common)
        meterTimer = timer
    }

    private func stopMetering() {
        let timer = meterTimer
        meterTimer = nil

        DispatchQueue.main.async {
            timer?.invalidate()
        }

        loudestLock.lock()
        loudest = 0
        loudestLock.unlock()
    }

    /// Lets go of the audio session and puts back the category it had before recording.
    private func releaseSession() {
        let audioSession = AVAudioSession.sharedInstance()

        do {
            try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            print("⚠️ Error deactivating audio session: \(error.localizedDescription)")
        }

        if let previous = previousSession {
            do {
                try audioSession.setCategory(previous.category, mode: previous.mode, options: previous.options)
            } catch {
                print("⚠️ Error restoring audio session category: \(error.localizedDescription)")
            }
        }

        previousSession = nil
    }

    /// Clean up resources in case of error
    private func cleanup() {
        recordingState = .idle
        audioRecorder?.stop()
        audioRecorder = nil
        stopMetering()
        releaseSession()
    }

    // MARK: - AVAudioRecorderDelegate

    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        guard recorder === audioRecorder, recordingState != .idle else {
            return
        }

        if !flag {
            print("❌ Recording finished unsuccessfully")
            cleanup()
            MicrophoneFunctions.dispatchCancelled(reason: "recording_failed")
            return
        }

        // Only reaching the limit ends a recording on its own: it's finished as Microphone.Stop would finish it.
        print("⏱️ Recording reached its limit of \(options.maxDuration)s")

        if let path = stop() {
            MicrophoneFunctions.dispatchRecorded(path: path, mimeType: options.mimeType)
        }
    }

    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        print("❌ Audio recorder encode error: \(error?.localizedDescription ?? "unknown")")
        cleanup()
        MicrophoneFunctions.dispatchCancelled(reason: "recording_failed")
    }
}
