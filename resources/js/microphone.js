/**
 * Microphone Plugin for NativePHP Mobile
 *
 * @example Start Recording
 * import { Microphone } from '@nativephp/microphone';
 *
 * // Start recording with fluent API
 * await Microphone.record().id('voice-memo');
 *
 * @example Control Recording
 * import { Microphone } from '@nativephp/microphone';
 *
 * // Pause recording
 * await Microphone.pause();
 *
 * // Resume recording
 * await Microphone.resume();
 *
 * // Stop and get recording
 * await Microphone.stop();
 *
 * @example Get Recording Status
 * import { Microphone } from '@nativephp/microphone';
 *
 * const status = await Microphone.getStatus();
 * const recording = await Microphone.getRecording();
 *
 * @example Event Listening
 * import { On } from '@nativephp/mobile';
 * import { Events } from '@nativephp/microphone';
 *
 * On(Events.Recorded, (event) => {
 *   console.log('Recording path:', event.path);
 * });
 */

const baseUrl = '/_native/api/call';

export async function BridgeCall(method, params = {}) {
    const response = await fetch(baseUrl, {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json',
            'X-CSRF-TOKEN': document.querySelector('meta[name="csrf-token"]')?.content || ''
        },
        body: JSON.stringify({ method, params })
    });

    const result = await response.json();

    if (result.status === 'error') {
        throw new Error(result.message || 'Native call failed');
    }

    return result.data;
}

// ============================================================================
// Microphone Functions
// ============================================================================

/**
 * PendingMicrophone - Fluent builder for microphone recording
 * Matches PHP: Microphone::record() returns PendingMicrophone
 */
class PendingMicrophone {
    constructor() {
        this._id = null;
        this._event = null;
        this._started = false;
    }

    /**
     * Set a unique identifier for this recording
     * @param {string} id - Recording ID
     * @returns {PendingMicrophone}
     */
    id(id) {
        this._id = id;
        return this;
    }

    /**
     * Set a custom event class name to fire
     * @param {string} event - Event class name
     * @returns {PendingMicrophone}
     */
    event(event) {
        this._event = event;
        return this;
    }

    /**
     * Make this builder thenable so it can be awaited directly
     * @param {Function} resolve - Promise resolve function
     * @param {Function} reject - Promise reject function
     * @returns {Promise<void>}
     */
    then(resolve, reject) {
        if (this._started) {
            return resolve();
        }

        this._started = true;

        const params = {};
        if (this._id) params.id = this._id;
        if (this._event) params.event = this._event;

        return BridgeCall('Microphone.Start', params).then(resolve, reject);
    }
}

/**
 * Start microphone recording
 * @returns {PendingMicrophone}
 */
function recordMicrophoneFunction() {
    return new PendingMicrophone();
}

/**
 * Stop microphone recording
 * @returns {Promise<any>}
 */
function stopMicrophoneFunction() {
    return BridgeCall('Microphone.Stop', {});
}

/**
 * Pause microphone recording
 * @returns {Promise<any>}
 */
function pauseMicrophoneFunction() {
    return BridgeCall('Microphone.Pause', {});
}

/**
 * Resume microphone recording
 * @returns {Promise<any>}
 */
function resumeMicrophoneFunction() {
    return BridgeCall('Microphone.Resume', {});
}

/**
 * Get microphone recording status
 * @returns {Promise<any>}
 */
function getMicrophoneStatusFunction() {
    return BridgeCall('Microphone.GetStatus', {});
}

/**
 * Get the path to the last recorded audio file
 * @returns {Promise<any>}
 */
function getMicrophoneRecordingFunction() {
    return BridgeCall('Microphone.GetRecording', {});
}

export const Microphone = {
    record: recordMicrophoneFunction,
    stop: stopMicrophoneFunction,
    pause: pauseMicrophoneFunction,
    resume: resumeMicrophoneFunction,
    getStatus: getMicrophoneStatusFunction,
    getRecording: getMicrophoneRecordingFunction
};

export { PendingMicrophone };

// ============================================================================
// Native Event Constants
// ============================================================================

/**
 * Native event class name constants for type-safe event listening
 * Usage: import { Events } from '@nativephp/microphone';
 *        import { On } from '@nativephp/mobile';
 *        On(Events.Recorded, (event) => { ... });
 */
export const Events = {
    Recorded: 'NativePHP\\Microphone\\Events\\MicrophoneRecorded',
    Cancelled: 'NativePHP\\Microphone\\Events\\MicrophoneCancelled',
};

export default Microphone;
