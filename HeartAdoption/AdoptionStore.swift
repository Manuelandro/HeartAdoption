import Foundation
import Observation

@MainActor @Observable final class AdoptionStore {
    private(set) var serverURL: URL?
    private(set) var user: AppUser?
    private(set) var countries: [Country] = Country.all
    private(set) var postsByID: [String: AdoptionPost] = [:]
    private(set) var revision = 0
    private(set) var isLoading = false
    private(set) var workingLikes: Set<String> = []
    var errorMessage: String?
    var showAuthentication = false
    private var sessionToken: String?
    private let demo: DemoRepository
    var isDemo: Bool { serverURL == nil }
    var demoUsers: [AppUser] { demo.users }
    var api: APIClient? { serverURL.map { APIClient(baseURL: $0, token: sessionToken) } }
    var liveServerAddress: String? {
        let candidates = [UserDefaults.standard.string(forKey: "lastServerURL"), Bundle.main.object(forInfoDictionaryKey: "APIBaseURL") as? String]
        return candidates.compactMap { $0 }.first { (try? APIClient.validatedURL($0)) != nil }
    }

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        demo = DemoRepository(reset: arguments.contains("--uitesting"))
        let unitTestHost = ProcessInfo.processInfo.environment["XCTestBundlePath"] != nil
        if arguments.contains("--demo") || unitTestHost { serverURL = nil }
        else if let index = arguments.firstIndex(of: "--api-url"), arguments.indices.contains(index + 1) { serverURL = try? APIClient.validatedURL(arguments[index + 1]) }
        else if arguments.contains("--uitesting") { serverURL = nil }
        else {
            let configured = UserDefaults.standard.string(forKey: "serverURL") ?? (Bundle.main.object(forInfoDictionaryKey: "APIBaseURL") as? String ?? "")
            serverURL = try? APIClient.validatedURL(configured)
        }
        if let serverURL { sessionToken = SessionKeychain.read(server: serverURL) }
        else { user = demo.user; updateDemoCountries() }
    }

    func bootstrap() async {
        guard let api else { return }
        isLoading = true; defer { isLoading = false }
        do {
            if sessionToken != nil {
                do { user = try await api.request("GET", "v1/me") }
                catch AppFailure.server(401, _) {
                    if let serverURL { SessionKeychain.remove(server: serverURL) }
                    sessionToken = nil; user = nil
                }
            }
            countries = try await self.api!.request("GET", "v1/countries")
            revision += 1
        } catch { errorMessage = error.localizedDescription }
    }
    func connect(to text: String) async throws {
        let url = try APIClient.validatedURL(text)
        struct Health: Decodable { let status: String }
        let _: Health = try await APIClient(baseURL: url).request("GET", "health")
        var saved = SessionKeychain.read(server: url)
        var newUser: AppUser?
        if saved != nil {
            do { newUser = try await APIClient(baseURL: url, token: saved).request("GET", "v1/me") }
            catch AppFailure.server(401, _) { SessionKeychain.remove(server: url); saved = nil }
        }
        let newCountries: [Country] = try await APIClient(baseURL: url, token: saved).request("GET", "v1/countries")
        serverURL = url; sessionToken = saved; user = newUser; countries = newCountries
        UserDefaults.standard.set(url.absoluteString, forKey: "serverURL")
        UserDefaults.standard.set(url.absoluteString, forKey: "lastServerURL")
        postsByID.removeAll(); revision += 1
    }
    func useDemo() {
        if let serverURL { UserDefaults.standard.set(serverURL.absoluteString, forKey: "lastServerURL") }
        serverURL = nil; sessionToken = nil; user = demo.user
        UserDefaults.standard.set("", forKey: "serverURL")
        postsByID.removeAll(); updateDemoCountries(); revision += 1
    }
    func switchDemoUser(_ id: String) throws {
        guard isDemo else { return }
        try demo.switchUser(id); user = demo.user; postsByID.removeAll(); updateDemoCountries(); revision += 1
    }
    func authenticate(email: String, password: String, name: String?, country: String) async throws {
        guard let api, let serverURL else { throw AppFailure.message("Connect to your server to create an account.") }
        struct Login: Encodable { let email: String; let password: String }
        struct Register: Encodable { let email: String; let password: String; let name: String; let homeCountry: String }
        let response: AuthResponse
        if let name { response = try await api.request("POST", "v1/auth/register", body: Register(email: email, password: password, name: name, homeCountry: country)) }
        else { response = try await api.request("POST", "v1/auth/login", body: Login(email: email, password: password)) }
        try SessionKeychain.save(response.token, server: serverURL)
        sessionToken = response.token; user = response.user
        countries = try await self.api!.request("GET", "v1/countries")
        postsByID.removeAll(); revision += 1
    }
    func signOut() async throws {
        if let api { _ = try await api.send("DELETE", "v1/auth/session") }
        if let serverURL { SessionKeychain.remove(server: serverURL) }
        sessionToken = nil; user = nil; postsByID.removeAll(); revision += 1
    }
    func deleteAccount(password: String) async throws {
        guard let api else { return }
        struct Body: Encodable { let password: String }
        _ = try await api.send("DELETE", "v1/me", body: Body(password: password))
        if let serverURL { SessionKeychain.remove(server: serverURL) }
        sessionToken = nil; user = nil; postsByID.removeAll(); revision += 1
    }
    func updateProfile(name: String, country: String) async throws {
        if let api {
            struct Body: Encodable { let name: String; let homeCountry: String }
            user = try await api.request("PATCH", "v1/me", body: Body(name: name, homeCountry: country))
        } else { try demo.updateUser(name: name, country: country); user = demo.user }
        revision += 1
    }
    func country(_ code: String) -> Country { countries.first { $0.code == code } ?? Country(code: code, name: code) }
    func requireUser() -> Bool {
        guard user != nil else { showAuthentication = true; return false }
        return true
    }
    func follow(_ code: String) async throws {
        guard let user else { showAuthentication = true; return }
        let following = !user.followedCountries.contains(code)
        if let api {
            _ = try await api.send(following ? "PUT" : "DELETE", "v1/countries/\(code)/follow")
            self.user = try await api.request("GET", "v1/me")
            countries = try await api.request("GET", "v1/countries")
        } else { try demo.follow(code, following: following); self.user = demo.user; updateDemoCountries() }
        revision += 1
    }
    func feed(_ query: FeedQuery, cursor: String? = nil) async throws -> PostPage {
        let page: PostPage
        if let api {
            var items = [URLQueryItem(name: "scope", value: query.scope.rawValue)]
            if let code = query.country { items.append(.init(name: "country", value: code)) }
            if let species = query.species { items.append(.init(name: "species", value: species.rawValue)) }
            if !query.search.isEmpty { items.append(.init(name: "q", value: query.search)) }
            if let cursor { items.append(.init(name: "cursor", value: cursor)) }
            page = try await api.request("GET", "v1/posts", query: items)
        } else { page = PostPage(posts: demo.posts(query: query), nextCursor: nil) }
        cache(page.posts); return page
    }
    func post(_ id: String) async throws -> AdoptionPost {
        let post: AdoptionPost
        if let api { post = try await api.request("GET", "v1/posts/\(id)") }
        else { post = try demo.post(id) }
        cache([post]); return post
    }
    func publish(_ draft: PostDraft, photos: [Data]) async throws -> AdoptionPost {
        guard let _ = user else { throw AppFailure.message("Sign in to post an animal.") }
        if let message = draft.validationMessage { throw AppFailure.message(message) }
        guard (1...6).contains(photos.count) else { throw AppFailure.message("Add between one and six photos.") }
        let post: AdoptionPost
        if let api {
            var payload = draft; payload.photos = photos.map { $0.base64EncodedString() }
            post = try await api.request("POST", "v1/posts", body: payload)
        } else { post = try demo.publish(draft, photos: photos); updateDemoCountries() }
        cache([post]); revision += 1; return post
    }
    func update(_ id: String, draft: PostDraft) async throws -> AdoptionPost {
        if let message = draft.validationMessage { throw AppFailure.message(message) }
        let post: AdoptionPost
        if let api { post = try await api.request("PATCH", "v1/posts/\(id)", body: draft) }
        else { post = try demo.update(id, draft: draft); updateDemoCountries() }
        cache([post]); revision += 1; return post
    }
    func delete(_ id: String) async throws {
        if let api { _ = try await api.send("DELETE", "v1/posts/\(id)") }
        else { try demo.delete(id); updateDemoCountries() }
        postsByID.removeValue(forKey: id); revision += 1
    }
    func like(_ id: String) async throws {
        guard requireUser(), !workingLikes.contains(id), let existing = postsByID[id] else { return }
        workingLikes.insert(id); defer { workingLikes.remove(id) }
        if let api {
            _ = try await api.send(existing.liked ? "DELETE" : "PUT", "v1/posts/\(id)/like")
            cache([try await post(id)])
        } else { cache([try demo.like(id)]) }
        revision += 1
    }
    func report(_ id: String, reason: String) async throws {
        if let api {
            struct Body: Encodable { let reason: String }
            _ = try await api.send("POST", "v1/posts/\(id)/report", body: Body(reason: reason))
        } else { try demo.report(id, reason: reason) }
    }
    func moderation(cursor: String? = nil) async throws -> ModerationPage {
        let page: ModerationPage
        if let api { page = try await api.request("GET", "v1/moderation", query: cursor.map { [.init(name: "cursor", value: $0)] } ?? []) }
        else { page = demo.moderation() }
        cache(page.posts); return page
    }
    func moderate(_ id: String, status: PostStatus) async throws {
        let post: AdoptionPost
        if let api {
            struct Body: Encodable { let status: PostStatus }
            post = try await api.request("PATCH", "v1/moderation/posts/\(id)", body: Body(status: status))
        } else { post = try demo.moderate(id, status: status); updateDemoCountries() }
        cache([post]); revision += 1
    }
    func resolve(_ id: String) async throws {
        if let api { _ = try await api.send("POST", "v1/moderation/reports/\(id)/resolve") }
        else { try demo.resolve(id) }
        revision += 1
    }
    func shareURL(for post: AdoptionPost) -> URL? { serverURL?.appending(path: "p/\(post.id)") }
    var invitationURL: URL? { serverURL?.appending(path: "invite") }
    func shareMessage(for post: AdoptionPost) -> String {
        "Meet \(post.name), a \(post.species.rawValue) looking for a home in \(post.city), \(country(post.countryCode).name)."
    }
    func shareText(for post: AdoptionPost) -> String {
        if let url = shareURL(for: post) { return "\(shareMessage(for: post))\n\(url.absoluteString)" }
        return "Meet \(post.name) in the Heart Adoption app preview. This is a sample adoption post."
    }
    var invitation: String {
        if let serverURL { return "A home changes everything. Join me on Heart Adoption and help dogs and cats find their people.\n\(serverURL.appending(path: "invite").absoluteString)" }
        return "I’m trying Heart Adoption, an iOS app for helping shelter and street dogs and cats find homes. Ask me for the app’s TestFlight invitation."
    }
    private func cache(_ posts: [AdoptionPost]) { for post in posts { postsByID[post.id] = post } }
    private func updateDemoCountries() {
        countries = Country.all.map { country in
            var country = country
            country.isFollowing = demo.user.followedCountries.contains(country.code)
            country.postCount = demo.state.posts.filter { $0.countryCode == country.code && $0.status == .available }.count
            country.followerCount = demo.users.filter { $0.followedCountries.contains(country.code) }.count
            return country
        }
    }
}
