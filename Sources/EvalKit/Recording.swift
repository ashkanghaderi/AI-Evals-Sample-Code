import Foundation

/// One model call, recorded.
///
/// Generation and grading are separate steps, and this is the boundary. A
/// recorded run can be re-graded any number of times, by anyone, without the
/// model - which makes grading fast, free, reproducible, and runnable in CI on
/// machines that have no model at all.
public struct RunRecord<Output: Codable & Sendable>: Codable, Sendable {
    public let caseID: String
    public let repetition: Int
    public let output: Output?
    public let error: String?
    public let latencyMilliseconds: Int
    public let model: String
    public let sampling: String
    public let osVersion: String
    public let recordedAt: Date

    public init(caseID: String, repetition: Int, output: Output?, error: String?,
                latencyMilliseconds: Int, model: String, sampling: String,
                osVersion: String = ProcessInfo.processInfo.operatingSystemVersionString,
                recordedAt: Date = Date()) {
        self.caseID = caseID
        self.repetition = repetition
        self.output = output
        self.error = error
        self.latencyMilliseconds = latencyMilliseconds
        self.model = model
        self.sampling = sampling
        self.osVersion = osVersion
        self.recordedAt = recordedAt
    }
}

/// JSON Lines: one JSON object per line.
///
/// Chosen over a single JSON array because a run is written one line at a
/// time. If a long run is interrupted, everything recorded so far survives,
/// and a diff of two runs is a readable line-by-line diff.
public enum JSONLines {
    public static func read<T: Decodable>(_ type: T.Type, from url: URL) throws -> [T] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try String(contentsOf: url, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { try decoder.decode(T.self, from: Data($0.utf8)) }
    }

    public static func append<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var line = try encoder.encode(value)
        line.append(UInt8(ascii: "\n"))
        if !FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: line)
    }
}
