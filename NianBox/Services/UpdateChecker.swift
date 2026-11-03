import Combine
import Foundation

struct ReleaseVersion: Comparable, Equatable {
    let major: Int
    let minor: Int
    let patch: Int

    init?(_ value: String) {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, parts.allSatisfy({
            !$0.isEmpty && $0.allSatisfy { $0.isASCII && $0.isNumber }
                && ($0.count == 1 || $0.first != "0")
        }), let major = Int(parts[0]), let minor = Int(parts[1]), let patch = Int(parts[2]) else { return nil }
        self.major = major; self.minor = minor; self.patch = patch
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}

struct AvailableRelease: Codable, Equatable {
    let version: String
    var url: URL { URL(string: "https://github.com/takboo/nianbox/releases/tag/v\(version)")! }
}

enum UpdateCheckError: Error {
    case unavailable, rateLimited, invalidRelease
}

struct GitHubReleaseClient {
    static let endpoint = URL(string: "https://api.github.com/repos/takboo/nianbox/releases/latest")!
    let session: URLSession

    init(session: URLSession? = nil) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 20
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        self.session = session ?? URLSession(configuration: configuration)
    }

    func fetch() async throws -> Data {
        var request = URLRequest(url: Self.endpoint, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("NianBox-update-check", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw UpdateCheckError.unavailable }
        if response.statusCode == 403 || response.statusCode == 429 { throw UpdateCheckError.rateLimited }
        guard response.statusCode == 200 else { throw UpdateCheckError.unavailable }
        guard data.count <= 1_048_576 else { throw UpdateCheckError.invalidRelease }
        return data
    }
}

@MainActor
final class UpdateChecker: ObservableObject {
    typealias Fetch = @MainActor () async throws -> Data
    static let brewUpgradeCommand = "brew upgrade --cask takboo/nianbox/nianbox"
    static let checkInterval: TimeInterval = 24 * 60 * 60

    @Published var automaticallyChecks: Bool {
        didSet {
            defaults.set(automaticallyChecks, forKey: "updates.automatic")
            if automaticallyChecks && running {
                Task { @MainActor [weak self] in await self?.checkIfDue() }
            }
        }
    }
    @Published private(set) var isChecking = false
    @Published private(set) var availableRelease: AvailableRelease?
    @Published private(set) var lastChecked: Date?
    @Published private(set) var errorMessage: String?
    let currentVersion: String

    private let defaults: UserDefaults
    private let now: () -> Date
    private let fetch: Fetch
    private var periodic: Task<Void, Never>?
    private var running = false

    init(defaults: UserDefaults = .standard,
         currentVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0",
         now: @escaping () -> Date = Date.init, fetch: Fetch? = nil) {
        self.defaults = defaults; self.currentVersion = currentVersion; self.now = now
        let client = GitHubReleaseClient()
        self.fetch = fetch ?? { try await client.fetch() }
        automaticallyChecks = defaults.object(forKey: "updates.automatic") as? Bool ?? true
        lastChecked = defaults.object(forKey: "updates.lastChecked") as? Date
        if let data = defaults.data(forKey: "updates.available"),
           let saved = try? JSONDecoder().decode(AvailableRelease.self, from: data),
           let version = ReleaseVersion(saved.version), let current = ReleaseVersion(currentVersion), version > current {
            availableRelease = saved
        }
    }

    var status: String {
        if isChecking { return "Checking for updates…" }
        if let errorMessage { return errorMessage }
        if let availableRelease { return "NianBox \(availableRelease.version) is available." }
        return lastChecked == nil ? "Not checked yet." : "You're up to date."
    }

    func start() {
        guard !running else { return }
        running = true
        periodic = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                await self?.checkIfDue()
                do { try await Task.sleep(for: .seconds(3600)) } catch { return }
            }
        }
    }

    func stop() {
        running = false
        periodic?.cancel(); periodic = nil
    }

    func checkIfDue() async {
        guard automaticallyChecks else { return }
        if let attempt = defaults.object(forKey: "updates.lastAttempt") as? Date {
            let elapsed = now().timeIntervalSince(attempt)
            if elapsed >= 0 && elapsed < Self.checkInterval { return }
        }
        await checkNow()
    }

    func checkNow() async {
        guard !isChecking else { return }
        isChecking = true
        errorMessage = nil
        defaults.set(now(), forKey: "updates.lastAttempt")
        defer { isChecking = false }
        do {
            let data = try await fetch()
            try Task.checkCancellation()
            let release = try Self.parseRelease(data)
            guard let current = ReleaseVersion(currentVersion), let version = ReleaseVersion(release.version) else {
                throw UpdateCheckError.invalidRelease
            }
            availableRelease = version > current ? release : nil
            if let availableRelease {
                defaults.set(try JSONEncoder().encode(availableRelease), forKey: "updates.available")
            } else {
                defaults.removeObject(forKey: "updates.available")
            }
            lastChecked = now()
            defaults.set(lastChecked, forKey: "updates.lastChecked")
        } catch {
            guard !Task.isCancelled else { return }
            if case UpdateCheckError.rateLimited = error {
                errorMessage = "Update checks are temporarily limited. Try again later."
            } else {
                errorMessage = "Could not check for updates. Check your connection and try again."
            }
            // Retain a previously verified update notice while offline.
        }
    }

    static func parseRelease(_ data: Data) throws -> AvailableRelease {
        struct Response: Decodable {
            struct Asset: Decodable { let name: String; let browser_download_url: String; let state: String; let size: Int }
            let tag_name: String
            let html_url: String
            let draft: Bool
            let prerelease: Bool
            let published_at: String?
            let assets: [Asset]
        }
        let response = try JSONDecoder().decode(Response.self, from: data)
        guard !response.draft, !response.prerelease, response.published_at != nil,
              response.tag_name.hasPrefix("v") else { throw UpdateCheckError.invalidRelease }
        let version = String(response.tag_name.dropFirst())
        guard ReleaseVersion(version) != nil else { throw UpdateCheckError.invalidRelease }
        let release = AvailableRelease(version: version)
        let name = "NianBox-\(version)-universal.dmg"
        guard response.html_url == release.url.absoluteString,
              response.assets.contains(where: {
                  $0.name == name && $0.state == "uploaded" && $0.size > 0
                      && $0.browser_download_url == "https://github.com/takboo/nianbox/releases/download/v\(version)/\(name)"
              }) else { throw UpdateCheckError.invalidRelease }
        return release
    }
}
