import Foundation

/// A separate, labelled sample world. It is never merged into a connected server.
@MainActor final class DemoRepository {
    struct Snapshot: Codable {
        var users: [AppUser]
        var posts: [AdoptionPost]
        var reports: [PostReport]
        var activeUserID: String
        var likedPostIDs: [String: [String]]
    }
    private let fileURL: URL
    private(set) var state: Snapshot

    init(reset: Bool = false, directory: URL? = nil) {
        let directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "HeartAdoption")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appending(path: "sample-world.json")
        if !reset, let data = try? Data(contentsOf: fileURL), let snapshot = try? AppJSON.decoder().decode(Snapshot.self, from: data) { state = snapshot }
        else { state = Self.seed() }
    }
    var user: AppUser { state.users.first { $0.id == state.activeUserID }! }
    var users: [AppUser] { state.users }
    func save() throws { try AppJSON.encoder().encode(state).write(to: fileURL, options: .atomic) }
    func switchUser(_ id: String) throws {
        guard state.users.contains(where: { $0.id == id }) else { return }
        state.activeUserID = id
        try save()
    }
    func updateUser(name: String, country: String) throws {
        let index = state.users.firstIndex { $0.id == user.id }!
        state.users[index].name = name; state.users[index].homeCountry = country
        try save()
    }
    func follow(_ code: String, following: Bool) throws {
        let index = state.users.firstIndex { $0.id == user.id }!
        state.users[index].followedCountries.removeAll { $0 == code }
        if following { state.users[index].followedCountries.append(code) }
        try save()
    }
    func posts(query: FeedQuery) -> [AdoptionPost] {
        state.posts.map(personalized).filter { post in
            if query.scope == .mine { return post.authorID == user.id }
            guard post.status == .available else { return false }
            switch query.scope {
            case .home: if post.countryCode != user.homeCountry { return false }
            case .following: if !user.followedCountries.contains(post.countryCode) { return false }
            case .country: if post.countryCode != query.country { return false }
            case .liked: if !post.liked { return false }
            default: break
            }
            if let species = query.species, post.species != species { return false }
            return query.search.isEmpty || "\(post.name) \(post.city) \(post.story)".localizedCaseInsensitiveContains(query.search)
        }.sorted { $0.createdAt > $1.createdAt }
    }
    func post(_ id: String) throws -> AdoptionPost {
        guard let post = state.posts.first(where: { $0.id == id }), post.status != .hidden || post.authorID == user.id || user.adminCountries.contains(post.countryCode) else { throw AppFailure.message("This post is no longer available.") }
        return personalized(post)
    }
    func publish(_ draft: PostDraft, photos: [Data]) throws -> AdoptionPost {
        guard !photos.isEmpty else { throw AppFailure.message("Add at least one photo.") }
        let references = try photos.map { data in
            let id = UUID().uuidString
            let url = fileURL.deletingLastPathComponent().appending(path: "\(id).jpg")
            try data.write(to: url, options: .atomic)
            return AnimalPhoto(id: id, url: url.absoluteString)
        }
        let post = AdoptionPost(id: UUID().uuidString, authorID: user.id, authorName: user.name, name: draft.name,
            species: draft.species, sex: draft.sex, ageMonths: draft.ageMonths, size: draft.size, source: draft.source,
            countryCode: draft.countryCode, city: draft.city, story: draft.story, contactEmail: draft.contactEmail,
            vaccinated: draft.vaccinated, neutered: draft.neutered, status: .available, createdAt: Date(), likesCount: 0, liked: false, photos: references)
        state.posts.insert(post, at: 0); try save(); return post
    }
    func update(_ id: String, draft: PostDraft) throws -> AdoptionPost {
        guard let i = state.posts.firstIndex(where: { $0.id == id }), state.posts[i].authorID == user.id else { throw AppFailure.message("You can only edit your own posts.") }
        guard state.posts[i].status != .hidden else { throw AppFailure.message("A country administrator has hidden this post.") }
        state.posts[i].name = draft.name; state.posts[i].species = draft.species; state.posts[i].sex = draft.sex
        state.posts[i].ageMonths = draft.ageMonths; state.posts[i].size = draft.size; state.posts[i].source = draft.source
        state.posts[i].countryCode = draft.countryCode; state.posts[i].city = draft.city; state.posts[i].story = draft.story
        state.posts[i].contactEmail = draft.contactEmail; state.posts[i].vaccinated = draft.vaccinated; state.posts[i].neutered = draft.neutered
        state.posts[i].status = draft.status ?? .available; try save(); return state.posts[i]
    }
    func delete(_ id: String) throws {
        let existing = try post(id)
        guard existing.authorID == user.id else { throw AppFailure.message("You can only delete your own posts.") }
        state.posts.removeAll { $0.id == id }; state.reports.removeAll { $0.postID == id }
        for key in state.likedPostIDs.keys { state.likedPostIDs[key]?.removeAll { $0 == id } }
        try save()
        for photo in existing.photos { if let url = URL(string: photo.url), url.isFileURL { try? FileManager.default.removeItem(at: url) } }
    }
    func like(_ id: String) throws -> AdoptionPost {
        guard let i = state.posts.firstIndex(where: { $0.id == id }), state.posts[i].status == .available else { throw AppFailure.message("This animal is no longer available.") }
        var ids = state.likedPostIDs[user.id] ?? []
        let wasLiked = ids.contains(id)
        if wasLiked { ids.removeAll { $0 == id } } else { ids.append(id) }
        state.likedPostIDs[user.id] = ids
        state.posts[i].likesCount += wasLiked ? -1 : 1
        try save(); return personalized(state.posts[i])
    }
    func report(_ id: String, reason: String) throws {
        _ = try post(id)
        state.reports.append(PostReport(id: UUID().uuidString, postID: id, reason: reason, createdAt: Date())); try save()
    }
    func moderation() -> ModerationPage {
        let posts = state.posts.filter { user.adminCountries.contains($0.countryCode) }
        return ModerationPage(posts: posts, reports: state.reports.filter { report in posts.contains { $0.id == report.postID } })
    }
    func moderate(_ id: String, status: PostStatus) throws -> AdoptionPost {
        guard let i = state.posts.firstIndex(where: { $0.id == id }), user.adminCountries.contains(state.posts[i].countryCode) else { throw AppFailure.message("You can only moderate your assigned countries.") }
        state.posts[i].status = status; state.reports.removeAll { $0.postID == id }; try save(); return state.posts[i]
    }
    func resolve(_ reportID: String) throws {
        guard let report = state.reports.first(where: { $0.id == reportID }), let post = state.posts.first(where: { $0.id == report.postID }), user.adminCountries.contains(post.countryCode) else { throw AppFailure.message("You can only resolve reports in your assigned countries.") }
        state.reports.removeAll { $0.id == reportID }; try save()
    }

    private static func seed() -> Snapshot {
        let regular = AppUser(id: "11111111-1111-4111-8111-111111111111", name: "Alex", email: "alex@example.com", homeCountry: "IT", adminCountries: [], followedCountries: ["IT", "GR"])
        let admin = AppUser(id: "22222222-2222-4222-8222-222222222222", name: "Sofia", email: "sofia@example.com", homeCountry: "IT", adminCountries: ["IT", "GR"], followedCountries: ["IT", "GR"])
        let shelterID = "33333333-3333-4333-8333-333333333333"
        let entries: [(String, Species, String, String, String, String, Int, AnimalSex, AnimalSize, AnimalSource, String)] = [
            ("Milo", .dog, "IT", "Florence", "milo", "Milo has a way of making every walk feel like an adventure. Rescued from the streets near Florence, he now loves belly rubs, a sunny patch of grass, and anyone with a tennis ball. He is gentle with other dogs and would love a family who enjoys being outdoors. His foster carer can arrange a first meeting.", 24, .male, .medium, .street, "Hope Paws Florence"),
            ("Luna", .cat, "IT", "Rome", "luna", "Luna is a quiet little companion with a very loud purr. She was found with her kittens, who have all found homes. Now it is her turn. She likes slow mornings, windowsills, and sitting beside you while you read. She would do best in a calm indoor home.", 18, .female, .small, .shelter, "Casa dei Gatti"),
            ("Olive", .dog, "GR", "Athens", "olive", "Olive was rescued outside Athens and has been discovering the joys of living with people. She is curious, playful, and learning her first commands. A patient home with time for training would help her blossom. Her shelter will guide you through every step of adoption.", 9, .female, .medium, .shelter, "Athens Animal Rescue"),
            ("Nori", .cat, "PT", "Lisbon", "nori", "Nori is an affectionate tabby who greets everyone at the door. He loves chasing feather toys and curling up on a soft blanket afterward. His current foster family says he is confident around other cats and happiest when he has company.", 36, .male, .small, .family, "Lisbon Foster Friends"),
            ("Teddy", .dog, "IT", "Bologna", "teddy", "Teddy is the resident optimist at our shelter. He has never met a person he did not want to be friends with. He enjoys gentle walks and has a soft spot for squeaky toys. We are looking for a home where he can settle in and be part of everyday family life.", 60, .male, .large, .shelter, "Seconda Zampa"),
            ("Cleo", .cat, "ES", "Barcelona", "luna", "Cleo is a curious young cat who loves to explore and then find the nearest lap. She came to us after being found in a garden and is ready for a safe indoor home with plenty of playtime. Meet her and see whether you might be her person.", 12, .female, .small, .street, "Barcelona Cat Care"),
        ]
        let posts = entries.enumerated().map { index, e in
            AdoptionPost(id: String(format: "44444444-4444-4444-8444-%012d", index + 1), authorID: shelterID,
                authorName: e.10, name: e.0, species: e.1, sex: e.7, ageMonths: e.6, size: e.8, source: e.9,
                countryCode: e.2, city: e.3, story: e.5, contactEmail: "adopt@example.com", vaccinated: true,
                neutered: index != 2, status: .available, createdAt: Date().addingTimeInterval(Double(-index) * 3600),
                likesCount: [28, 16, 42, 12, 19, 8][index], liked: false,
                photos: [AnimalPhoto(id: "sample-\(e.4)", url: "asset:\(e.4)")])
        }
        return Snapshot(users: [regular, admin], posts: posts, reports: [], activeUserID: regular.id, likedPostIDs: [:])
    }
    private func personalized(_ original: AdoptionPost) -> AdoptionPost {
        var post = original; post.liked = state.likedPostIDs[user.id]?.contains(post.id) ?? false; return post
    }
}
