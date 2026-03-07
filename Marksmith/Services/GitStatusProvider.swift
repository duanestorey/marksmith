import Foundation

/// Provides git status information for the current file.
/// Uses in-memory diffing (CollectionDifference) to compare buffer vs HEAD content.
final class GitStatusProvider: ObservableObject {
    @Published var lineStatuses: [Int: GitLineStatus] = [:]
    @Published var isGitRepo: Bool = false
    @Published var repoRoot: URL?

    private var fileURL: URL?
    private var headContent: String?
    private var relativePath: String?
    /// Background-queue-safe copy of repoRoot (set before the @Published one)
    private var backgroundRepoRoot: URL?
    private let queue = DispatchQueue(label: "com.marksmith.git-status", qos: .utility)
    private var diffWorkItem: DispatchWorkItem?

    func configure(fileURL: URL?) {
        self.fileURL = fileURL
        guard let fileURL = fileURL else {
            self.backgroundRepoRoot = nil
            DispatchQueue.main.async {
                self.isGitRepo = false
                self.repoRoot = nil
                self.lineStatuses = [:]
            }
            return
        }
        queue.async { [weak self] in
            self?.detectRepo(for: fileURL)
        }
    }

    /// Re-fetch HEAD content (e.g. on window focus after external commit)
    func refetchHEAD() {
        guard let fileURL = fileURL else { return }
        queue.async { [weak self] in
            self?.fetchHEADContent(for: fileURL)
        }
    }

    /// Diff the current buffer text against HEAD content, debounced at 300ms.
    func diffBuffer(_ text: String) {
        diffWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.computeInMemoryDiff(currentText: text)
        }
        diffWorkItem = workItem
        queue.asyncAfter(deadline: .now() + 0.3, execute: workItem)
    }

    // MARK: - Git CLI Operations

    private func detectRepo(for fileURL: URL) {
        let dir = fileURL.deletingLastPathComponent().path
        guard let result = runGit(["rev-parse", "--show-toplevel"], in: dir),
              !result.isEmpty
        else {
            self.backgroundRepoRoot = nil
            DispatchQueue.main.async { [weak self] in
                self?.isGitRepo = false
                self?.repoRoot = nil
                self?.lineStatuses = [:]
            }
            return
        }
        let root = URL(fileURLWithPath: result.trimmingCharacters(in: .whitespacesAndNewlines))
        self.backgroundRepoRoot = root
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        self.relativePath = fileURL.path.replacingOccurrences(of: rootPath, with: "")
        DispatchQueue.main.async { [weak self] in
            self?.isGitRepo = true
            self?.repoRoot = root
        }
        fetchHEADContent(for: fileURL)
    }

    private func fetchHEADContent(for fileURL: URL) {
        guard let root = backgroundRepoRoot,
              let relativePath = relativePath else { return }

        // Get the file content at HEAD
        if let content = runGit(["show", "HEAD:\(relativePath)"], in: root.path) {
            self.headContent = content
        } else {
            // File not in HEAD (new file) — all lines are added
            self.headContent = nil
        }
    }

    private func computeInMemoryDiff(currentText: String) {
        guard backgroundRepoRoot != nil else {
            DispatchQueue.main.async { [weak self] in
                self?.lineStatuses = [:]
            }
            return
        }

        // If no HEAD content, all lines are added (new file)
        guard let headContent = headContent else {
            var statuses: [Int: GitLineStatus] = [:]
            if !currentText.isEmpty {
                let lines = currentText.components(separatedBy: "\n")
                for i in 1...lines.count {
                    statuses[i] = .added
                }
            }
            DispatchQueue.main.async { [weak self] in
                self?.lineStatuses = statuses
            }
            return
        }

        let oldLines = headContent.components(separatedBy: "\n")
        let newLines = currentText.components(separatedBy: "\n")

        let diff = newLines.difference(from: oldLines)

        // Build sets of inserted and removed indices
        var insertedIndices = Set<Int>()
        var removedIndices = Set<Int>()

        for change in diff {
            switch change {
            case .insert(let offset, _, _):
                insertedIndices.insert(offset)
            case .remove(let offset, _, _):
                removedIndices.insert(offset)
            }
        }

        var statuses: [Int: GitLineStatus] = [:]

        // Walk through new lines and classify changes
        // Lines that are inserted with a corresponding removal nearby are "modified"
        // Lines that are only inserted are "added"
        // For removed lines, mark the position in the new file

        // Use a simple heuristic: pair removals with insertions
        var pairedInserts = Set<Int>()
        var pairedRemoves = Set<Int>()

        // Sort to pair in order
        let sortedRemoves = removedIndices.sorted()
        let sortedInserts = insertedIndices.sorted()

        // Pair removals with nearby insertions (modified lines)
        var insertIdx = 0
        for removeIdx in sortedRemoves {
            while insertIdx < sortedInserts.count && sortedInserts[insertIdx] < removeIdx {
                insertIdx += 1
            }
            if insertIdx < sortedInserts.count {
                pairedInserts.insert(sortedInserts[insertIdx])
                pairedRemoves.insert(removeIdx)
                insertIdx += 1
            }
        }

        for idx in sortedInserts {
            let lineNumber = idx + 1 // 1-based
            if pairedInserts.contains(idx) {
                statuses[lineNumber] = .modified
            } else {
                statuses[lineNumber] = .added
            }
        }

        // Remaining unpaired removes: mark deletion at their position in new file
        for removeIdx in sortedRemoves where !pairedRemoves.contains(removeIdx) {
            // Find the corresponding position in the new file
            let lineNumber = min(removeIdx + 1, max(newLines.count, 1))
            if statuses[lineNumber] == nil {
                statuses[lineNumber] = .deleted
            }
        }

        DispatchQueue.main.async { [weak self] in
            self?.lineStatuses = statuses
        }
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

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else { return nil }

            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }
}

