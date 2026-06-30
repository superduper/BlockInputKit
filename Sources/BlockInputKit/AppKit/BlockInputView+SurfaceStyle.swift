import AppKit
import QuartzCore

extension BlockInputView {
    func applyEditorSurfaceStyle() {
        wantsLayer = true
        effectiveAppearance.performAsCurrentDrawingAppearance {
            applyRootLayerSurfaceStyle()
            if let scrollBackgroundColor = style.editorSurface.scrollBackgroundColor {
                scrollView.backgroundColor = scrollBackgroundColor
                scrollView.drawsBackground = true
                scrollView.layer?.backgroundColor = scrollBackgroundColor.cgColor
                scrollView.contentView.backgroundColor = scrollBackgroundColor
                scrollView.contentView.drawsBackground = true
                scrollView.contentView.layer?.backgroundColor = scrollBackgroundColor.cgColor
            } else {
                scrollView.backgroundColor = .clear
                scrollView.drawsBackground = false
                scrollView.layer?.backgroundColor = NSColor.clear.cgColor
                scrollView.contentView.backgroundColor = .clear
                scrollView.contentView.drawsBackground = false
                scrollView.contentView.layer?.backgroundColor = NSColor.clear.cgColor
            }
            collectionView.backgroundColors = style.editorSurface.collectionBackgroundColor.map { [$0] } ?? []
            collectionView.layer?.backgroundColor = (style.editorSurface.collectionBackgroundColor ?? .clear).cgColor
        }
    }

    private func applyRootLayerSurfaceStyle() {
        guard let layer else {
            return
        }
        guard let chrome = style.editorSurface.chrome else {
            removeEditorChromeLayers()
            editorChromeView.configure(chrome: nil, fallbackFillColor: nil)
            layer.backgroundColor = style.editorSurface.editorBackgroundColor?.cgColor
            layer.borderColor = nil
            layer.borderWidth = 0
            layer.cornerRadius = 0
            layer.maskedCorners = BlockInputEditorChromeCorners.all.caCornerMask
            layer.masksToBounds = false
            return
        }

        let fillColor = chrome.fillColor ?? style.editorSurface.editorBackgroundColor
        editorChromeView.configure(chrome: chrome, fallbackFillColor: style.editorSurface.editorBackgroundColor)
        layer.backgroundColor = nil
        layer.borderColor = nil
        layer.borderWidth = 0
        layer.cornerRadius = 0
        layer.maskedCorners = BlockInputEditorChromeCorners.all.caCornerMask
        layer.masksToBounds = false
        installEditorChromeLayersIfNeeded()
        editorChromeFillLayer.fillColor = fillColor?.cgColor
        editorChromeStrokeLayer.fillColor = nil
        editorChromeStrokeLayer.strokeColor = chrome.strokeColor?.cgColor
        editorChromeStrokeLayer.lineWidth = chrome.strokeColor == nil ? 0 : chrome.borderWidth
        layer.mask = chrome.clipsContentToShape ? editorChromeMaskLayer : nil
        updateEditorChromeLayers()
    }

    func updateEditorChromeLayers() {
        guard style.editorSurface.chrome != nil else {
            return
        }
        let currentBounds = bounds
        editorChromeFillLayer.frame = currentBounds
        editorChromeStrokeLayer.frame = currentBounds
        editorChromeMaskLayer.frame = currentBounds

        guard currentBounds.width > 0, currentBounds.height > 0,
              let chrome = style.editorSurface.chrome else {
            editorChromeFillLayer.path = nil
            editorChromeStrokeLayer.path = nil
            editorChromeMaskLayer.path = nil
            return
        }

        let strokeInset = chrome.strokeColor == nil ? 0 : chrome.borderWidth / 2
        let chromePath = CGPath.blockInputEditorChromePath(
            in: currentBounds.insetBy(dx: strokeInset, dy: strokeInset),
            radius: chrome.cornerRadius,
            roundedCorners: chrome.roundedCorners
        )
        editorChromeFillLayer.path = chromePath
        editorChromeStrokeLayer.path = chromePath
        editorChromeMaskLayer.path = CGPath.blockInputEditorChromePath(
            in: currentBounds,
            radius: chrome.cornerRadius,
            roundedCorners: chrome.roundedCorners
        )
    }

