import XCTest
@testable import HeartAdoption

@MainActor final class AdoptionTests: XCTestCase {
    private func repository() throws -> (DemoRepository, URL) {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        return (DemoRepository(reset: true, directory: directory), directory)
    }
    func testCountryGroupsFollowingAndGlobalSearchAreDifferentScopes() throws {
        let (repository, directory) = try repository()
        defer { try? FileManager.default.removeItem(at: directory) }
        XCTAssertTrue(repository.posts(query: FeedQuery()).allSatisfy { $0.countryCode == "IT" })
        let followed = repository.posts(query: FeedQuery(scope: .following))
        XCTAssertTrue(followed.contains { $0.countryCode == "GR" })
        XCTAssertFalse(followed.contains { $0.countryCode == "PT" })
        let search = repository.posts(query: FeedQuery(scope: .all, search: "Lisbon"))
        XCTAssertEqual(search.map(\.name), ["Nori"])
        let cats = repository.posts(query: FeedQuery(scope: .all, species: .cat))
        XCTAssertTrue(cats.allSatisfy { $0.species == .cat })
        try repository.follow("PT", following: true)
        XCTAssertTrue(repository.posts(query: FeedQuery(scope: .following)).contains { $0.name == "Nori" })
    }
    func testLikesArePerUserAndPersistAcrossRelaunch() throws {
        let (repository, directory) = try repository()
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = try XCTUnwrap(repository.posts(query: FeedQuery()).first)
        _ = try repository.like(original.id)
        XCTAssertTrue(try repository.post(original.id).liked)
        let regularID = repository.user.id
        try repository.switchUser(repository.users.first { $0.isAdmin }!.id)
        XCTAssertFalse(try repository.post(original.id).liked)
        XCTAssertEqual(try repository.post(original.id).likesCount, original.likesCount + 1)
        try repository.switchUser(regularID)
        let relaunched = DemoRepository(directory: directory)
        XCTAssertTrue(try relaunched.post(original.id).liked)
        XCTAssertEqual(relaunched.posts(query: FeedQuery(scope: .liked)).map(\.id), [original.id])
    }
    func testCountryAdministratorCannotModerateOutsideAssignedCountries() throws {
        let (repository, directory) = try repository()
        defer { try? FileManager.default.removeItem(at: directory) }
        let italy = try XCTUnwrap(repository.posts(query: FeedQuery()).first)
        XCTAssertThrowsError(try repository.moderate(italy.id, status: .hidden))
        try repository.switchUser(repository.users.first { $0.isAdmin }!.id)
        let portugal = try XCTUnwrap(repository.posts(query: FeedQuery(scope: .country, country: "PT")).first)
        XCTAssertThrowsError(try repository.moderate(portugal.id, status: .hidden))
        _ = try repository.moderate(italy.id, status: .hidden)
        XCTAssertFalse(repository.posts(query: FeedQuery()).contains { $0.id == italy.id })
        XCTAssertEqual(try repository.post(italy.id).status, .hidden)
        _ = try repository.moderate(italy.id, status: .available)
        XCTAssertTrue(repository.posts(query: FeedQuery()).contains { $0.id == italy.id })
    }
    func testPostCreationUsesAnimalCountryAndSurvivesRestart() throws {
        let (repository, directory) = try repository()
        defer { try? FileManager.default.removeItem(at: directory) }
        var draft = PostDraft()
        draft.name = "Pepper"; draft.countryCode = "PT"; draft.city = "Porto"
        draft.story = "Pepper is a gentle rescue who is ready to find a loving home."
        draft.contactEmail = "rescue@example.org"
        let post = try repository.publish(draft, photos: [Data([1, 2, 3])])
        XCTAssertFalse(repository.posts(query: FeedQuery()).contains { $0.id == post.id })
        XCTAssertTrue(repository.posts(query: FeedQuery(scope: .country, country: "PT")).contains { $0.id == post.id })
        let relaunched = DemoRepository(directory: directory)
        XCTAssertEqual(try relaunched.post(post.id).name, "Pepper")
        XCTAssertTrue(FileManager.default.fileExists(atPath: URL(string: post.photos[0].url)!.path))
        var update = PostDraft(post: post); update.status = .adopted
        _ = try relaunched.update(post.id, draft: update)
        XCTAssertFalse(relaunched.posts(query: FeedQuery(scope: .all)).contains { $0.id == post.id })
        XCTAssertTrue(relaunched.posts(query: FeedQuery(scope: .mine)).contains { $0.id == post.id })
    }
    func testProductionServerRequiresHTTPSAndRejectsCredentialsInURLs() throws {
        XCTAssertThrowsError(try APIClient.validatedURL("http://example.org"))
        XCTAssertThrowsError(try APIClient.validatedURL("https://user:secret@example.org"))
        XCTAssertThrowsError(try APIClient.validatedURL("https://example.org/path"))
        XCTAssertThrowsError(try APIClient.validatedURL("https://example.org?token=secret"))
        XCTAssertEqual(try APIClient.validatedURL("https://example.org").host, "example.org")
        XCTAssertEqual(try APIClient.validatedURL("http://localhost:8787").port, 8787)
    }
    func testCountryCatalogAndDraftValidation() {
        XCTAssertEqual(Country.all.count, 249)
        XCTAssertEqual(Country.all.first { $0.code == "IT" }?.flag, "🇮🇹")
        var draft = PostDraft(); XCTAssertNotNil(draft.validationMessage)
        draft.name = "Luna"; draft.city = "Rome"; draft.story = "Luna is ready for a quiet home and a family to love."; draft.contactEmail = "foster@example.org"
        XCTAssertNil(draft.validationMessage)
        draft.ageMonths = 361; XCTAssertNotNil(draft.validationMessage)
    }
    func testSessionIsStoredInKeychainAndScopedToItsServer() throws {
        let server = URL(string: "https://\(UUID().uuidString.lowercased()).example.invalid")!
        let other = URL(string: "https://another.example.invalid")!
        defer { SessionKeychain.remove(server: server) }
        try SessionKeychain.save("opaque-test-session", server: server)
        XCTAssertEqual(SessionKeychain.read(server: server), "opaque-test-session")
        XCTAssertNil(SessionKeychain.read(server: other))
        SessionKeychain.remove(server: server)
        XCTAssertNil(SessionKeychain.read(server: server))
    }
}
