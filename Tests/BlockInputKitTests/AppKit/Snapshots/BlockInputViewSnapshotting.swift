import AppKit
import SnapshotTesting

private let appKitSnapshotPrecision: Float = 0.995
private let appKitSnapshotPerceptualPrecision: Float = 0.995
private let appKitSnapshotScale: CGFloat = 2
private let fixedScaleSnapshotPrecision: Float = 0.9

/// Uses SnapshotTesting's native AppKit renderer on Retina displays, and falls back to a fixed
/// Retina-scale renderer when headless CI only exposes a 1x display. The fixed scale keeps generated
/// images at the same pixel dimensions as the checked-in local baselines.
func appKitSnapshotImage() -> Snapshotting<NSView, NSImage> {
    if usesNativeSnapshotRenderer {
        return .image(
            precision: appKitSnapshotPrecision,
            perceptualPrecision: appKitSnapshotPerceptualPrecision
        )
    }
    return Snapshotting(pathExtension: "png", diffing: .image(
        precision: fixedScaleSnapshotPrecision,
        perceptualPrecision: fixedScaleSnapshotPrecision
    )) { view in
        MainActor.assumeIsolated {
            renderAppKitSnapshotImage(for: view)
        }
    }
}

private var usesNativeSnapshotRenderer: Bool {
    ProcessInfo.processInfo.environment["BLOCKINPUTKIT_FORCE_FIXED_SCALE_SNAPSHOTS"] != "true"
        && (NSScreen.main?.backingScaleFactor ?? 1) >= appKitSnapshotScale
}

@MainActor
private func renderAppKitSnapshotImage(for view: NSView) -> NSImage {
    let bounds = view.bounds
    guard bounds.width > 0, bounds.height > 0 else {
        fatalError("View not renderable to image at size \(bounds.size)")
    }
    guard let bitmapRep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(bounds.width * appKitSnapshotScale),
        pixelsHigh: Int(bounds.height * appKitSnapshotScale),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        fatalError("Unable to create snapshot bitmap representation at size \(bounds.size)")
    }
    bitmapRep.size = bounds.size
    view.cacheDisplay(in: bounds, to: bitmapRep)
    let image = NSImage(size: bounds.size)
    image.addRepresentation(bitmapRep)
    return image
}
