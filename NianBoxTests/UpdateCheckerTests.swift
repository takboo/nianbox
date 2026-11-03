import XCTest
@testable import NianBox

@MainActor
final class UpdateCheckerTests: XCTestCase {
    private func preferences() -> UserDefaults {
        let name = "org.nianbox.update-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    private func release(_ version: String = "0.4.0", patch: [String: Any] = [:]) throws -> Data {
        let tag = "v\(version)"
        let name = "NianBox-\(version)-universal.dmg"
        var json: [String: Any] = [
            "tag_name": tag, "draft": false, "prerelease": false, "published_at": "2026-11-03T00:00:00Z",
            "html_url": "https://github.com/takboo/nianbox/releases/tag/\(tag)",
            "assets": [["name": name, "state": "uploaded", "size": 100,
                        "browser_download_url": "https://github.com/takboo/nianbox/releases/download/\(tag)/\(name)"]]
        ]
        json.merge(patch) { _, new in new }
        return try JSONSerialization.data(withJSONObject: json)
    }

    func testVersionsCompareNumericallyAndRejectPrereleasesAndMalformedInput() throws {
        XCTAssertGreaterThan(try XCTUnwrap(ReleaseVersion("0.10.0")), try XCTUnwrap(ReleaseVersion("0.9.9")))
        XCTAssertGreaterThan(try XCTUnwrap(ReleaseVersion("1.0.0")), try XCTUnwrap(ReleaseVersion("0.99.99")))
        for invalid in ["", "1.0", "1.0.0.0", "v1.0.0", "1.0.0-beta.1", "01.0.0", "-1.0.0", "１.0.0", "1.0.x", "1.0.0\n"] {
            XCTAssertNil(ReleaseVersion(invalid), invalid)
        }
    }

    func testOnlyPublishedStableReleasesWithOfficialMacDownloadsAreAccepted() throws {
        XCTAssertEqual(try UpdateChecker.parseRelease(release()).version, "0.4.0")
        for patch: [String: Any] in [["draft": true], ["prerelease": true], ["published_at": NSNull()],
                                   ["tag_name": "v0.4.0-rc.1"], ["html_url": "https://example.com/update"],
                                   ["html_url": "https://github.com/takboo/nianbox/releases/tag/v0.4.0?redirect=1"],
                                   ["assets": []]] {
            XCTAssertThrowsError(try UpdateChecker.parseRelease(release(patch: patch)))
        }
        let badAsset: [String: Any] = ["name": "NianBox-0.4.0-universal.dmg", "state": "uploaded", "size": 100,
                                       "browser_download_url": "https://example.com/untrusted.dmg"]
        XCTAssertThrowsError(try UpdateChecker.parseRelease(release(patch: ["assets": [badAsset]])))
    }

    func testNewerReleaseAppearsAndSurvivesRelaunchWithoutARequest() async throws {
        let defaults = preferences()
        let data = try release()
        let checker = UpdateChecker(defaults: defaults, currentVersion: "0.3.0", fetch: { data })
        await checker.checkNow()
        XCTAssertEqual(checker.availableRelease?.version, "0.4.0")
        XCTAssertEqual(checker.availableRelease?.url.absoluteString, "https://github.com/takboo/nianbox/releases/tag/v0.4.0")
        XCTAssertNotNil(checker.lastChecked)
        XCTAssertFalse(checker.isChecking)
        let reopened = UpdateChecker(defaults: defaults, currentVersion: "0.3.0", fetch: { XCTFail("Unexpected network"); return data })
        XCTAssertEqual(reopened.availableRelease, checker.availableRelease)
    }

    func testCurrentAndOlderReleasesDoNotSuggestDowngradesOrLeaveStaleCache() async throws {
        let defaults = preferences()
        defaults.set(try JSONEncoder().encode(AvailableRelease(version: "0.4.0")), forKey: "updates.available")
        for version in ["0.4.0", "0.3.0"] {
            let data = try release(version)
            let checker = UpdateChecker(defaults: defaults, currentVersion: "0.4.0", fetch: { data })
            XCTAssertNil(checker.availableRelease)
            await checker.checkNow()
            XCTAssertNil(checker.availableRelease)
            XCTAssertNil(defaults.data(forKey: "updates.available"))
            XCTAssertEqual(checker.status, "You're up to date.")
        }
    }

    func testBackgroundChecksAreLimitedAcrossRelaunchButManualChecksWork() async throws {
        let defaults = preferences()
        let clock = MutableNow(Date(timeIntervalSince1970: 1_800_000_000))
        let data = try release()
        var calls = 0
        let fetch: UpdateChecker.Fetch = { calls += 1; return data }
        let checker = UpdateChecker(defaults: defaults, currentVersion: "0.3.0", now: { clock.value }, fetch: fetch)
        await checker.checkIfDue(); await checker.checkIfDue()
        XCTAssertEqual(calls, 1)
        clock.value.addTimeInterval(3600)
        let reopened = UpdateChecker(defaults: defaults, currentVersion: "0.3.0", now: { clock.value }, fetch: fetch)
        await reopened.checkIfDue()
        XCTAssertEqual(calls, 1)
        await reopened.checkNow()
        XCTAssertEqual(calls, 2)
        clock.value.addTimeInterval(UpdateChecker.checkInterval)
        await reopened.checkIfDue()
        XCTAssertEqual(calls, 3)
    }

