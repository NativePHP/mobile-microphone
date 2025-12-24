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
 * MicrophoneRecorder manages audio recording functionality for NativePHP
 * Handles recording state, file management, and MediaRecorder lifecycle
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

    enum class RecordingState {
        IDLE,
        RECORDING,
        PAUSED
    }

    /**
     * Start a new audio recording
     * @return true if recording started successfully, false otherwise
     */
    fun start(): Boolean {
        if (recordingState != RecordingState.IDLE) {
            Log.w(TAG, "⚠️ Cannot start recording - current state: $recordingState")
            return false
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
     * Stop the current recording
     * @return absolute path to the recorded file, or null if no recording or error
     */
    fun stop(): String? {
        if (recordingState == RecordingState.IDLE) {
            Log.w(TAG, "⚠️ Cannot stop recording - no active recording")
            return null
        }

        return try {
            mediaRecorder?.apply {
                if (recordingState == RecordingState.PAUSED && Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                    // Resume before stopping if paused
                    resume()
                }
                stop()
                release()
            }
            mediaRecorder = null

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