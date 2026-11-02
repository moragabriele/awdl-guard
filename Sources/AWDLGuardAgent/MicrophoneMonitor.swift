import CoreAudio
import Foundation

/// Reports whether any process is capturing audio input, which is how calls in Zoom,
/// Teams, FaceTime or Google Meet in a browser are detected. Only reads Core Audio
/// state; it never opens the microphone, so no TCC prompt is involved.
final class MicrophoneMonitor {
    private var timer: Timer?
    private(set) var isInUse = false

    var onChange: (() -> Void)?

    func start() {
        isInUse = Self.query()
        // Polling keeps this simple and robust across device hot-plugs; each check is a few property reads.
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self else { return }
            let now = Self.query()
            if now != self.isInUse {
                self.isInUse = now
                self.onChange?()
            }
        }
    }

    static func query() -> Bool {
        if let perProcess = anyProcessRunningInput() {
            return perProcess
        }
        return anyInputDeviceRunning()
    }

    /// Precise per-process check. Returns nil when the OS does not support process objects.
    private static func anyProcessRunningInput() -> Bool? {
        guard let processes: [AudioObjectID] = arrayProperty(
            AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyProcessObjectList) else {
            return nil
        }
        return processes.contains { uint32Property($0, kAudioProcessPropertyIsRunningInput) == 1 }
    }

    /// Fallback: an input-capable device is running. Can also fire for headsets that are
    /// only playing audio, because the flag covers the whole device.
    private static func anyInputDeviceRunning() -> Bool {
        let devices: [AudioObjectID] = arrayProperty(
            AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDevices) ?? []
        return devices.contains { device in
            let streams: [AudioObjectID] = arrayProperty(device, kAudioDevicePropertyStreams,
                                                        scope: kAudioObjectPropertyScopeInput) ?? []
            return !streams.isEmpty && uint32Property(device, kAudioDevicePropertyDeviceIsRunningSomewhere) == 1
        }
    }

    private static func arrayProperty(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                                      scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> [AudioObjectID]? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr else { return nil }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &ids) == noErr else { return nil }
        return ids
    }

    private static func uint32Property(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }
}
