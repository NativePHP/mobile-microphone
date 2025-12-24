package com.nativephp.microphone

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.fragment.app.FragmentActivity
import com.nativephp.mobile.bridge.BridgeFunction
import com.nativephp.mobile.utils.NativeActionCoordinator

/**
 * Functions related to microphone recording operations
 * Namespace: "Microphone.*"
 */
object MicrophoneFunctions {

    var microphoneRecorder: MicrophoneRecorder? = null
    private var isCallbackRegistered = false

    /**
     * Register the audio permission callback with NativeActionCoordinator
     * This is called when the microphone recording is started
     */
    private fun ensureCallbackRegistered(activity: FragmentActivity, context: Context) {
        if (!isCallbackRegistered) {
            val coord = NativeActionCoordinator.install(activity)
            coord.onAudioPermissionGranted = { id, event ->
                Log.d("MicrophoneFunctions", "🎤 Audio permission granted callback - id=$id, event=$event")

                // Initialize recorder if needed
                if (microphoneRecorder == null) {
                    microphoneRecorder = MicrophoneRecorder(context)
                }

                microphoneRecorder?.start() ?: false
            }
            isCallbackRegistered = true
            Log.d("MicrophoneFunctions", "✅ Audio permission callback registered")
        }
    }

    /**
     * Start microphone recording
     * Parameters:
     *   - id: (optional) string - Unique identifier for this recording
     *   - event: (optional) string - Custom event class to dispatch when recording completes
     * Returns:
     *   - status: string - "success" or "error"
     * Events:
     *   - Fires "NativePHP\Microphone\Events\MicrophoneRecorded" when recording is stopped
     */
    class Start(private val activity: FragmentActivity) : BridgeFunction {
        override fun execute(parameters: Map<String, Any>): Map<String, Any> {
            val id = parameters["id"] as? String
            val event = parameters["event"] as? String

            Log.d("MicrophoneFunctions.Start", "🎤 Starting microphone recording with id=$id, event=$event")

            // Ensure callback is registered
            ensureCallbackRegistered(activity, activity.applicationContext)

            // Delegate to NativeActionCoordinator for permission handling
            val coord = NativeActionCoordinator.install(activity)
            coord.launchMicrophoneRecorder(id, event)

            return emptyMap()
        }
    }

    /**
     * Stop microphone recording
     * Events:
     *   - Fires "NativePHP\Microphone\Events\MicrophoneRecorded" via Livewire dispatch when stopped
     */
    class Stop(private val activity: FragmentActivity) : BridgeFunction {
        override fun execute(parameters: Map<String, Any>): Map<String, Any> {
            Log.d("MicrophoneFunctions.Stop", "⏹️ Stopping microphone recording")

            val path = microphoneRecorder?.stop()

            if (path != null) {
                // Retrieve stored id and event class from SharedPreferences
                val prefs = activity.getSharedPreferences("microphone_recording", Context.MODE_PRIVATE)
                val id = prefs.getString("pending_id", null)
                val eventClass = prefs.getString("pending_event", null)
                    ?: "NativePHP\\Microphone\\Events\\MicrophoneRecorded"

                Log.d("MicrophoneFunctions.Stop", "📤 Dispatching $eventClass with path=$path, id=$id")

                // Clean up stored values
                prefs.edit()
                    .remove("pending_id")
                    .remove("pending_event")
                    .apply()

                // Create payload JSON
                val payload = org.json.JSONObject().apply {
                    put("path", path)
                    put("mimeType", "audio/m4a")
                    if (id != null) {
                        put("id", id)
                    }
                }

                // Dispatch event directly to Livewire via JavaScript (must be on main thread)
                Handler(Looper.getMainLooper()).post {
                    NativeActionCoordinator.dispatchEvent(activity, eventClass, payload.toString())
                }
            }

            return emptyMap()
        }
    }

    /**
     * Pause microphone recording
     */
    class Pause : BridgeFunction {
        override fun execute(parameters: Map<String, Any>): Map<String, Any> {
            Log.d("MicrophoneFunctions.Pause", "⏸️ Pausing microphone recording")
            microphoneRecorder?.pause()
            return emptyMap()
        }
    }

    /**
     * Resume microphone recording
     */
    class Resume : BridgeFunction {
        override fun execute(parameters: Map<String, Any>): Map<String, Any> {
            Log.d("MicrophoneFunctions.Resume", "▶️ Resuming microphone recording")
            microphoneRecorder?.resume()
            return emptyMap()
        }
    }

    /**
     * Get current recording status
     */
    class GetStatus(private val context: Context) : BridgeFunction {
        override fun execute(parameters: Map<String, Any>): Map<String, Any> {
            Log.d("MicrophoneFunctions.GetStatus", "📊 Getting microphone status")

            // Initialize recorder if needed to get consistent status
            if (microphoneRecorder == null) {
                Log.d("MicrophoneFunctions.GetStatus", "🔧 Initializing MicrophoneRecorder")
                microphoneRecorder = MicrophoneRecorder(context)
            }

            val status = microphoneRecorder?.getStatus() ?: "idle"
            Log.d("MicrophoneFunctions.GetStatus", "📊 Status: $status")

            val result = mapOf("status" to status)
            Log.d("MicrophoneFunctions.GetStatus", "📤 Returning: $result")

            return result
        }
    }

    /**
     * Get path to last recording
     */
    class GetRecording(private val context: Context) : BridgeFunction {
        override fun execute(parameters: Map<String, Any>): Map<String, Any> {
            // Initialize recorder if needed
            if (microphoneRecorder == null) {
                microphoneRecorder = MicrophoneRecorder(context)
            }
            val path = microphoneRecorder?.getLastRecording()
            return if (path != null) {
                mapOf("path" to path)
            } else {
                mapOf("path" to "")
            }
        }
    }
}