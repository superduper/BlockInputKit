import AppKit
@testable import BlockInputKit

final class BlockInputDraggingInfo: NSObject, NSDraggingInfo {
    private let pasteboard: NSPasteboard
    private let location: NSPoint

    init(
        blockID: BlockInputBlockID? = nil,
        fileURLs: [URL] = [],
        pasteboardTypes: [NSPasteboard.PasteboardType] = [],
        location: NSPoint = .zero
    ) {
        pasteboard = NSPasteboard(name: NSPasteboard.Name("BlockInputKitTests.\(UUID().uuidString)"))
        self.location = location
        pasteboard.clearContents()
        if let blockID {
            pasteboard.setString(blockID.rawValue, forType: .blockInputBlockID)
        }
        if !fileURLs.isEmpty {
            pasteboard.writeObjects(fileURLs as [NSURL])
        }
        for type in pasteboardTypes {
            pasteboard.setData(Data(), forType: type)
        }
    }

    var draggingDestinationWindow: NSWindow? { nil }
    var draggingSourceOperationMask: NSDragOperation { .move }
    var draggingLocation: NSPoint { location }
    var draggedImageLocation: NSPoint { .zero }
    var draggedImage: NSImage? { nil }
    var draggingPasteboard: NSPasteboard { pasteboard }
    var draggingSource: Any? { nil }
    var draggingSequenceNumber: Int { 0 }
    var draggingFormation: NSDraggingFormation = .none
    var animatesToDestination = false
    var numberOfValidItemsForDrop = 1
    var springLoadingHighlight: NSSpringLoadingHighlight { .none }

    func slideDraggedImage(to screenPoint: NSPoint) {}

    override func namesOfPromisedFilesDropped(atDestination dropDestination: URL) -> [String]? {
        nil
    }

    func enumerateDraggingItems(
        options enumOpts: NSDraggingItemEnumerationOptions = [],
        for view: NSView?,
        classes classArray: [AnyClass],
        searchOptions: [NSPasteboard.ReadingOptionKey: Any] = [:],
        using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void
    ) {}

    func resetSpringLoading() {}
}
