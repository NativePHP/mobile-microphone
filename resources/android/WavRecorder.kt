package com.nativephp.microphone

import android.annotation.SuppressLint
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Handler
import android.os.Looper
import android.util.Log
import java.io.File
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.abs

/**
 * Records mono 16-bit PCM WAV straight from AudioRecord, which MediaRecorder can't write.
 *
 * The header goes in first with its sizes empty and is filled in when the recording stops. With a
 * maximum duration, the recording stops itself once it holds that many samples and onLimit runs on
 * the main thread. The caller checks RECORD_AUDIO before starting.
 */
class WavRecorder(
    private val file: File,
    private val sampleRate: Int,
    private val maxDurationMs: Long,
    private val onLimit: () -> Unit
) {

    companion object {
        private const val TAG = "WavRecorder"
        private const val HEADER_BYTES = 44
    }

    private var audioRecord: AudioRecord? = null
    private var thread: Thread? = null

    @Volatile
    private var running = false

    @Volatile
    private var paused = false

    @Volatile
    private var loudest = 0

    private var dataBytes = 0L

    @SuppressLint("MissingPermission")
    fun start(): Boolean {
        val minBuffer = AudioRecord.getMinBufferSize(sampleRate, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)

        if (minBuffer <= 0) {
            Log.e(TAG, "❌ $sampleRate Hz mono 16-bit isn't supported here")
            return false
        }

        val record = AudioRecord(
            MediaRecorder.AudioSource.MIC,
            sampleRate,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
            minBuffer * 2
        )

        if (record.state != AudioRecord.STATE_INITIALIZED) {
            Log.e(TAG, "❌ AudioRecord failed to initialize")
            record.release()
            return false
        }

        val output = RandomAccessFile(file, "rw")
        output.setLength(0)
        output.write(header(0))

        try {
            record.startRecording()
        } catch (e: IllegalStateException) {
            Log.e(TAG, "❌ Could not start AudioRecord", e)
            record.release()
            output.close()
            return false
        }

        audioRecord = record
        dataBytes = 0
        running = true
        paused = false

        val maxBytes = if (maxDurationMs > 0) sampleRate * 2L * maxDurationMs / 1000 else Long.MAX_VALUE

        thread = Thread({
            val samples = ShortArray(minBuffer / 2)
            val bytes = ByteBuffer.allocate(samples.size * 2).order(ByteOrder.LITTLE_ENDIAN)
            var reachedLimit = false

            try {
                while (running) {
                    val read = record.read(samples, 0, samples.size)

                    if (read < 0) {
                        Log.e(TAG, "❌ AudioRecord read failed: $read")
                        break
                    }

                    if (read == 0 || paused) {
                        continue
                    }

                    val count = minOf(read.toLong(), (maxBytes - dataBytes) / 2).toInt()
                    var peak = 0
                    bytes.clear()

                    for (index in 0 until count) {
                        bytes.putShort(samples[index])
                        peak = maxOf(peak, abs(samples[index].toInt()))
                    }

                    output.write(bytes.array(), 0, count * 2)
                    dataBytes += count * 2
                    loudest = maxOf(loudest, peak)

                    if (dataBytes >= maxBytes) {
                        reachedLimit = true
                        break
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "❌ Recording broke off", e)
            } finally {
                output.seek(0)
                output.write(header(dataBytes))
                output.close()
            }

            if (reachedLimit && running) {
                Log.d(TAG, "⏱️ Recording reached its limit of ${maxDurationMs}ms")
                Handler(Looper.getMainLooper()).post(onLimit)
            }
        }, "NativePHP-WavRecorder")

        thread?.start()

        return true
    }

    /**
     * Stops recording and waits for the file to be finished, header and all.
     */
    fun stop() {
        running = false
        thread?.join(2000)
        thread = null

        try {
            audioRecord?.stop()
        } catch (e: IllegalStateException) {
            Log.w(TAG, "⚠️ AudioRecord was already stopped")
        }

        audioRecord?.release()
        audioRecord = null
    }

    fun pause() {
        paused = true
    }

    fun resume() {
        paused = false
    }

    /**
     * The loudest sample since this was last asked, from 0 to 1.
     */
    fun level(): Float {
        val level = loudest
        loudest = 0

        return level / 32768f
    }

    private fun header(dataBytes: Long): ByteArray {
        val buffer = ByteBuffer.allocate(HEADER_BYTES).order(ByteOrder.LITTLE_ENDIAN)

        buffer.put("RIFF".toByteArray(Charsets.US_ASCII))
        buffer.putInt((36 + dataBytes).toInt())
        buffer.put("WAVE".toByteArray(Charsets.US_ASCII))
        buffer.put("fmt ".toByteArray(Charsets.US_ASCII))
        buffer.putInt(16)
        buffer.putShort(1)
        buffer.putShort(1)
        buffer.putInt(sampleRate)
        buffer.putInt(sampleRate * 2)
        buffer.putShort(2)
        buffer.putShort(16)
        buffer.put("data".toByteArray(Charsets.US_ASCII))
        buffer.putInt(dataBytes.toInt())

        return buffer.array()
    }
}
