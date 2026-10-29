import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import AVFoundation

struct ProfileAvatar: View {
    let photoData: Data?
    let size: CGFloat

    var body: some View {
        Group {
            if let photoData, let image = UIImage(data: photoData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "person.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
                    .padding(size * 0.23)
                    .background(Color(uiColor: .tertiarySystemFill))
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}

struct UserProfileView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var profileStore: UserProfileStore

    @State private var draft: UserProfile
    @State private var passportCode: String
    @State private var showPassportPicker = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showPhotoPicker = false
    @State private var showCamera = false
    @State private var pendingPhoto: ProfilePhotoSelection?
    @State private var photoToCrop: ProfilePhotoSelection?
    @State private var isLoadingPhoto = false
    @State private var photoError: String?
    @State private var saveError: String?

    init(profileStore: UserProfileStore, passportCode: String) {
        self.profileStore = profileStore
        _draft = State(initialValue: profileStore.profile)
        _passportCode = State(initialValue: passportCode)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Menu {
                        if draft.photoData != nil {
                            Button("Edit Photo", systemImage: "crop") {
                                editPhoto()
                            }
                        }
                        Button("Take Photo", systemImage: "camera") {
                            Task { await takePhoto() }
                        }
                        Button("Choose from Album", systemImage: "photo.on.rectangle") {
                            showPhotoPicker = true
                        }
                        if draft.photoData != nil {
                            Button("Remove Photo", systemImage: "trash", role: .destructive) {
                                draft.photoData = nil
                                draft.photoSourceData = nil
                                draft.photoCrop = nil
                            }
                        }
                    } label: {
                        ProfileAvatar(photoData: draft.photoData, size: 88)
                    }
                    .accessibilityLabel("Profile photo")
                    .accessibilityHint("Open photo options")
                    .disabled(isLoadingPhoto)

                    if isLoadingPhoto {
                        ProgressView()
                            .accessibilityLabel("Loading photo")
                    }
                }
                .padding(.top, 12)

                VStack(spacing: 16) {
                    HStack(spacing: 16) {
                        Text("Name")
                            .foregroundStyle(.secondary)
                        TextField("Your name", text: $draft.name)
                            .multilineTextAlignment(.trailing)
                            .textContentType(.name)
                            .textInputAutocapitalization(.words)
                            .submitLabel(.done)
                            .accessibilityLabel("Name")
                    }
                    .padding()
                    .background(Color(uiColor: .secondarySystemBackground),
                                in: RoundedRectangle(cornerRadius: 12))

                    Button {
                        showPassportPicker = true
                    } label: {
                        HStack {
                            Text("Passport")
                                .foregroundStyle(.secondary)
                            Spacer()
                            if let country = appState.country(for: passportCode) {
                                Text("\(country.flag) \(country.localizedName())")
                            } else {
                                Text(passportCode)
                            }
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .foregroundStyle(.primary)
                        .padding()
                        .background(Color(uiColor: .secondarySystemBackground),
                                    in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                        .labelStyle(.iconOnly)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save Profile", systemImage: "checkmark") { save() }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.circle)
                        .disabled(isLoadingPhoto || profileStore.loadFailed)
                }
            }
            .sheet(isPresented: $showPassportPicker) {
                PassportPickerView(isFirstLaunch: false, initialCode: passportCode) {
                    passportCode = $0
                }
            }
            .photosPicker(isPresented: $showPhotoPicker, selection: $selectedPhoto, matching: .images)
            .onChange(of: showPhotoPicker) { _, isPresented in
                if !isPresented { presentPendingPhoto() }
            }
            .fullScreenCover(isPresented: $showCamera, onDismiss: presentPendingPhoto) {
                CameraImagePicker { image in
                    do {
                        guard let data = image.jpegData(compressionQuality: 0.95) else {
                            throw ProfilePhotoError.invalidImage
                        }
                        try stagePhoto(data)
                    } catch {
                        photoError = error.localizedDescription
                    }
                }
                .ignoresSafeArea()
            }
            .sheet(item: $photoToCrop) { photo in
                ProfilePhotoEditorSheet(image: photo.image, initialCrop: photo.crop) { data, crop in
                    draft.photoData = data
                    draft.photoSourceData = photo.sourceData
                    draft.photoCrop = crop
                    photoToCrop = nil
                }
            }
            .task(id: selectedPhoto) {
                guard let selectedPhoto else { return }
                isLoadingPhoto = true
                defer { isLoadingPhoto = false }
                do {
                    guard let data = try await selectedPhoto.loadTransferable(type: Data.self) else {
                        throw ProfilePhotoError.invalidImage
                    }
                    try Task.checkCancellation()
                    try stagePhoto(data)
                    presentPendingPhoto()
                } catch is CancellationError {
                    // Dismissing the editor cancels photo loading without changing the saved profile.
                } catch {
                    photoError = error.localizedDescription
                }
                self.selectedPhoto = nil
            }
            .alert("Unable to Load Photo", isPresented: errorBinding($photoError)) {
                Button("OK", role: .cancel) { photoError = nil }
            } message: {
                Text(photoError ?? "")
            }
            .alert("Unable to Save Profile", isPresented: errorBinding($saveError)) {
                Button("OK", role: .cancel) { saveError = nil }
            } message: {
                Text(saveError ?? "")
            }
        }
    }

    private func editPhoto() {
        if let source = draft.photoSourceData, let image = UIImage(data: source) {
            photoToCrop = ProfilePhotoSelection(image: image, sourceData: source, crop: draft.photoCrop)
            return
        }
        // Avatars saved before original photos were retained can only be re-cropped from the avatar.
        guard let data = draft.photoData, let image = UIImage(data: data) else {
            photoError = ProfilePhotoError.invalidImage.localizedDescription
            return
        }
        photoToCrop = ProfilePhotoSelection(image: image, sourceData: data, crop: nil)
    }

    private func stagePhoto(_ data: Data) throws {
        let prepared = try UserProfileStore.preparePhoto(data, maximumPixelSize: 2048)
        guard let image = UIImage(data: prepared) else {
            throw ProfilePhotoError.invalidImage
        }
        pendingPhoto = ProfilePhotoSelection(image: image, sourceData: prepared, crop: nil)
    }

    private func presentPendingPhoto() {
        guard !showPhotoPicker, !showCamera, let pendingPhoto else { return }
        photoToCrop = pendingPhoto
        self.pendingPhoto = nil
    }

    private func takePhoto() async {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            photoError = String(localized: "A camera is not available on this device.")
            return
        }
        isLoadingPhoto = true
        defer { isLoadingPhoto = false }
        let authorized: Bool
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            authorized = true
        case .notDetermined:
            authorized = await AVCaptureDevice.requestAccess(for: .video)
        default:
            authorized = false
        }
        guard authorized else {
            photoError = String(localized: "Allow camera access in Settings to take a photo.")
            return
        }
        showCamera = true
    }

