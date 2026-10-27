import SwiftUI

struct ProfileView: View {
    @Environment(AdoptionStore.self) private var store
    @State private var showConnection = false
    @State private var showProfile = false
    @State private var showDelete = false
    var body: some View {
        List {
            if let user = store.user {
                Section {
                    HStack(spacing: 16) {
                        Text(String(user.name.prefix(1))).font(HATheme.title(32)).foregroundStyle(HATheme.blue).frame(width: 70, height: 70).background(HATheme.paleBlue, in: .circle)
                        VStack(alignment: .leading, spacing: 6) { Text(user.name).font(HATheme.title(27)).foregroundStyle(HATheme.ink); Text("\(store.country(user.homeCountry).flag) \(store.country(user.homeCountry).name)").font(.subheadline).foregroundStyle(.secondary) }
                    }.padding(.vertical, 12)
                    Button("Edit profile & home country") { showProfile = true }
                }
                Section {
                    NavigationLink { PostFeedView(query: FeedQuery(scope: .mine), title: "Your adoption posts", emptyTitle: "Someone needs your help", emptyMessage: "Create an adoption post from the Discover tab. Your posts and adoption updates will appear here.") } label: { Label("Your adoption posts", systemImage: "pawprint") }
                    NavigationLink { CountriesView() } label: { Label("Followed countries", systemImage: "globe.europe.africa") }
                    ShareLink(item: store.invitation) { Label("Invite a friend", systemImage: "person.badge.plus") }.accessibilityIdentifier("inviteFriend")
                }
                if user.isAdmin {
                    Section {
                        NavigationLink { ModerationView() } label: { Label("Country administration", systemImage: "checkmark.shield") }.accessibilityIdentifier("administration")
                        Text("Administrator for \(user.adminCountries.map { store.country($0).name }.joined(separator: ", ")).").font(.caption).foregroundStyle(.secondary)
                    }
                }
            } else {
                Section {
                    EmptyState(title: "Be part of their next chapter", message: "Create an account to post animals, like their stories, and follow countries.", symbol: "heart")
                    Button("Sign in or create an account") { store.showAuthentication = true }.font(.headline)
                }
            }
            Section {
                if store.isDemo {
                    Label("App preview", systemImage: "sparkle").foregroundStyle(HATheme.blue)
                    Text("These are sample animals and local accounts. Connect to your server for real adoption posts.").font(.subheadline).foregroundStyle(.secondary)
                    Picker("Sample account", selection: Binding(get: { store.user?.id ?? "" }, set: { id in do { try store.switchDemoUser(id) } catch { store.errorMessage = error.localizedDescription } })) {
                        ForEach(store.demoUsers) { user in Text("\(user.name) · \(user.isAdmin ? "Administrator" : "Regular user")").tag(user.id) }
                    }.accessibilityIdentifier("sampleAccount")
                } else if let server = store.serverURL {
                    LabeledContent("Connected server", value: server.host ?? "").font(.caption)
                }
                Button(store.isDemo ? "Connect to a server" : "Change server") { showConnection = true }.accessibilityIdentifier("connectServer")
                if !store.isDemo {
                    Button("Explore the app preview") { store.useDemo() }
                    if store.user != nil {
                        Button("Sign out") { Task { do { try await store.signOut() } catch { store.errorMessage = error.localizedDescription } } }
                        Button("Delete account", role: .destructive) { showDelete = true }
                    }
                }
            }
            Section { Text("Heart Adoption\nA home changes everything.").font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity).multilineTextAlignment(.center).padding(.vertical, 12) }.listRowBackground(Color.clear)
        }.navigationTitle("Your corner")
            .sheet(isPresented: $showConnection) { ServerConnectionView() }
            .sheet(isPresented: $showProfile) { EditProfileView() }
            .sheet(isPresented: $showDelete) { DeleteAccountView() }
    }
}

