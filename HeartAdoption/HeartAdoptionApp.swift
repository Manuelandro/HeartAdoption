import SwiftUI

@main struct HeartAdoptionApp: App {
    @State private var store = AdoptionStore()
    var body: some Scene {
        WindowGroup {
            RootView().environment(store).tint(HATheme.blue).task { await store.bootstrap() }
        }
    }
}

struct RootView: View {
    @Environment(AdoptionStore.self) private var store
    @State private var selectedTab = 0
    @State private var showCreate = false
    @State private var linkedPost: AdoptionPost?
    var body: some View {
        @Bindable var store = store
        TabView(selection: $selectedTab) {
            NavigationStack { DiscoverView(showCreate: $showCreate) }.tabItem { Label("Discover", systemImage: "pawprint.fill") }.tag(0)
            NavigationStack { CountriesView() }.tabItem { Label("Countries", systemImage: "globe.europe.africa") }.tag(1)
            NavigationStack { PostFeedView(query: FeedQuery(scope: .liked), title: "Your likes", emptyTitle: "Keep them close", emptyMessage: "Tap the heart on an animal’s post to find them here.") }.tabItem { Label("Liked", systemImage: "heart") }.tag(2)
            NavigationStack { ProfileView() }.tabItem { Label("You", systemImage: "person.crop.circle") }.tag(3)
        }
        .sheet(isPresented: $showCreate) { PostEditorView() }
        .sheet(isPresented: $store.showAuthentication) { AuthenticationView() }
        .sheet(item: $linkedPost) { post in NavigationStack { PostDetailView(initialPost: post).toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { linkedPost = nil } } } } }
        .alert("Couldn’t finish that", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) { Button("OK") { store.errorMessage = nil } } message: { Text(store.errorMessage ?? "") }
        .onOpenURL { url in
            guard url.scheme == "heartadoption" else { return }
            if url.host == "post", let id = url.pathComponents.dropFirst().first {
                Task { do { linkedPost = try await store.post(id) } catch { store.errorMessage = error.localizedDescription } }
            } else if url.host == "invite" { selectedTab = 3; if !store.isDemo && store.user == nil { store.showAuthentication = true } }
        }
    }
}
