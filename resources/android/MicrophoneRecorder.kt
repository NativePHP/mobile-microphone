package com.nativephp.microphone

import android.content.ContentValues
import android.content.Context
import android.media.MediaRecorder
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import android.util.Log
import com.nativephp.microphone.services.AudioRecordingService
import java.io.File
import java.io.IOException

/**
 * How a recording is made, from the parameters Microphone.Start was called with: "m4a" (AAC, the
 * default) or "wav" (mono 16-bit PCM at sampleRate), and a maximum duration after which it stops
 * by itself, as if Microphone.Stop was called (0 for no limit).
 */
data class RecordingOptions(
    val format: String = "m4a",
    val sampleRate: Int = 16000,
    val maxDurationMs: Long = 0
) {
    val isWav: Boolean get() = format == "wav"

    val mimeType: String get() = if (isWav) "audio/wav" else "audio/m4a"

    companion object {
        fun fromParameters(parameters: Map<String, Any>): RecordingOptions = RecordingOptions(
            format = if ((parameters["format"] as? String)?.lowercase() == "wav") "wav" else "m4a",
            sampleRate = (parameters["sampleRate"] as? Number)?.toInt() ?: 16000,
            maxDurationMs = (((parameters["maxDuration"] as? Number)?.toDouble() ?: 0.0) * 1000).toLong().coerceAtLeast(0)
        )
    }
}

/**
 * MicrophoneRecorder manages audio recording functionality for NativePHP
 * Handles recording state, file management, and MediaRecorder lifecycle
 * (or WavRecorder's, for WAV)
 */
