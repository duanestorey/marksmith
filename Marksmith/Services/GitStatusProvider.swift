import Foundation

/// Provides git status information for the current file.
/// Uses the git CLI for reliable operation without external library dependencies.
final class GitStatusProvider: ObservableObject {
    @Published var lineStatuses: [Int: GitLineStatus] = [:]
    @Published var isGitRepo: Bool = false

    private var repoRoot: URL?
    private var fileURL: URL?
    private let queue = DispatchQueue(label: "com.marksmith.git-status", qos: .utility)

    func configure(fileURL: URL?) {
        self.fileURL = fileURL
        guard let fileURL = fileURL else {
            isGitRepo = false
            lineStatuses = [:]
            return
        }
        queue.async { [weak self] in
            self?.detectRepo(for: fileURL)
        }
    }

    func refresh() {
        guard let fileURL = fileURL else { return }
        queue.async { [weak self] in
            self?.computeDiff(for: fileURL)
        }
    }

    // MARK: - Git CLI Operations

    private func detectRepo(for fileURL: URL) {
        let dir = fileURL.deletingLastPathComponent().path
        guard let result = runGit(["rev-parse", "--show-toplevel"], in: dir),
              !result.isEmpty
        else {
            DispatchQueue.main.async { [weak self] in
                self?.isGitRepo = false
                self?.lineStatuses = [:]
            }
            return
        }
        let root = URL(fileURLWithPath: result.trimmingCharacters(in: .whitespacesAndNewlines))
        self.repoRoot = root
        DispatchQueue.main.async { [weak self] in
            self?.isGitRepo = true
        }
        computeDiff(for: fileURL)
    }

    private func computeDiff(for fileURL: URL) {
        guard let repoRoot = repoRoot else { return }
        let relativePath = fileURL.path.replacingOccurrences(of: repoRoot.path + "/", with: "")

        // Get unified diff between HEAD and working tree
        guard let diffOutput = runGit(
            ["diff", "--unified=0", "HEAD", "--", relativePath],
            in: repoRoot.path
        ) else {
            DispatchQueue.main.async { [weak self] in
                self?.lineStatuses = [:]
            }
            return
        }

        let statuses = parseDiff(diffOutput)
        DispatchQueue.main.async { [weak self] in
            self?.lineStatuses = statuses
        }
    }

    /// Parse unified diff output to extract line-level change information.
    private func parseDiff(_ diff: String) -> [Int: GitLineStatus] {
        var statuses: [Int: GitLineStatus] = [:]
        let lines = diff.components(separatedBy: "\n")

        for line in lines {
            // Parse hunk headers: @@ -oldStart,oldCount +newStart,newCount @@
            guard line.hasPrefix("@@") else { continue }

            let parts = line.components(separatedBy: " ")
            guard parts.count >= 3 else { continue }

            let oldPart = parts[1] // e.g., "-10,3"
            let newPart = parts[2] // e.g., "+12,5"

            let oldInfo = parseRange(oldPart)
            let newInfo = parseRange(newPart)

            if newInfo.count == 0 && oldInfo.count > 0 {
                // Lines were deleted — show indicator at the new position
                statuses[newInfo.start] = .deleted
            } else if oldInfo.count == 0 && newInfo.count > 0 {
                // Lines were added
                for i in newInfo.start..<(newInfo.start + newInfo.count) {
                    statuses[i] = .added
                }
            } else {
                // Lines were modified
                for i in newInfo.start..<(newInfo.start + newInfo.count) {
                    statuses[i] = .modified
                }
            }
        }

        return statuses
    }

    private func parseRange(_ range: String) -> (start: Int, count: Int) {
        let cleaned = range.trimmingCharacters(in: CharacterSet(charactersIn: "+-"))
        let parts = cleaned.components(separatedBy: ",")
        let start = Int(parts[0]) ?? 0
        let count = parts.count > 1 ? (Int(parts[1]) ?? 1) : 1
        return (start, count)
    }

    private func runGit(_ arguments: [String], in directory: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: directory)
        process.environment = ProcessInfo.processInfo.environment

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else { return nil }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }
}

// MARK: - Git Service for commit/push operations

final class GitService {
    static let shared = GitService()

    func commit(
        message: String,
        stageAll: Bool,
        push: Bool,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                guard let repoRoot = self.findRepoRoot() else {
                    throw GitError.notARepository
                }

                if stageAll {
                    try self.runGitOrThrow(["add", "-A"], in: repoRoot)
                }

                try self.runGitOrThrow(["commit", "-m", message], in: repoRoot)

                if push {
                    try self.runGitOrThrow(["push"], in: repoRoot)
                }

                completion(.success(()))
            } catch {
                completion(.failure(error))
            }
        }
    }

    func findRepoRoot() -> String? {
        // Use the frontmost document's location or current directory
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["rev-parse", "--show-toplevel"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }

    private func runGitOrThrow(_ arguments: [String], in directory: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: directory)

        let errorPipe = Pipe()
        process.standardOutput = Pipe()
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorString = String(data: errorData, encoding: .utf8) ?? "Unknown git error"
            throw GitError.commandFailed(errorString)
        }
    }
}

enum GitError: LocalizedError {
    case notARepository
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .notARepository:
            return "Not a git repository"
        case .commandFailed(let message):
            return message
        }
    }
}
