import BlockInputKit
import Foundation

/// Deterministic scripted `BlockInputInteractiveBlockContent.AIBackend` for the demo app (no LLM — purely rule-based).
///
/// Behavior:
/// - "left to right" / "lr" in the instruction → swaps the first-line direction token to `LR`.
/// - "top down" / "top to bottom" / "td" / "tb" → swaps to `TD`.
/// - "Fix the syntax error: <full mermaid error>" → returns a canned repair candidate (the plugin renders
///   and validates it in-page, re-asking on failure).
/// - Otherwise → echoes the source unchanged with a message explaining it can't interpret the instruction.
public struct DemoMockDiagramAIProvider {
    /// Artificial think-time before each step so the chat loader/progress is visible (a real agent has latency).
    /// Defaults to 0 so unit tests run fast; the demo sets ~1.2s.
    private let stepDelay: Duration

    public init(stepDelay: Duration = .zero) {
        self.stepDelay = stepDelay
    }

    /// Deterministic repair candidates for common breakages, ordered most- to least-likely.
    func cannedFixCandidates(for source: String) -> [String] {
        var candidates: [String] = []
        let lines = source.components(separatedBy: "\n")

        // Repair 1: complete a dangling edge ("A -->" with no target) by appending a target node.
        var danglingFixed = lines
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasSuffix("-->") || trimmed.hasSuffix("--") {
                danglingFixed[index] = line + " B"
            }
        }
        if danglingFixed != lines {
            candidates.append(danglingFixed.joined(separator: "\n"))
        }

        // Repair 2: last resort — a minimal valid diagram so the demo always recovers to *something*.
        candidates.append("graph TD\n    A[Fixed] --> B[Diagram]")
        return candidates
    }

    // MARK: - Private helpers

    /// Replaces the direction token on the first non-empty line that starts with `graph` or `flowchart`.
    ///
    /// Handles patterns like `graph TD`, `graph LR`, `flowchart TD`, `flowchart TB`, etc.
    func applyDirection(_ direction: String, to source: String) -> String {
        var lines = source.components(separatedBy: "\n")
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces).lowercased()
            if trimmed.hasPrefix("graph ") || trimmed.hasPrefix("flowchart ") {
                // Replace the direction token (last whitespace-separated word on the first keyword line).
                let words = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                if words.count >= 2 {
                    // Reconstruct: keep prefix spacing + keyword + new direction.
                    let leadingSpaces = line.prefix(while: { $0 == " " || $0 == "\t" })
                    lines[index] = "\(leadingSpaces)\(words[0]) \(direction)"
                }
                break
            }
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - BlockInputInteractiveBlockContent.AIBackend conformance

extension DemoMockDiagramAIProvider: BlockInputInteractiveBlockContent.AIBackend {
    // Backend variant: no host validate — the plugin renders/validates the result in-page. Returns the best
    // candidate (direction change or canned fix), letting the plugin's in-page render confirm or reject it.
    public func rewrite(
        source: String,
        instruction: String,
        contentIdentifier: String,
        onEvent: @Sendable @MainActor (BlockInputInteractiveBlockContent.AIEvent) -> Void
    ) async -> Result<String, Error> {
        let lower = instruction.lowercased()
        await MainActor.run { onEvent(.status("Thinking…")) }
        if stepDelay != .zero { try? await Task.sleep(for: stepDelay) }
        if lower.hasPrefix("fix the syntax error") {
            await MainActor.run { onEvent(.assistantMessage("Looks broken. Trying a fix…")) }
            // Return the first canned candidate; the plugin renders it and re-asks on failure.
            let candidate = cannedFixCandidates(for: source).first ?? source
            await MainActor.run { onEvent(.candidate(candidate)) }
            return .success(candidate)
        }
        let candidate: String
        let intentMessage: String
        if lower.contains("left to right") || lower.contains(" lr") || lower.hasPrefix("lr") {
            candidate = applyDirection("LR", to: source)
            intentMessage = "Switching diagram direction to left-to-right (LR)."
        } else if lower.contains("top down") || lower.contains("top to bottom")
                    || lower.contains(" td") || lower.hasPrefix("td")
                    || lower.contains(" tb") || lower.hasPrefix("tb") {
            candidate = applyDirection("TD", to: source)
            intentMessage = "Switching diagram direction to top-down (TD)."
        } else {
            candidate = source
            intentMessage = "No direction change recognised in '\(instruction)'. Returning source unchanged."
        }
        await MainActor.run { onEvent(.assistantMessage(intentMessage)) }
        return .success(candidate)
    }

