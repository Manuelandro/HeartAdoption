import SwiftUI

struct CountriesView: View {
    @Environment(AdoptionStore.self) private var store
    @State private var search = ""
    @State private var followingOnly = false
    private var filtered: [Country] {
        store.countries.filter { country in
            (!followingOnly || country.isFollowing) && (search.isEmpty || country.name.localizedCaseInsensitiveContains(search) || country.code.localizedCaseInsensitiveContains(search))
        }.sorted { a, b in
            if search.isEmpty, a.postCount != b.postCount { return a.postCount > b.postCount }
            return a.name < b.name
        }
    }
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Care has\nno borders.").font(HATheme.title(34)).tracking(-0.9).foregroundStyle(HATheme.ink)
                    Text("Follow a country to keep up with the animals who need a home there.").font(.subheadline).foregroundStyle(.secondary)
                }.padding(.vertical, 12).listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 12, trailing: 0))
                Picker("Country groups", selection: $followingOnly) { Text("All countries").tag(false); Text("Following").tag(true) }.pickerStyle(.segmented).listRowBackground(Color.clear).listRowInsets(EdgeInsets())
            }
            Section {
                ForEach(filtered) { country in
                    HStack(spacing: 14) {
                        NavigationLink { CountryGroupView(code: country.code) } label: {
                            HStack(spacing: 14) {
                                Text(country.flag).font(.system(size: 31)).frame(width: 48, height: 52).background(HATheme.paleBlue, in: .rect(cornerRadius: 15))
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(country.name).font(.headline).foregroundStyle(HATheme.ink)
                                    Text("\(country.postCount) \(country.postCount == 1 ? "animal" : "animals") looking for a home").font(.caption).foregroundStyle(.secondary)
                                }
                            }.padding(.vertical, 4)
                        }
                    }
                }
                if filtered.isEmpty { EmptyState(title: "No countries here", message: followingOnly ? "Open a country group and tap Follow to add it here." : "Try another country name.", symbol: "globe") }
            }
        }.navigationTitle("Countries").searchable(text: $search, prompt: "Find a country")
    }
}

struct CountryGroupView: View {
    @Environment(AdoptionStore.self) private var store
    let code: String
    @State private var working = false
    private var country: Country { store.country(code) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top, spacing: 18) {
                    Text(country.flag).font(.system(size: 46)).frame(width: 78, height: 86).background(HATheme.paleBlue, in: .rect(cornerRadius: 25))
                    VStack(alignment: .leading, spacing: 10) {
                        Text(country.name).font(HATheme.title(30)).foregroundStyle(HATheme.ink)
                        Text("\(country.postCount) animals • \(country.followerCount) followers").font(.subheadline).foregroundStyle(.secondary)
                        Button {
                            guard store.requireUser() else { return }
                            working = true
                            Task { do { try await store.follow(code) } catch { store.errorMessage = error.localizedDescription }; working = false }
                        } label: {
                            Label(country.isFollowing ? "Following" : "Follow country", systemImage: country.isFollowing ? "checkmark" : "plus").font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 16).padding(.vertical, 10).foregroundStyle(country.isFollowing ? HATheme.blue : .white)
                                .background(country.isFollowing ? HATheme.paleBlue : HATheme.blue, in: .capsule)
                        }.disabled(working).accessibilityIdentifier("followCountry")
                    }
                    Spacer(minLength: 0)
                }
                Text("Find a friend in \(country.name)").font(.headline).foregroundStyle(HATheme.ink)
                FeedContent(query: FeedQuery(scope: .country, country: code), emptyTitle: "The first hello is yours", emptyMessage: "Animals posted in \(country.name) will appear in this group.")
            }.padding(20).frame(maxWidth: 650).frame(maxWidth: .infinity)
        }.background(HATheme.background).navigationTitle(country.name).navigationBarTitleDisplayMode(.inline)
    }
}
