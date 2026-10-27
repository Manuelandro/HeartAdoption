import SwiftUI

struct DiscoverView: View {
    @Environment(AdoptionStore.self) private var store
    @Binding var showCreate: Bool
    @State private var scope: FeedScope = .home
    @State private var species: Species?
    @State private var search = ""
    var body: some View {
        VStack(spacing: 0) {
            if store.isDemo { PreviewBanner() }
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Good homes\nstart here.").font(HATheme.title(38)).tracking(-1.3).foregroundStyle(HATheme.ink).fixedSize(horizontal: false, vertical: true)
                            Text("A small hello. A whole new life.").font(.subheadline).foregroundStyle(HATheme.muted)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "heart.fill").font(.system(size: 31)).foregroundStyle(HATheme.blue)
                            .frame(width: 65, height: 65).background(HATheme.yellow, in: .rect(cornerRadius: 23)).rotationEffect(.degrees(8)).accessibilityHidden(true)
                    }.padding(.top, 8)
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").foregroundStyle(HATheme.muted)
                        TextField("Search animals, cities, stories", text: $search).font(.subheadline).autocorrectionDisabled().accessibilityIdentifier("discoverSearch")
                        if !search.isEmpty { Button { search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.accessibilityLabel("Clear search") }
                    }.padding(14).background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 15))
                    VStack(alignment: .leading, spacing: 18) {
                        if search.isEmpty {
                            Picker("Feed", selection: $scope) {
                                Text(store.country(store.user?.homeCountry ?? "IT").flag + " Near you").tag(FeedScope.home)
                                Text("Following").tag(FeedScope.following)
                                Text("Everywhere").tag(FeedScope.all)
                            }.pickerStyle(.segmented).accessibilityIdentifier("feedScope")
                        } else { Label("Searching across all countries", systemImage: "globe").font(.caption).foregroundStyle(HATheme.muted) }
                        HStack(spacing: 10) {
                            speciesChip("All friends", symbol: "pawprint", value: nil)
                            ForEach(Species.allCases) { item in speciesChip(item.title, symbol: item.symbol, value: item) }
                        }
                    }
                    FeedContent(query: FeedQuery(scope: search.isEmpty ? scope : .all, species: species, search: search.trimmingCharacters(in: .whitespacesAndNewlines)),
                        emptyTitle: "A little quiet here",
                        emptyMessage: scope == .following && search.isEmpty ? "Follow a country from the Countries tab to see its animals here." : "Try another search or explore animals in other countries.")
                }.padding(.horizontal, 20).padding(.bottom, 24).frame(maxWidth: 650).frame(maxWidth: .infinity)
            }
        }
        .background(HATheme.background).navigationTitle("Heart Adoption").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { Image(systemName: "heart.circle.fill").foregroundStyle(HATheme.blue).accessibilityHidden(true) }
            ToolbarItem(placement: .topBarTrailing) {
                Button { if store.requireUser() { showCreate = true } } label: { Image(systemName: "plus").fontWeight(.semibold) }
                    .accessibilityLabel("Create adoption post").accessibilityIdentifier("createPost")
            }
        }
    }
    private func speciesChip(_ title: String, symbol: String, value: Species?) -> some View {
        Button { species = value } label: {
            Label(title, systemImage: symbol).font(.subheadline.weight(.semibold)).padding(.horizontal, 13).padding(.vertical, 11)
                .foregroundStyle(species == value ? .white : HATheme.ink)
                .background(species == value ? HATheme.blue : Color(uiColor: .secondarySystemGroupedBackground), in: .capsule)
        }.buttonStyle(.plain).accessibilityAddTraits(species == value ? .isSelected : [])
    }
}

struct PostFeedView: View {
    let query: FeedQuery
    let title: String
    var emptyTitle = "No animals here yet"
    var emptyMessage = "New adoption posts will appear here."
    var body: some View {
        ScrollView {
            FeedContent(query: query, emptyTitle: emptyTitle, emptyMessage: emptyMessage)
                .padding(20).frame(maxWidth: 650).frame(maxWidth: .infinity)
        }.background(HATheme.background).navigationTitle(title)
    }
}