    private func save() {
        do {
            try profileStore.save(draft)
            if passportCode != appState.data.passportCode {
                appState.completePassportSelection(passportCode)
            }
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func errorBinding(_ error: Binding<String?>) -> Binding<Bool> {
        Binding {
            error.wrappedValue != nil
        } set: { isPresented in
            if !isPresented { error.wrappedValue = nil }
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @StateObject private var service: UserDataTransferService
    @State private var showExport = false
    @State private var showImporter = false
    @State private var importURL: URL?
    @State private var importSelection: ImportSelection?
    @State private var importError: String?
    @AppStorage(SearchEngine.storageKey) private var searchEngine: SearchEngine = .google

    init(appState: AppState, profileStore: UserProfileStore, friendStore: FriendStore) {
        _service = StateObject(wrappedValue: UserDataTransferService(
            appState: appState, profileStore: profileStore, friendStore: friendStore
        ))
    }

    private var isBusy: Bool { importURL != nil || appState.isRestoring }

    private struct ImportSelection: Identifiable {
        let id = UUID()
        let backup: UserDataBackup
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(selection: $searchEngine) {
                        ForEach(SearchEngine.allCases) { engine in
                            Text(verbatim: engine.displayName).tag(engine)
                        }
                    } label: {
                        Label("Search Engine", systemImage: "magnifyingglass")
                            .foregroundStyle(Color.primary)
                    }
                } header: {
                    Text("General")
                        .foregroundStyle(.primary)
                }

                Section {
                    NavigationLink {
                        SharingSettingsView()
                    } label: {
                        Label("Sharing", systemImage: "person.2")
                            .foregroundStyle(Color.primary)
                    }
                } header: {
                    Text("Friends")
                        .foregroundStyle(.primary)
                } footer: {
                    Text("Choose what your travel card includes by default.")
                }

                Section {
                    Button {
                        showExport = true
                    } label: {
                        Label("Export Data", systemImage: "square.and.arrow.up")
                            .foregroundStyle(Color.primary)
                    }
                    Button {
                        showImporter = true
                    } label: {
                        Label("Import Data", systemImage: "square.and.arrow.down")
                            .foregroundStyle(Color.primary)
                    }
                    if importURL != nil {
                        ProgressView("import.reading")
                    }
                } header: {
                    Text("Manage Data")
                        .foregroundStyle(.primary)
                }

                Section {
                    NavigationLink {
                        FAQView()
                    } label: {
                        Label("FAQ", systemImage: "questionmark.circle")
                            .foregroundStyle(Color.primary)
                    }
                    NavigationLink {
                        FeedbackView()
                    } label: {
                        Label("Send Feedback", systemImage: "paperplane")
                            .foregroundStyle(Color.primary)
                    }
                } header: {
                    Text("Support")
                        .foregroundStyle(.primary)
                }

                Section {
                    NavigationLink {
                        AboutView()
                    } label: {
                        Label("About", systemImage: "info.circle")
                            .foregroundStyle(Color.primary)
                    }
                    NavigationLink {
                        PrivacyPolicyView()
                    } label: {
                        Label("Privacy Policy", systemImage: "hand.raised")
                            .foregroundStyle(Color.primary)
                    }
                } header: {
                    Text("About")
                        .foregroundStyle(.primary)
                } footer: {
                    Text("Version \(AppInfo.version) (\(AppInfo.build))")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                }
            }
            .disabled(isBusy)
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .disabled(isBusy)
                }
            }
            .sheet(isPresented: $showExport) {
                ExportDataView(service: service)
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
                switch result {
                case .success(let url):
                    importURL = url
                case .failure(let error):
                    if let cocoaError = error as? CocoaError, cocoaError.code == .userCancelled { return }
                    importError = error.localizedDescription
                }
            }
            .task(id: importURL) {
                guard let importURL else { return }
                defer { self.importURL = nil }
                do {
                    let backup = try await service.readBackup(from: importURL)
                    try Task.checkCancellation()
                    importSelection = ImportSelection(backup: backup)
                } catch is CancellationError {
                    // A cancelled file read ends quietly.
                } catch {
                    importError = error.localizedDescription
                }
            }
            .sheet(item: $importSelection) { selection in
                ImportPreviewView(service: service, backup: selection.backup)
            }
            .alert("import.error.title", isPresented: Binding {
                importError != nil
            } set: { presented in
                if !presented { importError = nil }
            }) {
                Button("OK", role: .cancel) { importError = nil }
            } message: {
                Text(verbatim: importError ?? "")
            }
        }
        .interactiveDismissDisabled(isBusy)
    }
}
