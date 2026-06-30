import AppKit
import BlockInputKit
import Foundation

@MainActor
public enum DemoMutationBenchmark {
    public static func run(iterations: Int = 100) {
        let context = makeContext()

        let paragraphStats = measureMutations(
            name: "paragraph",
            blockID: BlockInputBlockID(rawValue: "large-0"),
            offset: "Paragraph block 0".utf16.count,
            iterations: iterations,
            view: context.view
        )
        let listStats = measureMutations(
            name: "list",
            blockID: BlockInputBlockID(rawValue: "large-3"),
            offset: "Bullet block 3".utf16.count,
            iterations: iterations,
            view: context.view
        )
        let quoteStats = measureQuoteTermination(
            blockID: BlockInputBlockID(rawValue: "large-2"),
            iterations: iterations,
            store: context.store,
            view: context.view
        )
        let quoteLineExitStats = measureQuoteLineExit(
            blockID: BlockInputBlockID(rawValue: "large-2"),
            iterations: iterations,
            store: context.store,
            view: context.view
        )
        let reorderStats = measureOrderedReorder(iterations: iterations)
        print(paragraphStats.reportLine)
        print(listStats.reportLine)
        print(quoteStats.reportLine)
        print(quoteLineExitStats.reportLine)
        print(reorderStats.reportLine)
        print("demo_100k_mutation_benchmark publishes=\(context.publishCount.value) loadedBlockCount=\(context.store.loadedBlockCount)")
    }

