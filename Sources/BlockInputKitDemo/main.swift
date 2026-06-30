import AppKit
import BlockInputKitDemoKit

let app = NSApplication.shared
if CommandLine.arguments.contains("--benchmark-100k-mutations") {
    let iterationIndex = CommandLine.arguments.firstIndex(of: "--benchmark-100k-mutations").map {
        CommandLine.arguments.index(after: $0)
    }
    let iterations = iterationIndex
        .flatMap { CommandLine.arguments.indices.contains($0) ? Int(CommandLine.arguments[$0]) : nil }
        ?? 100
    app.setActivationPolicy(.prohibited)
    Task { @MainActor in
        DemoMutationBenchmark.run(iterations: iterations)
        app.terminate(nil)
    }
} else {
    // Core-only demo: no plugins. DemoAppDelegate defaults to NullDemoEditorExtension (no-op seam).
    let delegate = DemoAppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.regular)
}
app.run()
