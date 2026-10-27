import SwiftUI

enum HATheme {
    static let blue = Color(red: 34/255, green: 77/255, blue: 199/255)
    static let ink = Color(red: 20/255, green: 45/255, blue: 79/255)
    static let muted = Color(red: 82/255, green: 102/255, blue: 129/255)
    static let background = Color(uiColor: .systemGroupedBackground)
    static let paleBlue = Color(red: 237/255, green: 243/255, blue: 1)
    static let yellow = Color(red: 246/255, green: 200/255, blue: 91/255)
    static func title(_ size: CGFloat) -> Font { .system(size: size, weight: .bold, design: .rounded) }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline).frame(maxWidth: .infinity).padding(.vertical, 17)
            .foregroundStyle(.white).background(HATheme.blue.opacity(configuration.isPressed ? 0.75 : 1), in: .rect(cornerRadius: 17))
    }
}

struct EmptyState: View {
    let title: String
    let message: String
    var symbol = "pawprint"
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 36, weight: .light)).foregroundStyle(HATheme.blue).padding(.bottom, 4)
            Text(title).font(HATheme.title(23)).foregroundStyle(HATheme.ink)
            Text(message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 300)
        }.frame(maxWidth: .infinity).padding(.vertical, 55).padding(.horizontal, 24)
    }
}

@MainActor private enum PhotoCache {
    static let images: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>(); cache.totalCostLimit = 50 * 1024 * 1024; return cache
    }()
}

struct AnimalImage: View {
    @Environment(AdoptionStore.self) private var store
    let photo: AnimalPhoto?
    var contentMode: ContentMode = .fill
    @State private var image: UIImage?
    @State private var failed = false
    var body: some View {
        GeometryReader { proxy in
            Group {
                if let image { Image(uiImage: image).resizable().aspectRatio(contentMode: contentMode) }
                else {
                    Rectangle().fill(HATheme.paleBlue).overlay {
                        if failed { Image(systemName: "pawprint").font(.largeTitle).foregroundStyle(HATheme.blue.opacity(0.5)) }
                        else { ProgressView() }
                    }
                }
            }.frame(width: proxy.size.width, height: proxy.size.height).clipped().contentShape(.rect)
        }
        .contentShape(.rect)
        .task(id: photo?.url) {
            image = nil; failed = false
            guard let reference = photo?.url else { failed = true; return }
            if reference.hasPrefix("asset:") { image = UIImage(named: String(reference.dropFirst(6))); failed = image == nil; return }
            if let cached = PhotoCache.images.object(forKey: reference as NSString) { image = cached; return }
            do {
                guard let url = URL(string: reference) else { throw AppFailure.message("Photo unavailable.") }
                let data: Data
                if url.isFileURL { data = try Data(contentsOf: url) }
                else {
                    var request = URLRequest(url: url)
                    // Never send a session to a host other than our configured API.
                    if url.host == store.serverURL?.host, url.port == store.serverURL?.port, url.scheme == store.serverURL?.scheme,
                       let token = store.api?.token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
                    let (received, response) = try await URLSession.shared.data(for: request)
                    guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw AppFailure.message("Photo unavailable.") }
                    data = received
                }
                guard let decoded = UIImage(data: data) else { throw AppFailure.message("Photo unavailable.") }
                PhotoCache.images.setObject(decoded, forKey: reference as NSString, cost: data.count)
                image = decoded
            } catch { if !Task.isCancelled { failed = true } }
        }
        .accessibilityHidden(true)
    }
}

struct CountryPicker: View {
    @Environment(AdoptionStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: String
    @State private var search = ""
    var body: some View {
        NavigationStack {
            List(store.countries.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.code.localizedCaseInsensitiveContains(search) }) { country in
                Button {
                    selection = country.code; dismiss()
                } label: {
                    HStack { Text(country.flag); Text(country.name).foregroundStyle(.primary); Spacer(); if selection == country.code { Image(systemName: "checkmark").foregroundStyle(HATheme.blue) } }
                }
            }.searchable(text: $search, prompt: "Search countries").navigationTitle("Choose a country")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }.tint(HATheme.blue)
    }
}

struct PreviewBanner: View {
    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "sparkle")
            Text("App preview").fontWeight(.semibold)
            Text("Sample animals and accounts")
            Spacer(minLength: 0)
        }.font(.caption).foregroundStyle(HATheme.blue).padding(.horizontal, 20).padding(.vertical, 9).background(HATheme.paleBlue)
            .accessibilityElement(children: .combine)
    }
}

struct PostShareLink: View {
    @Environment(AdoptionStore.self) private var store
    let post: AdoptionPost
    var body: some View {
        Group {
            if let url = store.shareURL(for: post) {
                ShareLink(item: url, subject: Text("Meet \(post.name)"), message: Text(store.shareMessage(for: post))) {
                    Image(systemName: "square.and.arrow.up")
                }
            } else {
                ShareLink(item: store.shareText(for: post)) { Image(systemName: "square.and.arrow.up") }
            }
        }.accessibilityLabel("Share \(post.name)")
    }
}

struct InvitationShareLink: View {
    @Environment(AdoptionStore.self) private var store
    var body: some View {
        Group {
            if let url = store.invitationURL {
                ShareLink(item: url, subject: Text("Join Heart Adoption"), message: Text("Help dogs and cats find their people.")) {
                    Label("Invite a friend", systemImage: "person.badge.plus")
                }
            } else {
                ShareLink(item: store.invitation) { Label("Invite a friend", systemImage: "person.badge.plus") }
            }
        }.accessibilityIdentifier("inviteFriend")
    }
}
