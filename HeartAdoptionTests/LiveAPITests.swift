import XCTest
import UIKit
@testable import HeartAdoption

final class LiveAPITests: XCTestCase {
    @MainActor func testExpiredSessionDoesNotBlockReturningToLiveBrowsing() async throws {
        let url = URL(string: "http://localhost:8787")!
        struct Health: Decodable { let status: String }
        do { let _: Health = try await APIClient(baseURL: url).request("GET", "health") }
        catch { throw XCTSkip("Start the local API to check session recovery.") }
        let oldToken = SessionKeychain.read(server: url)
        let defaults = UserDefaults.standard
        let oldServer = defaults.string(forKey: "serverURL")
        let oldLastServer = defaults.string(forKey: "lastServerURL")
        defer {
            if let oldToken { try? SessionKeychain.save(oldToken, server: url) } else { SessionKeychain.remove(server: url) }
            if let oldServer { defaults.set(oldServer, forKey: "serverURL") } else { defaults.removeObject(forKey: "serverURL") }
            if let oldLastServer { defaults.set(oldLastServer, forKey: "lastServerURL") } else { defaults.removeObject(forKey: "lastServerURL") }
        }
        try SessionKeychain.save(String(repeating: "x", count: 43), server: url)
        let store = AdoptionStore()
        try await store.connect(to: url.absoluteString)
        XCTAssertNil(store.user)
        XCTAssertNil(SessionKeychain.read(server: url))
        XCTAssertEqual(store.countries.count, 249)
        store.useDemo()
        XCTAssertEqual(store.liveServerAddress, url.absoluteString)
        try await store.connect(to: try XCTUnwrap(store.liveServerAddress))
        XCTAssertNil(store.user)
        XCTAssertEqual(store.serverURL, url)
    }

    /// Runs against the developer's running API; CI uses the isolated server suite.
    func testNativeClientAgainstRunningAPI() async throws {
        let base = URL(string: "http://localhost:8787")!
        struct Health: Decodable { let status: String }
        let anonymous = APIClient(baseURL: base)
        do { let _: Health = try await anonymous.request("GET", "health") }
        catch { throw XCTSkip("Start the API with npm run dev -- --local to check the native network client.") }
        struct Registration: Encodable { let email: String; let password: String; let name: String; let homeCountry: String }
        struct Delete: Encodable { let password: String }
        let password = UUID().uuidString
        let account: AuthResponse = try await anonymous.request("POST", "v1/auth/register", body: Registration(email: "native-\(UUID().uuidString)@example.invalid", password: password, name: "Native verification", homeCountry: "IT"))
        let client = APIClient(baseURL: base, token: account.token)
        do {
            let me: AppUser = try await client.request("GET", "v1/me")
            XCTAssertEqual(me.homeCountry, "IT"); XCTAssertTrue(me.adminCountries.isEmpty)
            let countries: [Country] = try await client.request("GET", "v1/countries")
            XCTAssertEqual(countries.count, 249)
            var draft = PostDraft(); draft.name = "Native client verification"; draft.city = "Rome"
            draft.story = "Temporary animal post created by the native networking integration check."
            draft.contactEmail = "verification@example.invalid"
            let data = try await MainActor.run { try XCTUnwrap(UIImage(named: "milo")?.jpegData(compressionQuality: 0.65)) }
            draft.photos = [data.base64EncodedString()]
            let post: AdoptionPost = try await client.request("POST", "v1/posts", body: draft)
            XCTAssertEqual(post.name, draft.name); XCTAssertEqual(post.photos.count, 1)
            XCTAssertLessThan(abs(post.createdAt.timeIntervalSinceNow), 120)
            _ = try await client.send("PUT", "v1/posts/\(post.id)/like")
            let liked: PostPage = try await client.request("GET", "v1/posts", query: [.init(name: "scope", value: "liked")])
            XCTAssertEqual(liked.posts.map(\.id), [post.id]); XCTAssertTrue(liked.posts[0].liked)
            let (_, response) = try await URLSession.shared.data(from: URL(string: post.photos[0].url)!)
            XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
            let (_, share) = try await URLSession.shared.data(from: base.appending(path: "p/\(post.id)"))
            XCTAssertEqual((share as? HTTPURLResponse)?.statusCode, 200)
            _ = try await client.send("DELETE", "v1/me", body: Delete(password: password))
        } catch {
            _ = try? await client.send("DELETE", "v1/me", body: Delete(password: password))
            throw error
        }
    }
}
