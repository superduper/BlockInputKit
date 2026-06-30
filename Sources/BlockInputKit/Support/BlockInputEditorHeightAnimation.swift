import AppKit

/// Animation metadata for a preferred editor height transition.
public struct BlockInputEditorHeightAnimation: Equatable, @unchecked Sendable {
    /// Built-in preferred-height animation used when a transition callback is configured.
    public static var `default`: BlockInputEditorHeightAnimation {
        BlockInputEditorHeightAnimation()
    }

    /// Animation duration in seconds. Negative and non-finite values are clamped to zero.
    public var duration: TimeInterval {
        didSet {
            duration = Self.validDuration(duration)
        }
    }
    /// Timing curve hosts should use when applying the reported height transition.
    public var curve: BlockInputEditorHeightAnimationCurve

    /// Creates preferred-height animation metadata.
    public init(
        duration: TimeInterval = 0.22,
        curve: BlockInputEditorHeightAnimationCurve = .easeInOut
    ) {
        self.duration = Self.validDuration(duration)
        self.curve = curve
    }

    private static func validDuration(_ value: TimeInterval) -> TimeInterval {
        value.isFinite ? max(0, value) : 0
    }
}

/// Timing curve options for animated preferred editor height transitions.
public enum BlockInputEditorHeightAnimationCurve: Equatable, Sendable {
    /// Accelerates and decelerates smoothly.
    case easeInOut
    /// Accelerates from the initial height.
    case easeIn
    /// Decelerates into the target height.
    case easeOut
    /// Moves at a constant rate.
    case linear
}

/// Preferred editor height transition reported to hosts that opt into transition callbacks.
public struct BlockInputEditorHeightTransition: Equatable, @unchecked Sendable {
    /// Last reported preferred height. Nil for the first publication.
    public var previousHeight: CGFloat?
    /// New clamped preferred height.
    public var targetHeight: CGFloat
    /// Animation metadata to use. Nil means apply the height immediately.
    public var animation: BlockInputEditorHeightAnimation?
    /// Whether this is the first preferred height publication for the current editor sizing session.
    public var isInitial: Bool

    /// Creates a preferred-height transition payload.
    public init(
        previousHeight: CGFloat?,
        targetHeight: CGFloat,
        animation: BlockInputEditorHeightAnimation?,
        isInitial: Bool
    ) {
        self.previousHeight = previousHeight
        self.targetHeight = targetHeight
        self.animation = animation
        self.isInitial = isInitial
    }
}
