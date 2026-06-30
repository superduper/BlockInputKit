import AppKit

/// Row-height and chrome-alignment metrics for each rendered block family.
struct BlockInputBlockItemVerticalMetrics {
    var textContainerInset: NSSize
    var topContentInset: CGFloat
    var bottomContentInset: CGFloat
    var minimumHeight: CGFloat

    static let standard = BlockInputBlockItemVerticalMetrics(
        textContainerInset: NSSize(width: 4, height: 6),
        topContentInset: 6,
        bottomContentInset: 6,
        minimumHeight: 34
    )

    static let textBlock = BlockInputBlockItemVerticalMetrics(
        textContainerInset: NSSize(width: 4, height: 3),
        topContentInset: 3,
        bottomContentInset: 3,
        minimumHeight: 29
    )

    static let quote = BlockInputBlockItemVerticalMetrics(
        textContainerInset: NSSize(width: 4, height: 10),
        topContentInset: 10,
        bottomContentInset: 6,
        minimumHeight: 40
    )

    static let textList = BlockInputBlockItemVerticalMetrics(
        textContainerInset: NSSize(width: 4, height: 4),
        topContentInset: 4,
        bottomContentInset: 0,
        minimumHeight: 24
    )

    static let checklist = BlockInputBlockItemVerticalMetrics(
        textContainerInset: NSSize(width: 4, height: 4),
        topContentInset: 4,
        bottomContentInset: 2,
        minimumHeight: 28
    )

    func scaled(by multiplier: CGFloat) -> BlockInputBlockItemVerticalMetrics {
        let multiplier = BlockInputConfiguration.sanitizedBlockVerticalInsetMultiplier(multiplier)
        return BlockInputBlockItemVerticalMetrics(
            textContainerInset: NSSize(width: textContainerInset.width, height: textContainerInset.height * multiplier),
            topContentInset: topContentInset * multiplier,
            bottomContentInset: bottomContentInset * multiplier,
            minimumHeight: minimumHeight * multiplier
        )
    }

    func chromeTopConstant(font: NSFont, chromeHeight: CGFloat) -> CGFloat {
        topContentInset + (font.blockInputLineHeight - chromeHeight) / 2
    }

    func checklistButtonTopConstant(font: NSFont, checkboxHeight: CGFloat) -> CGFloat {
        topContentInset + (font.blockInputLineHeight - checkboxHeight) / 2
    }
}

extension BlockInputBlockItem {
    static let dragHandleHeight: CGFloat = 14
    static let checklistButtonHeight: CGFloat = 18
    static let standardTextContainerInset = NSSize(width: 4, height: 6)
    static let textBlockTextContainerInset = NSSize(width: 4, height: 3)
    static let textListTextContainerInset = NSSize(width: 4, height: 4)
    static let checklistTextContainerInset = NSSize(width: 4, height: 4)

    static func dragHandleTopConstant(
        for kind: BlockInputBlockKind,
        metrics: BlockInputBlockItemVerticalMetrics,
        style: BlockInputStyle = .default
    ) -> CGFloat {
        metrics.chromeTopConstant(font: font(for: kind, style: style), chromeHeight: dragHandleHeight)
    }

    static func scaledVerticalInset(_ value: CGFloat, blockVerticalInsetMultiplier: CGFloat) -> CGFloat {
        value * BlockInputConfiguration.sanitizedBlockVerticalInsetMultiplier(blockVerticalInsetMultiplier)
    }

    static func scaledFrontMatterDividerVerticalInset(for blockVerticalInsetMultiplier: CGFloat) -> CGFloat {
        scaledVerticalInset(frontMatterDividerVerticalInset, blockVerticalInsetMultiplier: blockVerticalInsetMultiplier)
    }

    static func scaledTableExternalVerticalInset(for blockVerticalInsetMultiplier: CGFloat) -> CGFloat {
        scaledVerticalInset(tableExternalVerticalInset, blockVerticalInsetMultiplier: blockVerticalInsetMultiplier)
    }

    static func scaledImageExternalVerticalInset(for blockVerticalInsetMultiplier: CGFloat) -> CGFloat {
        scaledVerticalInset(imageExternalVerticalInset, blockVerticalInsetMultiplier: blockVerticalInsetMultiplier)
    }
}

private extension NSFont {
    var blockInputLineHeight: CGFloat {
        ceil(ascender - descender + leading)
    }
}