    private static func makeContext() -> BenchmarkContext {
        let store = BlockInputMemoryDocumentStore(document: DemoData.largeDocument())
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 480),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let view = BlockInputView(frame: window.contentView?.bounds ?? window.frame)
        window.contentView = view
        let publishCount = PublishCount()
        view.configure(BlockInputConfiguration(
            documentStore: store,
            undoController: BlockInputUndoController(),
            onDocumentMutation: { _ in
                publishCount.value += 1
                _ = store.loadedBlockCount
            }
        ))
        view.layoutSubtreeIfNeeded()
        return BenchmarkContext(store: store, view: view, publishCount: publishCount)
    }

    private static func measureMutations(
        name: String,
        blockID: BlockInputBlockID,
        offset: Int,
        iterations: Int,
        view: BlockInputView
    ) -> MutationStats {
        view.focus(blockID: blockID, utf16Offset: offset)
        var createDurations: [Double] = []
        var undoDurations: [Double] = []
        var redoDurations: [Double] = []
        var deleteDurations: [Double] = []
        for _ in 0..<iterations {
            let createStart = CFAbsoluteTimeGetCurrent()
            guard let createSelection = view.insertBlockBelowCurrentBlock() else {
                assertionFailure("Benchmark failed to create block for \(name)")
                break
            }
            createDurations.append((CFAbsoluteTimeGetCurrent() - createStart) * 1_000)

            let undoStart = CFAbsoluteTimeGetCurrent()
            guard view.undoStructuralEdit() != nil else {
                print("demo_100k_mutation_benchmark_undo_failed name=\(name) createSelection=\(createSelection)")
                break
            }
            undoDurations.append((CFAbsoluteTimeGetCurrent() - undoStart) * 1_000)

            let redoStart = CFAbsoluteTimeGetCurrent()
            guard view.redoStructuralEdit() != nil else {
                print("demo_100k_mutation_benchmark_redo_failed name=\(name) createSelection=\(createSelection)")
                break
            }
            redoDurations.append((CFAbsoluteTimeGetCurrent() - redoStart) * 1_000)

            let deleteStart = CFAbsoluteTimeGetCurrent()
            guard view.deleteCurrentEmptyBlockForBackspaceOrDelete() != nil else {
                print(
                    "demo_100k_mutation_benchmark_delete_failed " +
                        "name=\(name) createSelection=\(createSelection) currentSelection=\(String(describing: view.selection))"
                )
                break
            }
            deleteDurations.append((CFAbsoluteTimeGetCurrent() - deleteStart) * 1_000)
        }
        return MutationStats(name: name, creates: createDurations, undos: undoDurations, redos: redoDurations, deletes: deleteDurations)
    }

    private static func measureQuoteTermination(
        blockID: BlockInputBlockID,
        iterations: Int,
        store: BlockInputMemoryDocumentStore,
        view: BlockInputView
    ) -> ReplacementStats {
        store.replaceBlock(BlockInputBlock(id: blockID, kind: .quote))
        view.focus(blockID: blockID, utf16Offset: 0)
        var replaceDurations: [Double] = []
        var undoDurations: [Double] = []
        var redoDurations: [Double] = []
        for _ in 0..<iterations {
            let replaceStart = CFAbsoluteTimeGetCurrent()
            guard view.insertBlockBelowCurrentBlock() != nil else {
                print("demo_100k_mutation_benchmark_quote_terminate_failed")
                break
            }
            replaceDurations.append((CFAbsoluteTimeGetCurrent() - replaceStart) * 1_000)

            let undoStart = CFAbsoluteTimeGetCurrent()
            guard view.undoStructuralEdit() != nil else {
                print("demo_100k_mutation_benchmark_quote_undo_failed")
                break
            }
            undoDurations.append((CFAbsoluteTimeGetCurrent() - undoStart) * 1_000)

            let redoStart = CFAbsoluteTimeGetCurrent()
            guard view.redoStructuralEdit() != nil else {
                print("demo_100k_mutation_benchmark_quote_redo_failed")
                break
            }
            redoDurations.append((CFAbsoluteTimeGetCurrent() - redoStart) * 1_000)
            _ = view.undoStructuralEdit()
        }
        return ReplacementStats(name: "quote_termination", replacements: replaceDurations, undos: undoDurations, redos: redoDurations)
    }

    private static func measureQuoteLineExit(
        blockID: BlockInputBlockID,
        iterations: Int,
        store: BlockInputMemoryDocumentStore,
        view: BlockInputView
    ) -> ReplacementStats {
        let text = "Line 1\nLine 2\n"
        store.replaceBlock(BlockInputBlock(id: blockID, kind: .quote, text: text))
        view.focus(blockID: blockID, utf16Offset: (text as NSString).length)
        var replaceDurations: [Double] = []
        var undoDurations: [Double] = []
        var redoDurations: [Double] = []
        for _ in 0..<iterations {
            let replaceStart = CFAbsoluteTimeGetCurrent()
            guard view.insertBlockBelowCurrentBlock() != nil else {
                print("demo_100k_mutation_benchmark_quote_line_exit_failed")
                break
            }
            replaceDurations.append((CFAbsoluteTimeGetCurrent() - replaceStart) * 1_000)

            let undoStart = CFAbsoluteTimeGetCurrent()
            guard view.undoStructuralEdit() != nil else {
                print("demo_100k_mutation_benchmark_quote_line_undo_failed")
                break
            }
            undoDurations.append((CFAbsoluteTimeGetCurrent() - undoStart) * 1_000)

            let redoStart = CFAbsoluteTimeGetCurrent()
            guard view.redoStructuralEdit() != nil else {
                print("demo_100k_mutation_benchmark_quote_line_redo_failed")
                break
            }
            redoDurations.append((CFAbsoluteTimeGetCurrent() - redoStart) * 1_000)
            _ = view.undoStructuralEdit()
        }
        return ReplacementStats(name: "quote_line_exit", replacements: replaceDurations, undos: undoDurations, redos: redoDurations)
    }

    private static func measureOrderedReorder(iterations: Int) -> MoveStats {
        let sourceIndex = 50_000
        let sourceID = BlockInputBlockID(rawValue: "ordered-\(sourceIndex)")
        let store = BlockInputMemoryDocumentStore(document: BlockInputDocument(blocks: (0..<100_000).map { index in
            BlockInputBlock(
                id: BlockInputBlockID(rawValue: "ordered-\(index)"),
                kind: .numberedListItem(start: index + 1),
                text: "Ordered block \(index)"
            )
        }))
        let view = BlockInputView(frame: NSRect(x: 0, y: 0, width: 720, height: 480))
        view.configure(BlockInputConfiguration(
            documentStore: store,
            undoController: BlockInputUndoController()
        ))
        view.layoutSubtreeIfNeeded()
        var moveDurations: [Double] = []
        var undoDurations: [Double] = []
        var redoDurations: [Double] = []
        for _ in 0..<iterations {
            let moveStart = CFAbsoluteTimeGetCurrent()
            guard view.moveBlock(blockID: sourceID, to: sourceIndex + 1) != nil else {
                print("demo_100k_mutation_benchmark_ordered_reorder_failed")
                break
            }
            moveDurations.append((CFAbsoluteTimeGetCurrent() - moveStart) * 1_000)

            let undoStart = CFAbsoluteTimeGetCurrent()
            guard view.undoStructuralEdit() != nil else {
                print("demo_100k_mutation_benchmark_ordered_reorder_undo_failed")
                break
            }
            undoDurations.append((CFAbsoluteTimeGetCurrent() - undoStart) * 1_000)

            let redoStart = CFAbsoluteTimeGetCurrent()
            guard view.redoStructuralEdit() != nil else {
                print("demo_100k_mutation_benchmark_ordered_reorder_redo_failed")
                break
            }
            redoDurations.append((CFAbsoluteTimeGetCurrent() - redoStart) * 1_000)
            _ = view.undoStructuralEdit()
        }
        return MoveStats(name: "ordered_reorder", moves: moveDurations, undos: undoDurations, redos: redoDurations)
    }
}