    func testAutomaticCheckPreferencePersistsAndDoesNotDisableManualChecks() async throws {
        let defaults = preferences()
        let data = try release()
        var calls = 0
        let checker = UpdateChecker(defaults: defaults, currentVersion: "0.3.0", fetch: { calls += 1; return data })
        checker.automaticallyChecks = false
        await checker.checkIfDue()
        XCTAssertEqual(calls, 0)
        XCTAssertFalse(UpdateChecker(defaults: defaults, currentVersion: "0.3.0").automaticallyChecks)
        await checker.checkNow()
        XCTAssertEqual(calls, 1)
    }

    func testOfflineCheckPreservesKnownReleaseAndLastSuccessfulCheck() async throws {
        let defaults = preferences()
        let data = try release()
        let first = UpdateChecker(defaults: defaults, currentVersion: "0.3.0", fetch: { data })
        await first.checkNow()
        let offline = UpdateChecker(defaults: defaults, currentVersion: "0.3.0", fetch: { throw URLError(.notConnectedToInternet) })
        await offline.checkNow()
        XCTAssertEqual(offline.availableRelease, first.availableRelease)
        XCTAssertEqual(offline.lastChecked, first.lastChecked)
        XCTAssertNotNil(offline.errorMessage)
        XCTAssertFalse(offline.isChecking)
    }

    func testFailuresAreAlsoThrottledAndClockRollbackDoesNotDisableChecksForever() async {
        let defaults = preferences()
        let clock = MutableNow(Date(timeIntervalSince1970: 1_800_000_000))
        var calls = 0
        let checker = UpdateChecker(defaults: defaults, currentVersion: "0.3.0", now: { clock.value }, fetch: {
            calls += 1; throw UpdateCheckError.rateLimited
        })
        await checker.checkIfDue(); await checker.checkIfDue()
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(checker.errorMessage, "Update checks are temporarily limited. Try again later.")
        clock.value.addTimeInterval(-60)
        await checker.checkIfDue()
        XCTAssertEqual(calls, 2)
    }

    func testConcurrentRequestsAreCoalesced() async throws {
        let data = try release()
        var continuation: CheckedContinuation<Data, Error>?
        var calls = 0
        let checker = UpdateChecker(defaults: preferences(), currentVersion: "0.3.0", fetch: {
            calls += 1
            return try await withCheckedThrowingContinuation { continuation = $0 }
        })
        let pending = Task { await checker.checkNow() }
        while continuation == nil { await Task.yield() }
        await checker.checkNow()
        XCTAssertEqual(calls, 1)
        continuation?.resume(returning: data)
        await pending.value
        XCTAssertEqual(checker.availableRelease?.version, "0.4.0")
    }

    func testMalformedCachedVersionCannotCreateADownloadLink() {
        let defaults = preferences()
        defaults.set(Data(#"{"version":"https://example.com"}"#.utf8), forKey: "updates.available")
        XCTAssertNil(UpdateChecker(defaults: defaults, currentVersion: "0.3.0").availableRelease)
    }
}

private final class UpdateURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, data) = try Self.handler!(request)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status,
                                                               httpVersion: "HTTP/1.1", headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

final class GitHubReleaseClientTests: XCTestCase {
    private func client() -> GitHubReleaseClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [UpdateURLProtocol.self]
        let session = URLSession(configuration: configuration)
        addTeardownBlock { session.invalidateAndCancel(); UpdateURLProtocol.handler = nil }
        return GitHubReleaseClient(session: session)
    }

    func testRequestUsesPublicEndpointWithoutServerCredentials() async throws {
        UpdateURLProtocol.handler = { request in
            XCTAssertEqual(request.url, GitHubReleaseClient.endpoint)
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/vnd.github+json")
            return (200, Data("public response".utf8))
        }
        let data = try await client().fetch()
        XCTAssertEqual(data, Data("public response".utf8))
    }

    func testHTTPFailuresAndOversizedResponsesAreRejected() async {
        let client = client()
        for status in [403, 429, 404, 500] {
            UpdateURLProtocol.handler = { _ in (status, Data()) }
            do { _ = try await client.fetch(); XCTFail("Accepted HTTP \(status)") }
            catch { XCTAssertTrue(error is UpdateCheckError) }
        }
        UpdateURLProtocol.handler = { _ in (200, Data(repeating: 0, count: 1_048_577)) }
        do { _ = try await client.fetch(); XCTFail("Accepted oversized response") }
        catch { XCTAssertTrue(error is UpdateCheckError) }
    }
}
