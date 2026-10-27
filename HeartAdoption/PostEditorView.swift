import SwiftUI
import PhotosUI

struct PostEditorView: View {
    @Environment(AdoptionStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var editing: AdoptionPost?
    @State private var draft = PostDraft()
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var photos: [Data] = []
    @State private var loadingPhotos = false
    @State private var showCountryPicker = false
    @State private var saving = false
    @State private var error: String?
    @State private var published: AdoptionPost?
    @State private var initialized = false

    var body: some View {
        NavigationStack {
            Group {
                if let published {
                    VStack(spacing: 22) {
                        Image(systemName: "checkmark.heart.fill").font(.system(size: 58)).foregroundStyle(HATheme.blue)
                        Text("A new beginning\nfor \(published.name).").font(HATheme.title(32)).multilineTextAlignment(.center).foregroundStyle(HATheme.ink)
                        Text("\(published.name)’s post is now in the \(store.country(published.countryCode).name) group and can be discovered from any country.").font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        if store.isDemo { Text("Saved in your local app preview.").font(.caption).foregroundStyle(.secondary) }
                        Button("Done") { dismiss() }.buttonStyle(PrimaryButtonStyle())
                    }.padding(30)
                } else {
                    Form {
                        Section {
                            if editing == nil { photoSection }
                            else { Text("Your existing \(editing!.photos.count) photos will stay with this post.").font(.subheadline).foregroundStyle(.secondary) }
                        } header: { Text("Photos") } footer: { if editing == nil { Text("Add 1–6 clear photos. Location information is removed when they are uploaded.") } }
                        Section("Meet your future friend") {
                            TextField("Animal’s name", text: $draft.name).textInputAutocapitalization(.words).accessibilityIdentifier("animalName")
                            Picker("Animal", selection: $draft.species) { ForEach(Species.allCases) { Text($0.rawValue.capitalized).tag($0) } }
                            Picker("Sex", selection: $draft.sex) { ForEach(AnimalSex.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) } }
                            Stepper("Age: \(draft.ageMonths) months", value: $draft.ageMonths, in: 0...360)
                            Picker("Size", selection: $draft.size) { ForEach(AnimalSize.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) } }
                            Picker("Currently", selection: $draft.source) { ForEach(AnimalSource.allCases, id: \.self) { Text($0.title).tag($0) } }
                        }
                        Section { Button { showCountryPicker = true } label: { HStack { Text("Country").foregroundStyle(.primary); Spacer(); Text("\(store.country(draft.countryCode).flag) \(store.country(draft.countryCode).name)").foregroundStyle(.secondary); Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary) } }
                            TextField("City", text: $draft.city).textInputAutocapitalization(.words).accessibilityIdentifier("animalCity")
                        } header: { Text("Where is the animal?") } footer: { Text("Choose the country the animal is in. This determines its country group.") }
                        Section("Their story") { TextField("Personality, needs, and the kind of home they’d love…", text: $draft.story, axis: .vertical).lineLimit(5...12).accessibilityIdentifier("animalStory") }
                        Section("Care") { Toggle("Vaccinated", isOn: $draft.vaccinated); Toggle("Neutered", isOn: $draft.neutered) }
                        Section { TextField("Contact email", text: $draft.contactEmail).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("contactEmail") } header: { Text("Adoption enquiries") } footer: { Text("This email appears on the post so potential adopters can contact you.") }
                        if editing != nil {
                            Section("Adoption status") { Picker("Status", selection: Binding(get: { draft.status ?? .available }, set: { draft.status = $0 })) { Text("Looking for a home").tag(PostStatus.available); Text("Adopted").tag(PostStatus.adopted) } }
                        }
                        if let error { Section { Text(error).foregroundStyle(.red).font(.subheadline).accessibilityIdentifier("editorError") } }
                    }.scrollDismissesKeyboard(.interactively)
                }
            }
            .navigationTitle(editing == nil ? "Post for adoption" : "Edit adoption post").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if published == nil {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
                    ToolbarItem(placement: .confirmationAction) { Button(saving ? "Saving…" : editing == nil ? "Publish" : "Save") { Task { await save() } }.fontWeight(.semibold).disabled(saving || loadingPhotos).accessibilityIdentifier("publishPost") }
                }
            }
            .interactiveDismissDisabled(saving)
            .sheet(isPresented: $showCountryPicker) { CountryPicker(selection: $draft.countryCode) }
            .onAppear {
                guard !initialized else { return }; initialized = true
                if let editing { draft = PostDraft(post: editing) }
                else { draft.countryCode = store.user?.homeCountry ?? "IT"; draft.contactEmail = store.user?.email ?? "" }
            }
            .task(id: selectedItems) { await loadPhotos() }
        }
    }

    private var photoSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !photos.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 12) {
                        ForEach(Array(photos.enumerated()), id: \.offset) { index, data in
                            if let image = UIImage(data: data) {
                                Image(uiImage: image).resizable().scaledToFill().frame(width: 100, height: 110).clipShape(.rect(cornerRadius: 14))
                                    .overlay(alignment: .topTrailing) { Button { photos.remove(at: index); selectedItems = [] } label: { Image(systemName: "xmark.circle.fill").symbolRenderingMode(.palette).foregroundStyle(.white, .black.opacity(0.6)).font(.title3).padding(5) }.accessibilityLabel("Remove photo \(index + 1)") }
                            }
                        }
                    }
                }
            }
            PhotosPicker(selection: $selectedItems, maxSelectionCount: max(1, 6 - photos.count), matching: .images) {
                Label(loadingPhotos ? "Preparing photos…" : photos.isEmpty ? "Add photos" : "Add more photos", systemImage: "photo.badge.plus").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 22)
                    .background(HATheme.paleBlue, in: .rect(cornerRadius: 17))
            }.buttonStyle(.borderless).disabled(loadingPhotos || photos.count >= 6).accessibilityIdentifier("addPhotos")
            if ProcessInfo.processInfo.arguments.contains("--uitesting") {
                Button("Use test photo") { if let image = UIImage(named: "milo"), let data = image.jpegData(compressionQuality: 0.7) { photos.append(data) } }.buttonStyle(.borderless).accessibilityIdentifier("useTestPhoto")
            }
        }.padding(.vertical, 4)
    }
    private func loadPhotos() async {
        guard !selectedItems.isEmpty else { return }
        loadingPhotos = true; defer { loadingPhotos = false }
        var prepared: [Data] = []
        do {
            for item in selectedItems {
                guard let data = try await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else { throw AppFailure.message("A photo could not be opened. Choose another image.") }
                guard !Task.isCancelled else { return }
                let maxEdge: CGFloat = 1600
                let scale = min(1, maxEdge / max(image.size.width, image.size.height))
                let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
                let resized = UIGraphicsImageRenderer(size: size, format: format).image { context in
                    UIColor.white.setFill(); context.fill(CGRect(origin: .zero, size: size)); image.draw(in: CGRect(origin: .zero, size: size))
                }
                guard let jpeg = resized.jpegData(compressionQuality: 0.78), jpeg.count <= 1_572_864 else { throw AppFailure.message("A photo is too large. Choose a smaller image.") }
                prepared.append(jpeg)
            }
            photos.append(contentsOf: prepared.prefix(6 - photos.count)); selectedItems = []
        } catch { self.error = error.localizedDescription }
    }
    private func save() async {
        error = nil
        if let message = draft.validationMessage { error = message; return }
        if editing == nil && photos.isEmpty { error = "Add at least one photo."; return }
        saving = true; defer { saving = false }
        do {
            if let editing { _ = try await store.update(editing.id, draft: draft); dismiss() }
            else { published = try await store.publish(draft, photos: photos) }
        } catch { self.error = error.localizedDescription }
    }
}
