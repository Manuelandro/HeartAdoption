import SwiftUI

struct PostDetailView: View {
    @Environment(AdoptionStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let initialPost: AdoptionPost
    @State private var selectedPhoto = 0
    @State private var showEditor = false
    @State private var showReport = false
    @State private var showDelete = false
    @State private var working = false
    private var post: AdoptionPost { store.postsByID[initialPost.id] ?? initialPost }
    private var isOwner: Bool { post.authorID == store.user?.id }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                TabView(selection: $selectedPhoto) {
                    ForEach(Array(post.photos.enumerated()), id: \.element.id) { index, photo in AnimalImage(photo: photo).tag(index) }
                }.tabViewStyle(.page(indexDisplayMode: post.photos.count > 1 ? .always : .never)).frame(height: 365).clipShape(.rect(cornerRadius: 28))
                    .overlay(alignment: .topLeading) {
                        if post.status != .available { Text(post.status.rawValue.capitalized).font(.headline).padding(12).background(.regularMaterial, in: .capsule).padding(16) }
                    }
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(post.name).font(HATheme.title(40)).foregroundStyle(HATheme.ink)
                        Spacer()
                        Button { Task { do { try await store.like(post.id) } catch { store.errorMessage = error.localizedDescription } } } label: {
                            Image(systemName: post.liked ? "heart.fill" : "heart").font(.title2).padding(15).background(HATheme.paleBlue, in: .circle)
                        }.accessibilityLabel("\(post.liked ? "Unlike" : "Like") \(post.name)").disabled(store.workingLikes.contains(post.id) || post.status != .available)
                    }
                    Label("\(post.city), \(store.country(post.countryCode).name)", systemImage: "mappin.and.ellipse").font(.subheadline).foregroundStyle(HATheme.muted)
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 10) { fact(post.age, label: "Age"); fact(post.sex.rawValue.capitalized, label: "Sex"); fact(post.size.rawValue.capitalized, label: "Size") }
                        VStack(spacing: 10) { fact(post.age, label: "Age"); fact(post.sex.rawValue.capitalized, label: "Sex"); fact(post.size.rawValue.capitalized, label: "Size") }
                    }.padding(.top, 8)
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text("A little about \(post.name)").font(HATheme.title(23)).foregroundStyle(HATheme.ink)
                    Text(post.story).font(.body).lineSpacing(5).foregroundStyle(HATheme.ink.opacity(0.9)).textSelection(.enabled)
                    HStack(spacing: 14) {
                        if post.vaccinated { Label("Vaccinated", systemImage: "cross.case").font(.caption) }
                        if post.neutered { Label("Neutered", systemImage: "checkmark.seal").font(.caption) }
                    }.foregroundStyle(HATheme.blue).padding(.top, 4)
                }
                HStack(spacing: 12) {
                    Image(systemName: post.source == .shelter ? "house" : "hands.sparkles").font(.title2).foregroundStyle(HATheme.blue).frame(width: 48, height: 48).background(HATheme.paleBlue, in: .circle)
                    VStack(alignment: .leading, spacing: 4) { Text("Cared for by").font(.caption).foregroundStyle(.secondary); Text(post.authorName).font(.headline) }
                    Spacer()
                }.padding(16).background(.background, in: .rect(cornerRadius: 19))
                if store.isDemo { Text("This is a sample animal. Contact and sharing are included so you can explore the app.").font(.caption).foregroundStyle(.secondary) }
                if isOwner {
                    Button("Edit adoption post") { showEditor = true }.buttonStyle(.bordered).frame(maxWidth: .infinity)
                    Button("Delete post", role: .destructive) { showDelete = true }.frame(maxWidth: .infinity).font(.subheadline)
                }
                if !isOwner { Button("Report this post") { if store.requireUser() { showReport = true } }.font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity) }
            }.padding(20).padding(.bottom, 12).frame(maxWidth: 650).frame(maxWidth: .infinity)
        }
        .background(HATheme.background).navigationTitle("Meet \(post.name)").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { ShareLink(item: store.shareText(for: post)) { Image(systemName: "square.and.arrow.up") }.accessibilityLabel("Share \(post.name)") } }
        .safeAreaInset(edge: .bottom) {
            if post.status == .available {
                Group {
                    if store.isDemo {
                        Button { store.errorMessage = "This is a sample animal. Connect to your server to contact real shelters and rescuers." } label: { Label("Ask about \(post.name)", systemImage: "envelope") }
                    } else {
                        Link(destination: contactURL) { Label("Ask about \(post.name)", systemImage: "envelope") }
                    }
                }.buttonStyle(PrimaryButtonStyle()).padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 8).background(.bar)
            }
        }
        .sheet(isPresented: $showEditor) { PostEditorView(editing: post) }
        .sheet(isPresented: $showReport) { ReportView(post: post) }
        .confirmationDialog("Delete \(post.name)’s post? This also removes its photos and likes.", isPresented: $showDelete, titleVisibility: .visible) {
            Button("Delete post", role: .destructive) { Task { do { try await store.delete(post.id); dismiss() } catch { store.errorMessage = error.localizedDescription } } }
        }
    }
    private var contactURL: URL {
        var parts = URLComponents(); parts.scheme = "mailto"; parts.path = post.contactEmail
        parts.queryItems = [.init(name: "subject", value: "Adopting \(post.name) · Heart Adoption"), .init(name: "body", value: "Hello, I saw \(post.name)’s adoption post on Heart Adoption and would love to learn more.")]
        return parts.url ?? URL(string: "mailto:")!
    }
    private func fact(_ value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 5) { Text(label).font(.caption).foregroundStyle(HATheme.muted); Text(value).font(.subheadline.weight(.semibold)).foregroundStyle(HATheme.ink) }
            .frame(maxWidth: .infinity, alignment: .leading).padding(14).background(HATheme.paleBlue, in: .rect(cornerRadius: 17))
    }
}

struct ReportView: View {
    @Environment(AdoptionStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let post: AdoptionPost
    @State private var reason = ""
    @State private var working = false
    @State private var error: String?
    @State private var sent = false
    var body: some View {
        NavigationStack {
            Form {
                if sent {
                    Section { Label("Report sent", systemImage: "checkmark.circle"); Text("A country administrator can now review this post.") }
                } else {
                    Section("What should the administrator know?") { TextField("Describe the problem", text: $reason, axis: .vertical).lineLimit(5...10) }
                    if let error { Text(error).foregroundStyle(.red) }
                    Section { Button(working ? "Sending…" : "Send report") {
                        working = true
                        Task { do { try await store.report(post.id, reason: reason); sent = true } catch { self.error = error.localizedDescription }; working = false }
                    }.disabled(working || reason.trimmingCharacters(in: .whitespacesAndNewlines).count < 5 || reason.count > 1000) }
                }
            }.navigationTitle("Report \(post.name)’s post").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(sent ? "Done" : "Cancel") { dismiss() } } }
        }
    }
}
