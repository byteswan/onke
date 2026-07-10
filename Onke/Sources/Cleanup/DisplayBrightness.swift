import Foundation
import CoreGraphics

/// Isolated wrapper around display brightness — the flakiest API surface in the project
/// (spec §7.2, risk #1). We resolve the private `DisplayServices` symbols at runtime via
/// `dlopen`/`dlsym` so that if they're unavailable on some hardware/macOS the feature
/// simply reports `isAvailable == false` and the UI hides the control, rather than failing
/// to launch.
enum DisplayBrightness {

    private typealias GetFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetFn = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private static let handle: UnsafeMutableRawPointer? =
        dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW)

    private static let getFn: GetFn? = handle
        .flatMap { dlsym($0, "DisplayServicesGetBrightness") }
        .map { unsafeBitCast($0, to: GetFn.self) }

    private static let setFn: SetFn? = handle
        .flatMap { dlsym($0, "DisplayServicesSetBrightness") }
        .map { unsafeBitCast($0, to: SetFn.self) }

    static var isAvailable: Bool { getFn != nil && setFn != nil }

    /// Main display brightness 0...1, or nil if the API is unavailable / errored.
    static func get() -> Float? {
        guard let getFn else { return nil }
        var value: Float = 0
        let result = getFn(CGMainDisplayID(), &value)
        return result == 0 ? value : nil
    }

    static func set(_ value: Float) {
        guard let setFn else { return }
        _ = setFn(CGMainDisplayID(), max(0, min(1, value)))
    }
}
