import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

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
                    .foregroundStyle(.secondary)
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
                    ProfileAvatar(photoData: draft.photoData, size: 88)
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Text("Edit Photo")
                            .font(.caption)
                    }
                    .disabled(isLoadingPhoto)

                    if isLoadingPhoto {
                        ProgressView()
                            .accessibilityLabel("Loading photo")
                    }
                    if draft.photoData != nil {
                        Button("Remove Photo", role: .destructive) {
                            draft.photoData = nil
                            selectedPhoto = nil
                        }
                        .font(.caption)
                        .disabled(isLoadingPhoto)
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
            .task(id: selectedPhoto) {
                guard let selectedPhoto else { return }
                isLoadingPhoto = true
                defer { isLoadingPhoto = false }
                do {
                    guard let data = try await selectedPhoto.loadTransferable(type: Data.self) else {
                        throw ProfilePhotoError.invalidImage
                    }
                    try Task.checkCancellation()
                    draft.photoData = try UserProfileStore.preparePhoto(data)
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

    init(appState: AppState, profileStore: UserProfileStore) {
        _service = StateObject(wrappedValue: UserDataTransferService(
            appState: appState, profileStore: profileStore
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
                    // A cancelled file read should not present an error or a preview.
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
