import Foundation

// MARK: - GitHub API types

private struct GitHubRelease: Decodable {
    let tagName: String
    let assets: [Asset]

    struct Asset: Decodable {
        let name: String
        let browserDownloadURL: URL
        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }
    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case assets
    }
}

// MARK: - Downloader

/// Downloads and manages the cagent binary from GitHub releases.
/// Install path: ~/Library/Application Support/OScar/cagent
@MainActor
final class CagentDownloader: ObservableObject {

    enum State: Equatable {
        case idle
        case checking
        case downloading
        case installing
        case ready(version: String)
        case failed(String)

        var isInProgress: Bool {
            switch self { case .checking, .downloading, .installing: return true; default: return false }
        }
    }

    @Published private(set) var state: State = .idle

    // MARK: - Paths

    static let installURL: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return support.appendingPathComponent("OScar/cagent")
    }()

    private static let versionURL: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return support.appendingPathComponent("OScar/cagent.version")
    }()

    // MARK: - Public

    /// Reads the installed version from disk and updates state. Call on launch.
    func checkInstalled() {
        guard FileManager.default.isExecutableFile(atPath: Self.installURL.path) else {
            state = .idle
            return
        }
        let version = (try? String(contentsOf: Self.versionURL, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown"
        state = .ready(version: version)
    }

    /// Fetches the latest cagent release from GitHub and installs it.
    func downloadLatest() async {
        state = .checking
        do {
            let release = try await fetchLatestRelease()
            let assetURL = try pickAsset(from: release)
            state = .downloading
            let tmpURL = try await downloadFile(from: assetURL)
            state = .installing
            try await install(tmpURL: tmpURL, assetName: assetURL.lastPathComponent)
            try release.tagName.write(to: Self.versionURL, atomically: true, encoding: .utf8)
            state = .ready(version: release.tagName)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    // MARK: - Private

    private func fetchLatestRelease() async throws -> GitHubRelease {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/docker/cagent/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(GitHubRelease.self, from: data)
    }

    private func pickAsset(from release: GitHubRelease) throws -> URL {
#if arch(arm64)
        let archTokens = ["arm64", "aarch64"]
#else
        let archTokens = ["amd64", "x86_64"]
#endif
        let platformTokens = ["darwin", "macos"]
        let skipSuffixes  = [".sha256", ".md5", ".txt", ".json"]

        for asset in release.assets {
            let name = asset.name.lowercased()
            guard !skipSuffixes.contains(where: { name.hasSuffix($0) }) else { continue }
            guard platformTokens.contains(where: { name.contains($0) }) else { continue }
            guard archTokens.contains(where: { name.contains($0) }) else { continue }
            return asset.browserDownloadURL
        }
        throw DownloadError.noMatchingAsset(
            "No cagent binary found for darwin/\(archTokens.first!) in release \(release.tagName)"
        )
    }

    private func downloadFile(from url: URL) async throws -> URL {
        let (tmpURL, _) = try await URLSession.shared.download(from: url)
        return tmpURL
    }

    private func install(tmpURL: URL, assetName: String) async throws {
        let fm = FileManager.default
        let installDir = Self.installURL.deletingLastPathComponent()
        try fm.createDirectory(at: installDir, withIntermediateDirectories: true)

        let binaryURL: URL
        if assetName.hasSuffix(".tar.gz") || assetName.hasSuffix(".tgz") {
            let extractDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("oscar-cagent-\(UUID().uuidString)")
            try fm.createDirectory(at: extractDir, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: extractDir) }

            try await runProcess("/usr/bin/tar", args: ["xzf", tmpURL.path, "-C", extractDir.path])

            guard let found = findBinary(named: "cagent", in: extractDir) else {
                throw DownloadError.noMatchingAsset("cagent binary not found inside archive")
            }
            binaryURL = found
        } else if assetName.hasSuffix(".zip") {
            let extractDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("oscar-cagent-\(UUID().uuidString)")
            try fm.createDirectory(at: extractDir, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: extractDir) }

            try await runProcess("/usr/bin/unzip", args: ["-q", tmpURL.path, "-d", extractDir.path])

            guard let found = findBinary(named: "cagent", in: extractDir) else {
                throw DownloadError.noMatchingAsset("cagent binary not found inside zip")
            }
            binaryURL = found
        } else {
            // Plain binary
            binaryURL = tmpURL
        }

        if fm.fileExists(atPath: Self.installURL.path) {
            try fm.removeItem(at: Self.installURL)
        }
        try fm.copyItem(at: binaryURL, to: Self.installURL)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: Self.installURL.path)
    }

    private func findBinary(named name: String, in dir: URL) -> URL? {
        let enumerator = FileManager.default.enumerator(
            at: dir,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: .skipsHiddenFiles
        )
        while let url = enumerator?.nextObject() as? URL {
            if url.lastPathComponent == name {
                return url
            }
        }
        return nil
    }

    private func runProcess(_ executable: String, args: [String]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: executable)
            p.arguments = args
            p.terminationHandler = { process in
                if process.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: DownloadError.extractionFailed(process.terminationStatus))
                }
            }
            do { try p.run() } catch { continuation.resume(throwing: error) }
        }
    }
}

// MARK: - Errors

private enum DownloadError: LocalizedError {
    case noMatchingAsset(String)
    case extractionFailed(Int32)

    var errorDescription: String? {
        switch self {
        case .noMatchingAsset(let detail): return detail
        case .extractionFailed(let code): return "Archive extraction failed (exit \(code))"
        }
    }
}