struct AuthenticationView: View {
    @Environment(AdoptionStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var registering = false
    @State private var email = ""
    @State private var password = ""
    @State private var name = ""
    @State private var country = "IT"
    @State private var showCountry = false
    @State private var showConnection = false
    @State private var working = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 12) { Image(systemName: "heart.fill").foregroundStyle(HATheme.blue).font(.largeTitle); Text(registering ? "Every home\nstarts with someone." : "Welcome back.").font(HATheme.title(31)).foregroundStyle(HATheme.ink); Text("Help dogs and cats find their people.").foregroundStyle(.secondary).font(.subheadline) }.padding(.vertical, 10)
                }.listRowBackground(Color.clear)
                if store.isDemo { Section { Text("Connect to a server to create your account."); Button("Connect to a server") { showConnection = true } } }
                else {
                    Section {
                        if registering { TextField("Your name or shelter name", text: $name).textContentType(.name).accessibilityIdentifier("authName") }
                        TextField("Email", text: $email).keyboardType(.emailAddress).textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("authEmail")
                        SecureField("Password (10 or more characters)", text: $password).textContentType(registering ? .newPassword : .password).accessibilityIdentifier("authPassword")
                        if registering { Button { showCountry = true } label: { LabeledContent("Home country", value: "\(store.country(country).flag) \(store.country(country).name)") } }
                    }
                    if let error { Section { Text(error).font(.subheadline).foregroundStyle(.red) } }
                    Section {
                        Button(working ? "Please wait…" : registering ? "Create account" : "Sign in") {
                            working = true; error = nil
                            Task {
                                do { try await store.authenticate(email: email.trimmingCharacters(in: .whitespacesAndNewlines), password: password, name: registering ? name : nil, country: country); dismiss() }
                                catch { self.error = error.localizedDescription }
                                working = false
                            }
                        }.font(.headline).disabled(working || email.isEmpty || password.count < 10 || (registering && name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)).accessibilityIdentifier("authSubmit")
                        Button(registering ? "Already have an account? Sign in" : "New here? Create an account") { registering.toggle(); error = nil }
                    }
                }
            }.navigationTitle(registering ? "Create account" : "Sign in").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() }.disabled(working) } }
                .sheet(isPresented: $showCountry) { CountryPicker(selection: $country) }
                .sheet(isPresented: $showConnection) { ServerConnectionView() }
        }.interactiveDismissDisabled(working)
    }
}

struct ServerConnectionView: View {
    @Environment(AdoptionStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var address = ""
    @State private var working = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section { TextField("https://api.your-shelter.org", text: $address).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("serverAddress") } header: { Text("Server address") } footer: { Text("Use the address provided by the app’s administrator.") }
                if let error { Section { Text(error).foregroundStyle(.red).font(.subheadline) } }
                Section { Button(working ? "Connecting…" : "Connect") {
                    working = true; error = nil
                    Task { do { try await store.connect(to: address); dismiss() } catch { self.error = error.localizedDescription }; working = false }
                }.disabled(working || address.isEmpty).accessibilityIdentifier("connectConfirm") }
            }.navigationTitle("Connect to your community").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(working) } }
                .onAppear { address = store.serverURL?.absoluteString ?? "" }
        }.interactiveDismissDisabled(working)
    }
}

struct EditProfileView: View {
    @Environment(AdoptionStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var country = "IT"
    @State private var showCountry = false
    @State private var working = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section { TextField("Your name or shelter name", text: $name); Button { showCountry = true } label: { LabeledContent("Home country", value: "\(store.country(country).flag) \(store.country(country).name)") } } footer: { Text("Your Discover feed starts with animals in your home country. You can follow other countries too.") }
                if let error { Text(error).foregroundStyle(.red) }
            }.navigationTitle("Edit profile").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button(working ? "Saving…" : "Save") { working = true; Task { do { try await store.updateProfile(name: name, country: country); dismiss() } catch { self.error = error.localizedDescription }; working = false } }.disabled(working || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
                }.onAppear { name = store.user?.name ?? ""; country = store.user?.homeCountry ?? "IT" }.sheet(isPresented: $showCountry) { CountryPicker(selection: $country) }
        }
    }
}

struct DeleteAccountView: View {
    @Environment(AdoptionStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var working = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section { Text("Deleting your account permanently removes your adoption posts, photos, likes, and country follows."); SecureField("Current password", text: $password).textContentType(.password) }
                if let error { Text(error).foregroundStyle(.red) }
                Button(working ? "Deleting…" : "Permanently delete account", role: .destructive) { working = true; Task { do { try await store.deleteAccount(password: password); dismiss() } catch { self.error = error.localizedDescription }; working = false } }.disabled(working || password.isEmpty)
            }.navigationTitle("Delete account").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(working) } }
        }.interactiveDismissDisabled(working)
    }
}