    private func installEditorChromeLayersIfNeeded() {
        guard let layer else {
            return
        }
        if editorChromeFillLayer.superlayer == nil {
            layer.insertSublayer(editorChromeFillLayer, at: 0)
        }
        if editorChromeStrokeLayer.superlayer == nil {
            layer.insertSublayer(editorChromeStrokeLayer, above: editorChromeFillLayer)
        }
    }

    private func removeEditorChromeLayers() {
        editorChromeFillLayer.removeFromSuperlayer()
        editorChromeStrokeLayer.removeFromSuperlayer()
        if layer?.mask === editorChromeMaskLayer {
            layer?.mask = nil
        }
        editorChromeFillLayer.path = nil
        editorChromeStrokeLayer.path = nil
        editorChromeMaskLayer.path = nil
    }
}

private extension BlockInputEditorChromeCorners {
    var caCornerMask: CACornerMask {
        var mask: CACornerMask = []
        if contains(.topLeft) {
            mask.insert(.layerMinXMinYCorner)
        }
        if contains(.topRight) {
            mask.insert(.layerMaxXMinYCorner)
        }
        if contains(.bottomLeft) {
            mask.insert(.layerMinXMaxYCorner)
        }
        if contains(.bottomRight) {
            mask.insert(.layerMaxXMaxYCorner)
        }
        return mask
    }
}

final class BlockInputEditorChromeView: NSView {
    private var chrome: BlockInputEditorChromeStyle?
    private var fallbackFillColor: NSColor?

    override var isOpaque: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    func configure(chrome: BlockInputEditorChromeStyle?, fallbackFillColor: NSColor?) {
        self.chrome = chrome
        self.fallbackFillColor = fallbackFillColor
        isHidden = chrome == nil
        needsDisplay = true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard bounds.width > 0, bounds.height > 0,
              let chrome else {
            return
        }

        effectiveAppearance.performAsCurrentDrawingAppearance {
            if let fillColor = chrome.fillColor ?? fallbackFillColor {
                fillColor.setFill()
                NSBezierPath.blockInputEditorChromePath(
                    in: bounds,
                    radius: chrome.cornerRadius,
                    roundedCorners: chrome.roundedCorners
                )
                .fill()
            }

            if let strokeColor = chrome.strokeColor, chrome.borderWidth > 0 {
                strokeColor.setStroke()
                let strokeInset = chrome.borderWidth / 2
                let path = NSBezierPath.blockInputEditorChromePath(
                    in: bounds.insetBy(dx: strokeInset, dy: strokeInset),
                    radius: chrome.cornerRadius,
                    roundedCorners: chrome.roundedCorners
                )
                path.lineWidth = chrome.borderWidth
                path.stroke()
            }
        }
    }
}

