import Foundation

struct BlockInputMarkdownStringLineReader: BlockInputMarkdownLineReader {
    private let lines: [String]
    private var index = 0

    init(markdown: String) {
        lines = BlockInputLineBreaks.lines(in: markdown)
    }

    mutating func readMarkdownLine() async throws -> String? {
        guard index < lines.count else {
            return nil
        }
        defer {
            index += 1
        }
        return lines[index]
    }
}

struct BlockInputMarkdownStringWriter: BlockInputMarkdownWriter {
    private var chunks: [String] = []

    var markdown: String {
        chunks.joined()
    }

    mutating func writeMarkdown(_ chunk: String) async throws {
        chunks.append(chunk)
    }
}

final class BlockInputMarkdownFileLineReader: BlockInputMarkdownLineReader {
    private var fileHandle: FileHandle?
    private let chunkSize = 64 * 1024
    private var currentLineBytes: [UInt8] = []
    private var currentChunk: [UInt8] = []
    private var chunkOffset = 0
    private var skipNextLineFeed = false
    private var lastReadEndedWithLineBreak = false

    init(url: URL) throws {
        fileHandle = try FileHandle(forReadingFrom: url)
    }

    func readMarkdownLine() async throws -> String? {
        guard let fileHandle else {
            return nil
        }
        while true {
            if chunkOffset < currentChunk.count {
                if let line = try process(currentChunk[chunkOffset]) {
                    chunkOffset += 1
                    return line
                }
                chunkOffset += 1
                continue
            }
            guard let data = try fileHandle.read(upToCount: chunkSize),
                  !data.isEmpty else {
                if lastReadEndedWithLineBreak {
                    lastReadEndedWithLineBreak = false
                    return ""
                }
                guard !currentLineBytes.isEmpty else {
                    return nil
                }
                return try finishLine()
            }
            currentChunk = Array(data)
            chunkOffset = 0
        }
    }

    func close() throws {
        guard let fileHandle else {
            return
        }
        self.fileHandle = nil
        try fileHandle.close()
    }

    private func process(_ byte: UInt8) throws -> String? {
        if skipNextLineFeed {
            skipNextLineFeed = false
            if byte == Self.lineFeed {
                return nil
            }
        }
        if byte == Self.carriageReturn {
            skipNextLineFeed = true
            lastReadEndedWithLineBreak = true
            return try finishLine()
        }
        if byte == Self.lineFeed {
            lastReadEndedWithLineBreak = true
            return try finishLine()
        }
        lastReadEndedWithLineBreak = false
        currentLineBytes.append(byte)
        return nil
    }

    private func finishLine() throws -> String {
        let data = Data(currentLineBytes)
        currentLineBytes.removeAll(keepingCapacity: true)
        guard let line = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return line
    }

    private static let lineFeed: UInt8 = 0x0A
    private static let carriageReturn: UInt8 = 0x0D
}

final class BlockInputMarkdownFileWriter: BlockInputMarkdownWriter {
    private var fileHandle: FileHandle?
    private var buffer = Data()
    private let bufferLimit = 64 * 1024

    init(url: URL) throws {
        if !FileManager.default.fileExists(atPath: url.path) {
            guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
                throw CocoaError(.fileWriteUnknown)
            }
        }
        let fileHandle = try FileHandle(forWritingTo: url)
        do {
            try fileHandle.truncate(atOffset: 0)
        } catch {
            try? fileHandle.close()
            throw error
        }
        self.fileHandle = fileHandle
    }

    func writeMarkdown(_ chunk: String) async throws {
        guard let fileHandle else {
            throw CocoaError(.fileWriteUnknown)
        }
        let bytes = chunk.utf8
        if bytes.count >= bufferLimit {
            try flush(to: fileHandle)
            try writeLargeChunk(bytes, to: fileHandle)
            return
        }
        buffer.append(contentsOf: bytes)
        if buffer.count >= bufferLimit {
            try flush(to: fileHandle)
        }
    }

    func close() throws {
        try close(flushingBuffer: true)
    }

    func closeAfterFailure() throws {
        try close(flushingBuffer: false)
    }

    private func close(flushingBuffer: Bool) throws {
        guard let fileHandle else {
            return
        }
        var closeError: Error?
        if flushingBuffer {
            do {
                try flush(to: fileHandle)
            } catch {
                closeError = error
            }
        } else {
            buffer.removeAll(keepingCapacity: false)
        }
        self.fileHandle = nil
        do {
            try fileHandle.close()
        } catch {
            closeError = closeError ?? error
        }
        if let closeError {
            throw closeError
        }
    }

    private func flush(to fileHandle: FileHandle) throws {
        guard !buffer.isEmpty else {
            return
        }
        try fileHandle.write(contentsOf: buffer)
        buffer.removeAll(keepingCapacity: true)
    }

    private func writeLargeChunk(_ bytes: String.UTF8View, to fileHandle: FileHandle) throws {
        var startIndex = bytes.startIndex
        while startIndex < bytes.endIndex {
            let endIndex = bytes.index(
                startIndex,
                offsetBy: bufferLimit,
                limitedBy: bytes.endIndex
            ) ?? bytes.endIndex
            try fileHandle.write(contentsOf: Data(bytes[startIndex..<endIndex]))
            startIndex = endIndex
        }
    }
}
