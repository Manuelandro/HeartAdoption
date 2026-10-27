import SwiftUI

struct ModerationView: View {
    @Environment(AdoptionStore.self) private var store
    @State private var page = ModerationPage(posts: [], reports: [])
    @State private var loading = true
    @State private var error: String?
    @State private var working: Set<String> = []
    @State private var loadingMore = false
    @State private var reportedPost: AdoptionPost?
    var body: some View {
        List {
            Section {
                Label("\(store.user?.adminCountries.map { store.country($0).name }.joined(separator: ", ") ?? "")", systemImage: "globe.europe.africa").font(.subheadline)
                Text("Posts appear in their country group immediately. Review reports and hide posts that do not belong.").font(.subheadline).foregroundStyle(.secondary)
            }
            if loading { ProgressView("Loading country posts…") }
            if let error { Section { Text(error).foregroundStyle(.red); Button("Try again") { Task { await load() } } } }
            if !page.reports.isEmpty {
                Section("Reports to review") {
                    ForEach(page.reports) { report in
                        VStack(alignment: .leading, spacing: 12) {
                            Button {
                                Task { do { reportedPost = try await store.post(report.postID) } catch { store.errorMessage = error.localizedDescription } }
                            } label: {
                                Text(report.postName ?? page.posts.first(where: { $0.id == report.postID })?.name ?? "Review adoption post").font(.headline)
                            }.buttonStyle(.borderless)
                            Text(report.reason).font(.subheadline)
                            Button("Dismiss report") { Task { do { try await store.resolve(report.id); await load() } catch { store.errorMessage = error.localizedDescription } } }.font(.caption).buttonStyle(.borderless)
                        }.padding(.vertical, 6)
                    }
                }
            }
            Section("Posts in your countries") {
                ForEach(page.posts) { initial in
                    let post = store.postsByID[initial.id] ?? initial
                    VStack(alignment: .leading, spacing: 12) {
                        NavigationLink { PostDetailView(initialPost: post) } label: {
                            HStack(spacing: 14) {
                                AnimalImage(photo: post.photos.first).frame(width: 66, height: 70).clipShape(.rect(cornerRadius: 14))
                                VStack(alignment: .leading, spacing: 5) { Text(post.name).font(.headline); Text("\(store.country(post.countryCode).name) · \(post.status.rawValue.capitalized)").font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                        HStack {
                            Button(post.status == .hidden ? "Restore post" : "Hide post", role: post.status == .hidden ? nil : .destructive) {
                                working.insert(post.id)
                                Task {
                                    do { try await store.moderate(post.id, status: post.status == .hidden ? .available : .hidden); await load() }
                                    catch { store.errorMessage = error.localizedDescription }
                                    working.remove(post.id)
                                }
                            }.font(.subheadline.weight(.semibold)).buttonStyle(.borderless).disabled(working.contains(post.id)).accessibilityIdentifier("moderate-\(post.name)")
                            Spacer()
                        }
                    }.padding(.vertical, 5)
                }
                if !loading && page.posts.isEmpty { Text("No posts in your assigned countries yet.").foregroundStyle(.secondary) }
                if page.nextCursor != nil {
                    Button(loadingMore ? "Loading…" : "More country posts") { Task { await loadMore() } }.disabled(loadingMore)
                }
            }
        }.navigationTitle("Country administration").navigationBarTitleDisplayMode(.inline).task { await load() }.refreshable { await load() }
            .navigationDestination(item: $reportedPost) { PostDetailView(initialPost: $0) }
    }
    private func load() async {
        error = nil
        do { page = try await store.moderation() } catch { self.error = error.localizedDescription }
        loading = false
    }
    private func loadMore() async {
        guard let cursor = page.nextCursor else { return }
        loadingMore = true; defer { loadingMore = false }
        do {
            let next = try await store.moderation(cursor: cursor)
            page.posts.append(contentsOf: next.posts.filter { post in !page.posts.contains { $0.id == post.id } })
            page.reports = next.reports; page.nextCursor = next.nextCursor
        } catch { store.errorMessage = error.localizedDescription }
    }
}
