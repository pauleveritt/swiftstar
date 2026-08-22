import Foundation
import IOKit
import CoreFoundation

// Private IOReport FFI for system power (watts). Approach and channel keys
// from vladkens/macmon (MIT) via ds4-control's PowerCollector/IOReportBridge
// (facts cross with citation; this implementation is written fresh). Apple
// Silicon only — Intel returns nil.

@_silgen_name("IOReportCopyChannelsInGroup")
private func IOReportCopyChannelsInGroup(_ group: OpaquePointer?, _ subgroup: OpaquePointer?, _ c: UInt64, _ d: UInt64, _ e: UInt64) -> OpaquePointer?
@_silgen_name("IOReportMergeChannels")
private func IOReportMergeChannels(_ a: OpaquePointer, _ b: OpaquePointer, _ nilArg: OpaquePointer?)
@_silgen_name("IOReportCreateSubscription")
private func IOReportCreateSubscription(_ a: UnsafeRawPointer?, _ chan: OpaquePointer, _ outChan: UnsafeMutablePointer<OpaquePointer?>, _ d: UInt64, _ e: OpaquePointer?) -> OpaquePointer?
@_silgen_name("IOReportCreateSamples")
private func IOReportCreateSamples(_ subs: OpaquePointer, _ chan: OpaquePointer, _ c: OpaquePointer?) -> OpaquePointer?
@_silgen_name("IOReportCreateSamplesDelta")
private func IOReportCreateSamplesDelta(_ a: OpaquePointer, _ b: OpaquePointer, _ c: OpaquePointer?) -> OpaquePointer?
@_silgen_name("IOReportChannelGetChannelName")
private func IOReportChannelGetChannelName(_ a: OpaquePointer) -> OpaquePointer?
@_silgen_name("IOReportChannelGetUnitLabel")
private func IOReportChannelGetUnitLabel(_ a: OpaquePointer) -> OpaquePointer?
@_silgen_name("IOReportSimpleGetIntegerValue")
private func IOReportSimpleGetIntegerValue(_ a: OpaquePointer, _ b: Int32) -> Int64

/// Cached IOReport subscription for the "Energy Model" group. The subscription
/// is created once and reused for every sample — creating a new subscription per
/// sample would leak (there is no public release for it), so this mirrors the
/// predecessor's IOReportBridge design: subscribe in init, sample repeatedly.
/// `@unchecked Sendable`: all stored state is immutable `let` (read-only after
/// init); the deinit release is the only mutation and happens after the last
/// reference is gone.
final class IOReportPower: @unchecked Sendable {
    private let subscription: OpaquePointer
    private let channels: OpaquePointer

    init?() {
        let group = "Energy Model" as CFString
        guard let chanPtr = IOReportCopyChannelsInGroup(
            OpaquePointer(Unmanaged.passUnretained(group).toOpaque()), nil, 0, 0, 0
        ) else { return nil }
        var subscribed: OpaquePointer?
        guard let subs = IOReportCreateSubscription(nil, chanPtr, &subscribed, 0, nil) else {
            Unmanaged<CFDictionary>.fromOpaque(UnsafeRawPointer(chanPtr)).release()
            return nil
        }
        // The subscription's output channel set is not needed beyond setup;
        // release it immediately (the subscription keeps its own reference).
        if let subscribed {
            Unmanaged<CFMutableDictionary>.fromOpaque(UnsafeRawPointer(subscribed)).release()
        }
        self.subscription = subs
        self.channels = chanPtr
    }

    /// Total system power in watts, sampled over `windowMs`. Suspends for
    /// `windowMs` while sampling (async, never blocks a thread). Returns 0 on
    /// Intel or any failure.
    func totalWatts(windowMs: UInt32 = 100) async -> Double {
        guard let s1 = IOReportCreateSamples(subscription, channels, nil) else { return 0 }
        try? await Task.sleep(nanoseconds: UInt64(windowMs) * 1_000_000)
        guard let s2 = IOReportCreateSamples(subscription, channels, nil) else {
            Unmanaged<CFDictionary>.fromOpaque(UnsafeRawPointer(s1)).release()
            return 0
        }
        guard let delta = IOReportCreateSamplesDelta(s1, s2, nil) else {
            Unmanaged<CFDictionary>.fromOpaque(UnsafeRawPointer(s1)).release()
            Unmanaged<CFDictionary>.fromOpaque(UnsafeRawPointer(s2)).release()
            return 0
        }
        defer {
            Unmanaged<CFDictionary>.fromOpaque(UnsafeRawPointer(s1)).release()
            Unmanaged<CFDictionary>.fromOpaque(UnsafeRawPointer(s2)).release()
            Unmanaged<CFDictionary>.fromOpaque(UnsafeRawPointer(delta)).release()
        }
        return Self.sumWatts(delta: delta, elapsedMs: Double(windowMs))
    }

    deinit {
        // Channel dict is +1 retained; the subscription has no public release
        // and is effectively permanent for the process lifetime.
        Unmanaged<CFMutableDictionary>.fromOpaque(UnsafeRawPointer(channels)).release()
    }

    private static func sumWatts(delta: OpaquePointer, elapsedMs: Double) -> Double {
        let deltaCF = Unmanaged<CFDictionary>.fromOpaque(UnsafeRawPointer(delta)).takeUnretainedValue()
        guard let arrayPtr = CFDictionaryGetValue(deltaCF, Unmanaged.passUnretained("IOReportChannels" as CFString).toOpaque()) else { return 0 }
        let array = Unmanaged<CFArray>.fromOpaque(arrayPtr).takeUnretainedValue()
        var total = 0.0
        for i in 0..<CFArrayGetCount(array) {
            guard let itemPtr = CFArrayGetValueAtIndex(array, i) else { continue }
            let cfPtr = OpaquePointer(itemPtr)
            let channel = cfString(IOReportChannelGetChannelName(cfPtr))
            guard isPowerChannel(channel) else { continue }
            let unit = cfString(IOReportChannelGetUnitLabel(cfPtr)).trimmingCharacters(in: .whitespacesAndNewlines)
            let perSecond = Double(IOReportSimpleGetIntegerValue(cfPtr, 0)) / (elapsedMs / 1000.0)
            switch unit {
            case "mJ": total += perSecond / 1e3
            case "uJ": total += perSecond / 1e6
            case "nJ": total += perSecond / 1e9
            default: break
            }
        }
        return total
    }

    private static func isPowerChannel(_ channel: String) -> Bool {
        channel == "GPU Energy" || channel.hasSuffix("CPU Energy") || channel.hasPrefix("ANE")
    }

    private static func cfString(_ p: OpaquePointer?) -> String {
        guard let p else { return "" }
        return Unmanaged<CFString>.fromOpaque(UnsafeRawPointer(p)).takeUnretainedValue() as String
    }
}