// MARK: - Git Service for commit/push operations

struct GitFileStatus: Identifiable {
    let id = UUID()
    let statusCode: String
    let filePath: String

    var displayStatus: String {
        switch statusCode {
        case "M": return "Modified"
        case "A": return "Added"
        case "D": return "Deleted"
        case "??": return "Untracked"
        case "R": return "Renamed"
        default: return statusCode
        }
    }

    var statusColor: String {
        switch statusCode {
        case "M": return "blue"
        case "A": return "green"
        case "D": return "red"
        case "??": return "gray"
        default: return "secondary"
        }
    }
}

final class GitService {
    static let shared = GitService()

    func status(repoRoot: String, completion: @escaping ([GitFileStatus]) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            // Use -uall to list individual untracked files (not just directories)
            let output = self.runGitWithOutput(["status", "--porcelain", "-uall"], in: repoRoot) ?? ""
            let files = output.components(separatedBy: "\n")
                .filter { !$0.isEmpty }
                .compactMap { line -> GitFileStatus? in
                    // Porcelain v1 format: XY<space>PATH (exactly 2 status chars + space + path)
                    guard line.count >= 4 else { return nil }
                    let xy = String(line.prefix(2))
                    let path = String(line.dropFirst(3))

                    // Determine display code from XY pair
                    let code: String
                    if xy == "??" {
                        code = "??"
                    } else if xy.hasPrefix("A") {
                        code = "A"
                    } else if xy.hasPrefix("D") || xy.hasSuffix("D") {
                        code = "D"
                    } else if xy.hasPrefix("R") {
                        code = "R"
                    } else if xy.hasPrefix("M") || xy.hasSuffix("M") {
                        code = "M"
                    } else {
                        code = xy.trimmingCharacters(in: .whitespaces)
                    }

                    return GitFileStatus(statusCode: code, filePath: path)
                }
            DispatchQueue.main.async {
                completion(files)
            }
        }
    }

    func commit(
        message: String,
        stageAll: Bool,
        push: Bool,
        repoRoot: String? = nil,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let root: String
                if let repoRoot = repoRoot {
                    root = repoRoot
                } else {
                    guard let found = self.findRepoRoot() else {
                        throw GitError.notARepository
                    }
                    root = found
                }

                if stageAll {
                    try self.runGitOrThrow(["add", "-A"], in: root)
                }

                try self.runGitOrThrow(["commit", "-m", message], in: root)

                if push {
                    try self.runGitOrThrow(["push"], in: root)
                }

                completion(.success(()))
            } catch {
                completion(.failure(error))
            }
        }
    }

    func findRepoRoot() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["rev-parse", "--show-toplevel"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }

    private func runGitWithOutput(_ arguments: [String], in directory: String) -> String? {
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
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            return String(data: data, encoding: .utf8)
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
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
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