private struct MutationStats {
    var name: String
    var creates: [Double]
    var undos: [Double]
    var redos: [Double]
    var deletes: [Double]

    var reportLine: String {
        "demo_100k_mutation_benchmark \(name) " +
            "create_avg_ms=\(Self.average(creates).roundedString) " +
            "create_p95_ms=\(Self.percentile(creates, 0.95).roundedString) " +
            "undo_avg_ms=\(Self.average(undos).roundedString) " +
            "undo_p95_ms=\(Self.percentile(undos, 0.95).roundedString) " +
            "redo_avg_ms=\(Self.average(redos).roundedString) " +
            "redo_p95_ms=\(Self.percentile(redos, 0.95).roundedString) " +
            "delete_avg_ms=\(Self.average(deletes).roundedString) " +
            "delete_p95_ms=\(Self.percentile(deletes, 0.95).roundedString) " +
            "iterations=\([creates.count, undos.count, redos.count, deletes.count].min() ?? 0)"
    }

    fileprivate static func average(_ values: [Double]) -> Double {
        guard !values.isEmpty else {
            return 0
        }
        return values.reduce(0, +) / Double(values.count)
    }

    fileprivate static func percentile(_ values: [Double], _ percentile: Double) -> Double {
        guard !values.isEmpty else {
            return 0
        }
        let sortedValues = values.sorted()
        let index = min(
            sortedValues.count - 1,
            max(0, Int((Double(sortedValues.count - 1) * percentile).rounded()))
        )
        return sortedValues[index]
    }
}

private struct ReplacementStats {
    var name: String
    var replacements: [Double]
    var undos: [Double]
    var redos: [Double]

    var reportLine: String {
        "demo_100k_mutation_benchmark \(name) " +
            "replace_avg_ms=\(MutationStats.average(replacements).roundedString) " +
            "replace_p95_ms=\(MutationStats.percentile(replacements, 0.95).roundedString) " +
            "undo_avg_ms=\(MutationStats.average(undos).roundedString) " +
            "undo_p95_ms=\(MutationStats.percentile(undos, 0.95).roundedString) " +
            "redo_avg_ms=\(MutationStats.average(redos).roundedString) " +
            "redo_p95_ms=\(MutationStats.percentile(redos, 0.95).roundedString) " +
            "iterations=\([replacements.count, undos.count, redos.count].min() ?? 0)"
    }
}

private struct MoveStats {
    var name: String
    var moves: [Double]
    var undos: [Double]
    var redos: [Double]

    var reportLine: String {
        "demo_100k_mutation_benchmark \(name) " +
            "move_avg_ms=\(MutationStats.average(moves).roundedString) " +
            "move_p95_ms=\(MutationStats.percentile(moves, 0.95).roundedString) " +
            "undo_avg_ms=\(MutationStats.average(undos).roundedString) " +
            "undo_p95_ms=\(MutationStats.percentile(undos, 0.95).roundedString) " +
            "redo_avg_ms=\(MutationStats.average(redos).roundedString) " +
            "redo_p95_ms=\(MutationStats.percentile(redos, 0.95).roundedString) " +
            "iterations=\([moves.count, undos.count, redos.count].min() ?? 0)"
    }
}

private struct BenchmarkContext {
    var store: BlockInputMemoryDocumentStore
    var view: BlockInputView
    var publishCount: PublishCount
}

private final class PublishCount {
    var value = 0
}

private extension Double {
    var roundedString: String {
        String(format: "%.3f", self)
    }
}