struct FeedContent: View {
    @Environment(AdoptionStore.self) private var store
    let query: FeedQuery
    let emptyTitle: String
    let emptyMessage: String
    @State private var posts: [AdoptionPost] = []
    @State private var cursor: String?
    @State private var loading = true
    @State private var loadingMore = false
    @State private var error: String?
    private var taskKey: String { "\(query.scope.rawValue)-\(query.country ?? "")-\(query.species?.rawValue ?? "")-\(query.search)-\(store.revision)" }
    var body: some View {
        LazyVStack(alignment: .leading, spacing: 22) {
            if let error {
                VStack(alignment: .leading, spacing: 12) {
                    Label("The feed couldn’t load", systemImage: "wifi.exclamationmark").font(.headline)
                    Text(error).font(.subheadline).foregroundStyle(.secondary)
                    Button("Try again") { Task { await load() } }.buttonStyle(.bordered)
                }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(.background, in: .rect(cornerRadius: 18))
            } else if loading && posts.isEmpty { ProgressView("Finding friends…").frame(maxWidth: .infinity).padding(.vertical, 60) }
            else if posts.isEmpty { EmptyState(title: emptyTitle, message: emptyMessage, symbol: query.scope == .liked ? "heart" : "pawprint") }
            else {
                ForEach(posts) { initial in
                    AnimalCard(post: store.postsByID[initial.id] ?? initial)
                }
                if cursor != nil {
                    Button { Task { await loadMore() } } label: {
                        if loadingMore { ProgressView() } else { Text("More animals").font(.headline) }
                    }.frame(maxWidth: .infinity).padding().disabled(loadingMore)
                }
            }
        }
        .task(id: taskKey) {
            if !query.search.isEmpty { do { try await Task.sleep(for: .milliseconds(300)) } catch { return } }
            await load()
        }
        .refreshable { await load() }
    }
    private func load() async {
        loading = true; error = nil
        do {
            let page = try await store.feed(query)
            guard !Task.isCancelled else { return }
            posts = page.posts; cursor = page.nextCursor; loading = false
        } catch { if !Task.isCancelled { self.error = error.localizedDescription; loading = false } }
    }
    private func loadMore() async {
        guard let cursor, !loadingMore else { return }
        loadingMore = true; defer { loadingMore = false }
        do {
            let page = try await store.feed(query, cursor: cursor)
            posts.append(contentsOf: page.posts.filter { new in !posts.contains { $0.id == new.id } }); self.cursor = page.nextCursor
        } catch { store.errorMessage = error.localizedDescription }
    }
}

struct AnimalCard: View {
    @Environment(AdoptionStore.self) private var store
    let post: AdoptionPost
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            NavigationLink { PostDetailView(initialPost: post) } label: {
                AnimalImage(photo: post.photos.first).frame(height: 280).contentShape(.rect)
                    .overlay(alignment: .topLeading) {
                        Text(post.status == .available ? post.source.title : post.status.rawValue.capitalized)
                            .font(.caption.weight(.semibold)).padding(.horizontal, 12).padding(.vertical, 8)
                            .background(.regularMaterial, in: .capsule).padding(16).foregroundStyle(HATheme.ink)
                    }
            }.buttonStyle(.plain).accessibilityLabel("Meet \(post.name), \(post.species.rawValue), in \(post.city)")
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center) {
                    NavigationLink { PostDetailView(initialPost: post) } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(post.name).font(HATheme.title(28)).foregroundStyle(HATheme.ink)
                            Text(post.summary).font(.subheadline).foregroundStyle(HATheme.muted)
                        }.frame(maxWidth: .infinity, alignment: .leading).contentShape(.rect)
                    }.buttonStyle(.plain)
                    Button { Task { do { try await store.like(post.id) } catch { store.errorMessage = error.localizedDescription } } } label: {
                        VStack(spacing: 4) {
                            Image(systemName: post.liked ? "heart.fill" : "heart").font(.system(size: 23))
                            Text("\(post.likesCount)").font(.caption2.weight(.medium))
                        }.foregroundStyle(post.liked ? HATheme.blue : HATheme.muted).frame(minWidth: 44, minHeight: 48)
                    }.disabled(store.workingLikes.contains(post.id) || post.status != .available).accessibilityLabel("\(post.liked ? "Unlike" : "Like") \(post.name)").accessibilityValue("\(post.likesCount) likes").accessibilityIdentifier("like-\(post.name)")
                }
                HStack(spacing: 6) {
                    Image(systemName: "mappin.and.ellipse").font(.caption)
                    Text("\(post.city), \(store.country(post.countryCode).name)").font(.caption.weight(.medium))
                    Spacer()
                    PostShareLink(post: post).font(.subheadline).frame(width: 36, height: 30)
                }.foregroundStyle(HATheme.muted)
            }.padding(.horizontal, 18).padding(.vertical, 15)
        }.background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 25))
            .clipShape(.rect(cornerRadius: 25))
    }
}
