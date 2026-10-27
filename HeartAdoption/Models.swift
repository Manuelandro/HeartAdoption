import Foundation

struct Country: Codable, Identifiable, Hashable {
    let code: String
    let name: String
    var postCount: Int = 0
    var followerCount: Int = 0
    var isFollowing: Bool = false
    var id: String { code }
    var flag: String { String(String.UnicodeScalarView(code.unicodeScalars.compactMap { UnicodeScalar(127397 + $0.value) })) }

    enum CodingKeys: String, CodingKey { case code, name, postCount, followerCount, isFollowing }
    init(code: String, name: String, postCount: Int = 0, followerCount: Int = 0, isFollowing: Bool = false) {
        self.code = code; self.name = name; self.postCount = postCount; self.followerCount = followerCount; self.isFollowing = isFollowing
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        code = try c.decode(String.self, forKey: .code); name = try c.decode(String.self, forKey: .name)
        postCount = try c.decodeIfPresent(Int.self, forKey: .postCount) ?? 0
        followerCount = try c.decodeIfPresent(Int.self, forKey: .followerCount) ?? 0
        isFollowing = try c.decodeIfPresent(Bool.self, forKey: .isFollowing) ?? false
    }
    static var all: [Country] {
        guard let url = Bundle.main.url(forResource: "countries", withExtension: "json"),
              let data = try? Data(contentsOf: url), let countries = try? JSONDecoder().decode([Country].self, from: data) else { return [] }
        return countries
    }
}

struct AppUser: Codable, Equatable, Identifiable {
    let id: String
    var name: String
    var email: String
    var homeCountry: String
    var adminCountries: [String]
    var followedCountries: [String]
    var isAdmin: Bool { !adminCountries.isEmpty }
}

enum Species: String, Codable, CaseIterable, Identifiable {
    case dog, cat
    var id: String { rawValue }
    var title: String { self == .dog ? "Dogs" : "Cats" }
    var symbol: String { self == .dog ? "dog" : "cat" }
}
enum AnimalSex: String, Codable, CaseIterable { case female, male, unknown }
enum AnimalSize: String, Codable, CaseIterable { case small, medium, large }
enum AnimalSource: String, Codable, CaseIterable {
    case shelter, street, family
    var title: String {
        switch self { case .shelter: "In a shelter"; case .street: "Street rescue"; case .family: "With a family" }
    }
}
enum PostStatus: String, Codable, CaseIterable { case available, adopted, hidden }

struct AnimalPhoto: Codable, Identifiable, Hashable {
    let id: String
    let url: String
}

struct AdoptionPost: Codable, Identifiable, Hashable {
    let id: String
    let authorID: String
    var authorName: String
    var name: String
    var species: Species
    var sex: AnimalSex
    var ageMonths: Int
    var size: AnimalSize
    var source: AnimalSource
    var countryCode: String
    var city: String
    var story: String
    var contactEmail: String
    var vaccinated: Bool
    var neutered: Bool
    var status: PostStatus
    var createdAt: Date
    var likesCount: Int
    var liked: Bool
    var photos: [AnimalPhoto]

    var age: String {
        if ageMonths == 0 { return "Under 1 month" }
        if ageMonths < 12 { return "\(ageMonths) \(ageMonths == 1 ? "month" : "months")" }
        let years = ageMonths / 12
        return "\(years)\(ageMonths % 12 >= 6 ? "½" : "") \(years == 1 && ageMonths % 12 < 6 ? "year" : "years")"
    }
    var summary: String { "\(age) • \(sex.rawValue.capitalized) • \(size.rawValue.capitalized)" }
}

struct PostDraft: Encodable {
    var name = ""
    var species: Species = .dog
    var sex: AnimalSex = .unknown
    var ageMonths = 12
    var size: AnimalSize = .medium
    var source: AnimalSource = .shelter
    var countryCode = "IT"
    var city = ""
    var story = ""
    var contactEmail = ""
    var vaccinated = false
    var neutered = false
    var status: PostStatus? = nil
    var photos: [String]? = nil

    init() {}
    init(post: AdoptionPost) {
        name = post.name; species = post.species; sex = post.sex; ageMonths = post.ageMonths; size = post.size
        source = post.source; countryCode = post.countryCode; city = post.city; story = post.story
        contactEmail = post.contactEmail; vaccinated = post.vaccinated; neutered = post.neutered; status = post.status
    }
    var validationMessage: String? {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Add the animal’s name." }
        if name.count > 80 { return "Keep the name under 80 characters." }
        if city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Add the city where the animal is." }
        if city.count > 100 { return "Keep the city under 100 characters." }
        if story.trimmingCharacters(in: .whitespacesAndNewlines).count < 20 { return "Tell adopters a little more (at least 20 characters)." }
        if story.count > 6000 { return "Keep the story under 6,000 characters." }
        if !contactEmail.contains("@") || !contactEmail.contains(".") { return "Add a valid contact email." }
        if !(0...360).contains(ageMonths) { return "Age must be between 0 and 360 months." }
        return nil
    }
}

enum FeedScope: String, CaseIterable { case home, following, all, country, liked, mine }
struct FeedQuery: Equatable {
    var scope: FeedScope = .home
    var country: String? = nil
    var species: Species? = nil
    var search = ""
}
struct PostPage: Decodable { let posts: [AdoptionPost]; let nextCursor: String? }
struct AuthResponse: Decodable { let token: String; let user: AppUser }
struct PostReport: Codable, Identifiable {
    let id: String; let postID: String; let reason: String; let createdAt: Date
    var postName: String? = nil
    var countryCode: String? = nil
}
struct ModerationPage: Codable { var posts: [AdoptionPost]; var reports: [PostReport]; var nextCursor: String? = nil }

enum AppFailure: LocalizedError {
    case message(String)
    case server(status: Int, message: String)
    var errorDescription: String? {
        switch self { case .message(let value), .server(_, let value): return value }
    }
}

enum AppJSON {
    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            let fractional = ISO8601DateFormatter(); fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: text) ?? ISO8601DateFormatter().date(from: text) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid date: \(text)"))
        }
        return decoder
    }
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; return encoder
    }
}
