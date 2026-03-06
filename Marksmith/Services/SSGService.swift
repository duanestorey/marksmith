import Foundation
import Combine

/// Manages a background SSG (Static Site Generator) process for build/serve.
final class SSGService: ObservableObject {
    enum Status: Equatable {
        case stopped
        case starting
        case running(url: String)
        case error(String)

        var isRunning: Bool {
            if case .running = self { return true }
            if case .starting = self { return true }
            return false
        }
    }

    @Published var status: Status = .stopped
    @Published var output: String = ""

    private var process: Process?
    private var outputPipe: Pipe?
    private let queue = DispatchQueue(label: "com.marksmith.ssg", qos: .utility)

    // URL detection pattern
    private static let urlPattern = try! NSRegularExpression(
        pattern: #"https?://(?:localhost|127\.0\.0\.1):\d+"#,
        options: .caseInsensitive
    )

    // ANSI escape sequence pattern
    private static let ansiPattern = try! NSRegularExpression(
        pattern: #"\x1B\[[0-9;]*[A-Za-z]"#
    )

    static func stripANSI(_ text: String) -> String {
        ansiPattern.stringByReplacingMatches(
            in: text, range: NSRange(location: 0, length: text.utf16.count),
            withTemplate: ""
        )
    }

    deinit {
        // Terminate process directly without dispatching (self is being deallocated)
        if let process = process, process.isRunning {
            process.terminate()
        }
        process = nil
        outputPipe = nil
    }

    func serve(command: String, workingDirectory: String, configuredURL: String? = nil) {
        stop()

        DispatchQueue.main.async {
            self.status = .starting
            self.output = ""
        }

        queue.async { [weak self] in
            self?.launchProcess(command: command, workingDirectory: workingDirectory, configuredURL: configuredURL)
        }
    }

    func stop() {
        if let process = process, process.isRunning {
            process.terminate()
        }
        process = nil
        outputPipe = nil

        DispatchQueue.main.async { [weak self] in
            self?.status = .stopped
        }
    }

    func build(command: String, workingDirectory: String, completion: @escaping (Result<String, Error>) -> Void) {
        queue.async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", command]
            process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)

            let pipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = pipe
            process.standardError = errorPipe

            do {
                try process.run()
                process.waitUntilExit()

                let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let outputString = Self.stripANSI(String(data: outputData, encoding: .utf8) ?? "")
                let errorString = Self.stripANSI(String(data: errorData, encoding: .utf8) ?? "")

                if process.terminationStatus == 0 {
                    completion(.success(outputString + errorString))
                } else {
                    completion(.failure(SSGError.buildFailed(errorString)))
                }
            } catch {
                completion(.failure(error))
            }
        }
    }

    private func launchProcess(command: String, workingDirectory: String, configuredURL: String?) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/sh")
        proc.arguments = ["-c", command]
        proc.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        self.outputPipe = pipe
        self.process = proc

        // Read output asynchronously for URL detection
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            let raw = String(data: data, encoding: .utf8) ?? ""
            let str = Self.stripANSI(raw)

            DispatchQueue.main.async {
                self?.output += str
                if let accumulated = self?.output {
                    self?.detectURL(in: accumulated, configuredURL: configuredURL)
                }
            }
        }

        proc.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async {
                if proc.terminationStatus != 0 {
                    self?.status = .error("Process exited with code \(proc.terminationStatus)")
                } else {
                    self?.status = .stopped
                }
            }
        }

        do {
            try proc.run()
        } catch {
            DispatchQueue.main.async { [weak self] in
                self?.status = .error(error.localizedDescription)
            }
        }
    }

    private func detectURL(in text: String, configuredURL: String?) {
        // If already detected a URL, skip
        if case .running = status { return }

        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)

        if let match = Self.urlPattern.firstMatch(in: text, range: range) {
            let url = nsText.substring(with: match.range)
            status = .running(url: url)
        } else if let configuredURL = configuredURL, !configuredURL.isEmpty {
            // If we have output but no detected URL, use configured URL after a short delay
            if output.count > 200 {
                status = .running(url: configuredURL)
            }
        }
    }
}

enum SSGError: LocalizedError {
    case buildFailed(String)

    var errorDescription: String? {
        switch self {
        case .buildFailed(let message):
            return "Build failed: \(message)"
        }
    }
}