    public func converse(
        contentIdentifier: String,
        blockID: BlockInputBlockID,
        source: String,
        messages: [BlockInputInteractiveBlockContent.AIMessage],
        onEvent: @Sendable @MainActor (BlockInputInteractiveBlockContent.AIEvent) -> Void
    ) async -> Result<BlockInputInteractiveBlockContent.AITurn, Error> {
        await MainActor.run { onEvent(.status("Thinking…")) }
        if stepDelay != .zero { try? await Task.sleep(for: stepDelay) }
        let prompt = messages.last(where: { $0.role == .user })?.text.lowercased() ?? ""
        // Emit syntax matching the block's engine: PlantUML blocks must get @startuml…@enduml, not Mermaid.
        let isPlantUML = contentIdentifier == "code.plantuml" || contentIdentifier == "code.puml"

        // The FSM re-asks failed candidates with "fix the syntax error: …" — reuse canned fixes.
        if prompt.contains("fix the syntax error") {
            let candidate = cannedFixCandidates(for: source).first ?? source
            return .success(.candidate(candidate))
        }
        // Refinement on an existing diagram (Mermaid graph direction; PlantUML has no equivalent token here).
        if !isPlantUML, !source.isEmpty, prompt.contains("left to right") || prompt.contains(" lr") {
            return .success(.candidate(applyDirection("LR", to: source)))
        }
        if !isPlantUML, !source.isEmpty, prompt.contains("top down") || prompt.contains(" td") || prompt.contains(" tb") {
            return .success(.candidate(applyDirection("TD", to: source)))
        }
        // A designated "broken" prompt exercises the real render-retry loop.
        if prompt.contains("broken demo") {
            await MainActor.run { onEvent(.assistantMessage("Here's a draft (intentionally broken).")) }
            let broken = isPlantUML ? "@startuml\nAlice ->" : "graph TD\nA -->"  // dangling → render fails → re-ask
            return .success(.candidate(broken))
        }
        // Specific create prompts → canned diagrams (engine-appropriate syntax).
        if prompt.contains("sequence") {
            return .success(.candidate(isPlantUML
                ? "@startuml\nAlice -> Bob: Hello\nBob --> Alice: Hi\n@enduml"
                : "sequenceDiagram\n  Alice->>Bob: Hello\n  Bob-->>Alice: Hi"))
        }
        if prompt.contains("flowchart") || prompt.contains("flow") {
            return .success(.candidate(isPlantUML
                ? "@startuml\nstart\nif (Decision?) then (yes)\n  :Do;\nelse (no)\n  :Skip;\nendif\nstop\n@enduml"
                : "graph TD\n  Start --> Decision\n  Decision -->|yes| Do\n  Decision -->|no| Skip"))
        }
        // Vague prompt → clarifying question.
        if prompt.split(separator: " ").count < 3 || prompt.contains("make a diagram") {
            return .success(.question("What kind — flowchart, sequence, or state? And what is it about?"))
        }
        // Fallback best-guess (engine-appropriate).
        let label = messages.last?.text ?? "Idea"
        return .success(.candidate(isPlantUML
            ? "@startuml\n[\(label)] --> [Detail]\n@enduml"
            : "graph TD\n  A[\(label)] --> B[Detail]"))
    }
}