private extension NSBezierPath {
    static func blockInputEditorChromePath(
        in rect: NSRect,
        radius: CGFloat,
        roundedCorners: BlockInputEditorChromeCorners
    ) -> NSBezierPath {
        let radius = min(max(0, radius), min(rect.width, rect.height) / 2)
        let path = NSBezierPath()
        guard rect.width > 0, rect.height > 0 else {
            return path
        }

        let topLeft = roundedCorners.contains(.topLeft) ? radius : 0
        let topRight = roundedCorners.contains(.topRight) ? radius : 0
        let bottomRight = roundedCorners.contains(.bottomRight) ? radius : 0
        let bottomLeft = roundedCorners.contains(.bottomLeft) ? radius : 0
        let curveFactor: CGFloat = 0.45

        path.move(to: NSPoint(x: rect.minX + bottomLeft, y: rect.minY))
        path.line(to: NSPoint(x: rect.maxX - bottomRight, y: rect.minY))
        if bottomRight > 0 {
            path.curve(
                to: NSPoint(x: rect.maxX, y: rect.minY + bottomRight),
                controlPoint1: NSPoint(x: rect.maxX - bottomRight * curveFactor, y: rect.minY),
                controlPoint2: NSPoint(x: rect.maxX, y: rect.minY + bottomRight * curveFactor)
            )
        }

        path.line(to: NSPoint(x: rect.maxX, y: rect.maxY - topRight))
        if topRight > 0 {
            path.curve(
                to: NSPoint(x: rect.maxX - topRight, y: rect.maxY),
                controlPoint1: NSPoint(x: rect.maxX, y: rect.maxY - topRight * curveFactor),
                controlPoint2: NSPoint(x: rect.maxX - topRight * curveFactor, y: rect.maxY)
            )
        }

        path.line(to: NSPoint(x: rect.minX + topLeft, y: rect.maxY))
        if topLeft > 0 {
            path.curve(
                to: NSPoint(x: rect.minX, y: rect.maxY - topLeft),
                controlPoint1: NSPoint(x: rect.minX + topLeft * curveFactor, y: rect.maxY),
                controlPoint2: NSPoint(x: rect.minX, y: rect.maxY - topLeft * curveFactor)
            )
        }

        path.line(to: NSPoint(x: rect.minX, y: rect.minY + bottomLeft))
        if bottomLeft > 0 {
            path.curve(
                to: NSPoint(x: rect.minX + bottomLeft, y: rect.minY),
                controlPoint1: NSPoint(x: rect.minX, y: rect.minY + bottomLeft * curveFactor),
                controlPoint2: NSPoint(x: rect.minX + bottomLeft * curveFactor, y: rect.minY)
            )
        }
        path.close()
        return path
    }
}

private extension CGPath {
    static func blockInputEditorChromePath(
        in rect: CGRect,
        radius: CGFloat,
        roundedCorners: BlockInputEditorChromeCorners
    ) -> CGPath {
        let radius = min(max(0, radius), min(rect.width, rect.height) / 2)
        let path = CGMutablePath()
        guard rect.width > 0, rect.height > 0 else {
            return path
        }

        // `CAShapeLayer.render(in:)` maps the path's maxY edge to the visual
        // top in AppKit-backed layers, so translate visual corner options to
        // the path-space edge they actually draw on.
        let topLeft = roundedCorners.contains(.bottomLeft) ? radius : 0
        let topRight = roundedCorners.contains(.bottomRight) ? radius : 0
        let bottomRight = roundedCorners.contains(.topRight) ? radius : 0
        let bottomLeft = roundedCorners.contains(.topLeft) ? radius : 0
        let curveFactor: CGFloat = 0.45

        path.move(to: CGPoint(x: rect.minX + topLeft, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - topRight, y: rect.minY))
        if topRight > 0 {
            path.addCurve(
                to: CGPoint(x: rect.maxX, y: rect.minY + topRight),
                control1: CGPoint(x: rect.maxX - topRight * curveFactor, y: rect.minY),
                control2: CGPoint(x: rect.maxX, y: rect.minY + topRight * curveFactor)
            )
        }

        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bottomRight))
        if bottomRight > 0 {
            path.addCurve(
                to: CGPoint(x: rect.maxX - bottomRight, y: rect.maxY),
                control1: CGPoint(x: rect.maxX, y: rect.maxY - bottomRight * curveFactor),
                control2: CGPoint(x: rect.maxX - bottomRight * curveFactor, y: rect.maxY)
            )
        }

        path.addLine(to: CGPoint(x: rect.minX + bottomLeft, y: rect.maxY))
        if bottomLeft > 0 {
            path.addCurve(
                to: CGPoint(x: rect.minX, y: rect.maxY - bottomLeft),
                control1: CGPoint(x: rect.minX + bottomLeft * curveFactor, y: rect.maxY),
                control2: CGPoint(x: rect.minX, y: rect.maxY - bottomLeft * curveFactor)
            )
        }

        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + topLeft))
        if topLeft > 0 {
            path.addCurve(
                to: CGPoint(x: rect.minX + topLeft, y: rect.minY),
                control1: CGPoint(x: rect.minX, y: rect.minY + topLeft * curveFactor),
                control2: CGPoint(x: rect.minX + topLeft * curveFactor, y: rect.minY)
            )
        }
        path.closeSubpath()
        return path
    }
}