class MicrophoneRecorder(
    private val context: Context,
    private val enableBackgroundRecording: Boolean = false
) {

    companion object {
        private const val TAG = "MicrophoneRecorder"
    }

    private var mediaRecorder: MediaRecorder? = null
    private var currentRecordingUri: Uri? = null
    private var recordingState: RecordingState = RecordingState.IDLE
    private var lastRecordingPath: String? = null
    private var currentFileDescriptor: android.os.ParcelFileDescriptor? = null
    private var wavRecorder: WavRecorder? = null
    private var wavFile: File? = null
    private var options = RecordingOptions()

    @Volatile
    private var reachedLimit = false

    enum class RecordingState {
        IDLE,
        RECORDING,
        PAUSED
    }

    /**
     * The MIME type of the recording made last, or under way.
     */
    val mimeType: String get() = options.mimeType

    /**
     * Start a new audio recording. Once it reaches options.maxDurationMs, onLimit runs on the main
     * thread, for the caller to stop it as Microphone.Stop would.
     * @return true if recording started successfully, false otherwise
     */
    fun start(options: RecordingOptions = RecordingOptions(), onLimit: () -> Unit = {}): Boolean {
        if (recordingState != RecordingState.IDLE) {
            Log.w(TAG, "⚠️ Cannot start recording - current state: $recordingState")
            return false
        }

        this.options = options
        reachedLimit = false

        if (options.isWav) {
            return startWav(onLimit)
        }

        return try {
            val resolver = context.contentResolver

            // Create audio file in MediaStore (device's Music/Recordings directory)
            val audioUri = resolver.insert(
                MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
                ContentValues().apply {
                    put(MediaStore.Audio.Media.DISPLAY_NAME, "NativePHP_${System.currentTimeMillis()}.m4a")
                    put(MediaStore.Audio.Media.MIME_TYPE, "audio/mp4")
                    put(MediaStore.Audio.Media.RELATIVE_PATH, "Music/Recordings")
                }
            ) ?: run {
                Log.e(TAG, "❌ Failed to create audio URI in MediaStore")
                return false
            }

            currentRecordingUri = audioUri
            Log.d(TAG, "🎤 Audio URI created: $currentRecordingUri")

            // Get ParcelFileDescriptor - store it so we can close it later
            currentFileDescriptor = resolver.openFileDescriptor(audioUri, "w")
                ?: run {
                    Log.e(TAG, "❌ Failed to get file descriptor")
                    cleanup()
                    return false
                }

            // Initialize MediaRecorder
            mediaRecorder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                MediaRecorder(context)
            } else {
                @Suppress("DEPRECATION")
                MediaRecorder()
            }

            mediaRecorder?.apply {
                setAudioSource(MediaRecorder.AudioSource.MIC)
                setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
                setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
                setAudioEncodingBitRate(128000)
                setAudioSamplingRate(44100)
                setOutputFile(currentFileDescriptor!!.fileDescriptor)

                if (options.maxDurationMs > 0) {
                    setMaxDuration(options.maxDurationMs.toInt())
                    setOnInfoListener { _, what, _ ->
                        if (what == MediaRecorder.MEDIA_RECORDER_INFO_MAX_DURATION_REACHED) {
                            Log.d(TAG, "⏱️ Recording reached its limit of ${options.maxDurationMs}ms")
                            reachedLimit = true
                            onLimit()
                        }
                    }
                }

                prepare()
                start()
            }

            // Start foreground service to enable recording while device is locked (if enabled)
            if (enableBackgroundRecording) {
                try {
                    AudioRecordingService.start(context)
                    Log.d(TAG, "🚀 Background recording service started")
                } catch (e: Exception) {
                    Log.w(TAG, "⚠️ Could not start background service (not enabled in config): ${e.message}")
                }
            }

            recordingState = RecordingState.RECORDING
            Log.d(TAG, "🎤 Recording started successfully")
            true
        } catch (e: IOException) {
            Log.e(TAG, "❌ IOException starting recording", e)
            cleanup()
            false
        } catch (e: IllegalStateException) {
            Log.e(TAG, "❌ IllegalStateException starting recording", e)
            cleanup()
            false
        } catch (e: Exception) {
            Log.e(TAG, "❌ Exception starting recording", e)
            cleanup()
            false
        }
    }

    /**
     * Records WAV into the cache directory, where the M4A path's copies go too.
     */
    private fun startWav(onLimit: () -> Unit): Boolean {
        val file = File(context.cacheDir, "audio_${System.currentTimeMillis()}.wav")
        val recorder = WavRecorder(file, options.sampleRate, options.maxDurationMs, onLimit)

        val started = try {
            recorder.start()
        } catch (e: Exception) {
            Log.e(TAG, "❌ Exception starting WAV recording", e)
            false
        }

        if (!started) {
            file.delete()
            return false
        }

        wavRecorder = recorder
        wavFile = file

        if (enableBackgroundRecording) {
            try {
                AudioRecordingService.start(context)
                Log.d(TAG, "🚀 Background recording service started")
            } catch (e: Exception) {
                Log.w(TAG, "⚠️ Could not start background service (not enabled in config): ${e.message}")
            }
        }

        recordingState = RecordingState.RECORDING
        Log.d(TAG, "🎤 WAV recording started successfully")

        return true
    }

    private fun stopWav(): String? {
        wavRecorder?.stop()
        wavRecorder = null

        val path = wavFile?.absolutePath
        wavFile = null
        lastRecordingPath = path
        recordingState = RecordingState.IDLE

        if (enableBackgroundRecording) {
            try {
                AudioRecordingService.stop(context)
            } catch (e: Exception) {
                Log.w(TAG, "⚠️ Could not stop background service: ${e.message}")
            }
        }

        Log.d(TAG, "⏹️ Recording stopped: $path")

        return path
    }

    /**
     * Stop the current recording
     * @return absolute path to the recorded file, or null if no recording or error
     */
    fun stop(): String? {
        if (recordingState == RecordingState.IDLE) {
            Log.w(TAG, "⚠️ Cannot stop recording - no active recording")
            return null
        }

        if (wavRecorder != null) {
            return stopWav()
        }

        return try {
            mediaRecorder?.apply {
                if (recordingState == RecordingState.PAUSED && Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                    // Resume before stopping if paused
                    resume()
                }
                try {
                    stop()
                } catch (e: RuntimeException) {
                    // Reaching the limit stops the recorder by itself, so it may already be stopped.
                    if (!reachedLimit) {
                        throw e
                    }
                }
                release()
            }
            mediaRecorder = null

            // CRITICAL: Close the file descriptor BEFORE trying to read the file
            // The file descriptor holds a write lock that prevents reading
            try {
                currentFileDescriptor?.close()
            } catch (e: Exception) {
                Log.e(TAG, "Error closing file descriptor", e)
            }
            currentFileDescriptor = null

            // Get the actual file path from the MediaStore URI
            val filePath = currentRecordingUri?.let { getAudioPathFromUri(it) }
            lastRecordingPath = filePath
            recordingState = RecordingState.IDLE

            // Stop foreground service (if it was started)
            if (enableBackgroundRecording) {
                try {
                    AudioRecordingService.stop(context)
                    Log.d(TAG, "⏹️ Background recording service stopped")
                } catch (e: Exception) {
                    Log.w(TAG, "⚠️ Could not stop background service: ${e.message}")
                }
            }

            Log.d(TAG, "⏹️ Recording stopped: $filePath")
            filePath
        } catch (e: IllegalStateException) {
            Log.e(TAG, "❌ IllegalStateException stopping recording", e)
            cleanup()
            null
        } catch (e: Exception) {
            Log.e(TAG, "❌ Exception stopping recording", e)
            cleanup()
            null
        }
    }

    /**
     * Copy audio file from MediaStore URI to cache directory
     * This is necessary because MediaStore.Audio.Media.DATA is deprecated and returns null on Android 10+
     */
    private fun getAudioPathFromUri(uri: Uri): String? {
        return try {
            // Copy MediaStore file to cache directory
            val timestamp = System.currentTimeMillis()
            val cacheFile = File(context.cacheDir, "audio_$timestamp.m4a")

            context.contentResolver.openInputStream(uri)?.use { input ->
                cacheFile.outputStream().buffered(64 * 1024).use { output ->
                    input.copyTo(output)
                }
            }

            // Clean up MediaStore entry after copying
            try {
                context.contentResolver.delete(uri, null, null)
            } catch (e: Exception) {
                Log.w(TAG, "⚠️ Could not delete MediaStore entry: ${e.message}")
            }

            cacheFile.absolutePath
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error copying audio from URI: ${e.message}", e)
            null
        }
    }

    /**
     * Pause the current recording (Android 7.0+)
     */
    fun pause() {
        if (recordingState != RecordingState.RECORDING) {
            Log.w(TAG, "⚠️ Cannot pause - not currently recording")
            return
        }

        wavRecorder?.let {
            it.pause()
            recordingState = RecordingState.PAUSED
            Log.d(TAG, "⏸️ Recording paused")
            return
        }

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) {
            Log.w(TAG, "⚠️ Pause is not supported on Android versions below 7.0")
            return
        }

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                mediaRecorder?.pause()
                recordingState = RecordingState.PAUSED
                Log.d(TAG, "⏸️ Recording paused")
            }
        } catch (e: IllegalStateException) {
            Log.e(TAG, "❌ IllegalStateException pausing recording", e)
        } catch (e: Exception) {
            Log.e(TAG, "❌ Exception pausing recording", e)
        }
    }

    /**
     * Resume a paused recording (Android 7.0+)
     */
    fun resume() {
        if (recordingState != RecordingState.PAUSED) {
            Log.w(TAG, "⚠️ Cannot resume - not currently paused")
            return
        }

        wavRecorder?.let {
            it.resume()
            recordingState = RecordingState.RECORDING
            Log.d(TAG, "▶️ Recording resumed")
            return
        }

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) {
            Log.w(TAG, "⚠️ Resume is not supported on Android versions below 7.0")
            return
        }

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                mediaRecorder?.resume()
                recordingState = RecordingState.RECORDING
                Log.d(TAG, "▶️ Recording resumed")
            }
        } catch (e: IllegalStateException) {
            Log.e(TAG, "❌ IllegalStateException resuming recording", e)
        } catch (e: Exception) {
            Log.e(TAG, "❌ Exception resuming recording", e)
        }
    }

    /**
     * Get the current recording status
     * @return "idle", "recording", or "paused"
     */
    fun getStatus(): String {
        return when (recordingState) {
            RecordingState.IDLE -> "idle"
            RecordingState.RECORDING -> "recording"
            RecordingState.PAUSED -> "paused"
        }
    }

    /**
     * How loud the microphone has been since this was last asked, from 0 to 1 (the loudest
     * sample's amplitude), then starts over. 0 while nothing is recording.
     */
    fun level(): Float {
        if (recordingState != RecordingState.RECORDING) {
            return 0f
        }

        wavRecorder?.let { return it.level() }

        return try {
            (mediaRecorder?.maxAmplitude ?: 0) / 32767f
        } catch (e: IllegalStateException) {
            0f
        }
    }

    /**
     * Get the path to the last recorded audio file
     * @return path to the last recording, or null if none exists
     */
    fun getLastRecording(): String? {
        return lastRecordingPath
    }

    /**
     * Clean up resources in case of error
     */
    private fun cleanup() {
        try {
            wavRecorder?.stop()
        } catch (e: Exception) {
            Log.e(TAG, "Error stopping WavRecorder", e)
        }
        wavRecorder = null
        wavFile?.delete()
        wavFile = null

        try {
            mediaRecorder?.release()
        } catch (e: Exception) {
            Log.e(TAG, "Error releasing MediaRecorder", e)
        }
        mediaRecorder = null

        // Close file descriptor to prevent leaks
        try {
            currentFileDescriptor?.close()
        } catch (e: Exception) {
            Log.e(TAG, "Error closing file descriptor", e)
        }
        currentFileDescriptor = null

        // Stop foreground service if running (and if enabled)
        if (enableBackgroundRecording) {
            try {
                AudioRecordingService.stop(context)
            } catch (e: Exception) {
                Log.w(TAG, "⚠️ Could not stop background service during cleanup: ${e.message}")
            }
        }

        recordingState = RecordingState.IDLE
    }

    /**
     * Release all resources
     * Should be called when the recorder is no longer needed
     */
    fun release() {
        cleanup()
        currentRecordingUri = null
        lastRecordingPath = null
    }
}