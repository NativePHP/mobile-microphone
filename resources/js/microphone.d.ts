/**
 * Microphone Plugin for NativePHP Mobile - TypeScript Declarations
 */

export function BridgeCall(method: string, params?: Record<string, any>): Promise<any>;

export class PendingMicrophone implements PromiseLike<void> {
    constructor();
    id(id: string): PendingMicrophone;
    event(event: string): PendingMicrophone;
    then<TResult1 = void, TResult2 = never>(
        onfulfilled?: ((value: void) => TResult1 | PromiseLike<TResult1>) | null,
        onrejected?: ((reason: any) => TResult2 | PromiseLike<TResult2>) | null
    ): PromiseLike<TResult1 | TResult2>;
}

export const Microphone: {
    record(): PendingMicrophone;
    stop(): Promise<any>;
    pause(): Promise<any>;
    resume(): Promise<any>;
    getStatus(): Promise<any>;
    getRecording(): Promise<any>;
};

export function On(eventName: string, callback: (payload: any, eventName: string) => void): void;
export function Off(eventName: string, callback: (payload: any, eventName: string) => void): void;

export const MicrophoneEvents: {
    Recorded: string;
    Cancelled: string;
};

export default Microphone;
