import Foundation

/// The learner's sentences, recorded for evals - only with consent, and only
/// after redaction.
///
/// The output is redacted too. The model echoes the learner: "Me llamo Carlos"
/// comes back corrected as "Me llamo Carlos", and a log that redacts the input
/// and stores the correction verbatim has recorded the name anyway.
public struct InteractionLog: Sendable {
    public struct Entry: Codable, Sendable, Equatable {
        public let input: String
        public let corrected: String
        public let hasError: Bool
        public let explanation: String
        /// A day, not a timestamp. The exact second a sentence was typed is
        /// itself identifying, and evals never need it.
        public let day: String
        public let appVersion: String
        public let osVersion: String
    }

    public let url: URL
    public let redactor: Redactor

    public init(url: URL, redactor: Redactor = Redactor()) {
        self.url = url
        self.redactor = redactor
    }

    /// Records one interaction if, and only if, the learner has opted in.
    /// Returns whether anything was written.
    @discardableResult
    public func record(input: String, output: Correction, consented: Bool,
                       appVersion: String, now: Date = Date()) throws -> Bool {
        guard consented else { return false }
        let day = ISO8601DateFormatter.string(from: now, timeZone: .gmt,
                                              formatOptions: [.withFullDate])
        let entry = Entry(input: redactor.redact(input),
                          corrected: redactor.redact(output.corrected),
                          hasError: output.hasError,
                          explanation: redactor.redact(output.explanation),
                          day: day, appVersion: appVersion,
                          osVersion: ProcessInfo.processInfo.operatingSystemVersionString)
        var line = try JSONEncoder().encode(entry)
        line.append(UInt8(ascii: "\n"))
        if !FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: line)
        return true
    }
}
