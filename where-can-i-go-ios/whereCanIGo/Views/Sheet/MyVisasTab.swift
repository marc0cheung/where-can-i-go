import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct MyVisasTab: View {
    @EnvironmentObject var appState: AppState

    // MARK: - Committed draft state (used by "Add Visa")
    @State private var country: Country? = nil
    @State private var visaType: String = ""
    @State private var duration: String = ""
    @State private var expiry: Date? = nil
    @State private var notes: String = ""
    @State private var coverage: VisaCoverage = .issuingCountry

    // MARK: - Sheet presentation
    @State private var showVisaDetailsSheet = false
    @State private var visaBeingEdited: PersonalVisa? = nil
    @State private var visaPendingDeletion: PersonalVisa? = nil
    @State private var showDeleteConfirmation = false

    // MARK: - Draft attachment state (Add flow)
    @State private var attachmentFileNames: [String] = []
    @State private var draftVisaID: UUID = UUID()

    // MARK: - Error handling
    @State private var errorMessage: String? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Add Personal Visa").font(.headline)

                // MARK: Input Cards (Flighty-style)
                HStack(spacing: 10) {
                    Button {
                        showVisaDetailsSheet = true
                    } label: {
                        countryCard
                    }
                    .buttonStyle(.plain)

                    Button {
                        showVisaDetailsSheet = true
                    } label: {
                        visaDetailsCard
                    }
                    .buttonStyle(.plain)
                }

                // Inline error (shown only when "Add Visa" is tapped with missing fields)
                if let errorMessage {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text(errorMessage)
                    }
                    .font(.caption)
                    .foregroundStyle(.red)
                    .transition(.opacity)
                }

                // MARK: Add Visa Button (save trigger — logic preserved)
                Button(action: addVisa) {
                    Text("ADD VISA")
                        .font(.headline).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding()
                        .background(canAdd ? Color.black : Color.gray.opacity(0.6),
                                    in: RoundedRectangle(cornerRadius: 10))
                }

                Divider().padding(.vertical, 8)

                // MARK: Saved list (unchanged)
                Text("Saved Personal Visas").font(.headline)
                if appState.data.personalVisas.isEmpty {
                    Text("No personal visas yet.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(appState.data.personalVisas) { visa in
                        personalVisaRow(visa)
                    }
                }

                if String(localized: "MyVisas.ShowExcelImport").lowercased() == "true" {
                    Divider().padding(.vertical, 8)

                    // MARK: Excel import
                    Text("Import from Excel").font(.headline)
                    Text("Load visa records from the MyVisa sheet of an .xlsx file.\nColumns: Country, Visa Type, Duration, Expire Date (dd-mm-yyyy), Notes.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button {
                        // TODO: implement Excel import
                    } label: {
                        Text("IMPORT EXCEL FILE (Coming Soon)")
                            .font(.subheadline.bold())
                            .frame(maxWidth: .infinity).padding()
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
                    }
                    .disabled(true)
                }
            }
            .padding()
        }
        .alert("Delete Personal Visa?", isPresented: $showDeleteConfirmation, presenting: visaPendingDeletion) { visa in
            Button("Delete", role: .destructive) {
                appState.removePersonalVisa(visa.id)
                visaPendingDeletion = nil
            }
            Button("Cancel", role: .cancel) {
                visaPendingDeletion = nil
            }
        } message: { visa in
            let countryName = appState.country(for: visa.countryCode)?.localizedName() ?? visa.countryCode
            Text("\(countryName) · \(visa.visaType)\n\n\(Text("This saved visa will be permanently deleted. This cannot be undone."))")
        }
        .sheet(isPresented: $showVisaDetailsSheet) {
            VisaDetailsSheet(
                country: country,
                visaID: draftVisaID,
                attachmentFileNames: attachmentFileNames,
                visaType: visaType,
                duration: duration,
                expiry: expiry,
                notes: notes,
                coverage: coverage
            ) { newCountry, newVisaType, newDuration, newExpiry, newNotes, newAttachments, newCoverage in
                country = newCountry
                visaType = newVisaType
                duration = newDuration
                expiry = newExpiry
                notes = newNotes
                attachmentFileNames = newAttachments
                coverage = newCoverage
                errorMessage = nil
            }
        }
        .sheet(item: $visaBeingEdited) { visa in
            VisaDetailsSheet(
                country: appState.country(for: visa.countryCode),
                visaID: visa.id,
                attachmentFileNames: visa.attachmentFileNames,
                visaType: visa.visaType,
                duration: visa.duration,
                expiry: visa.expiryDate,
                notes: visa.notes ?? "",
                coverage: visa.coverage
            ) { newCountry, newVisaType, newDuration, newExpiry, newNotes, newAttachments, newCoverage in
                guard let updatedCountry = newCountry, let newExpiry else { return }
                let removed = visa.attachmentFileNames.filter { !newAttachments.contains($0) }
                removed.forEach { VisaAttachmentStore.delete(fileName: $0, for: visa.id) }
                appState.updatePersonalVisa(
                    PersonalVisa(
                        id: visa.id,
                        countryCode: updatedCountry.code,
                        visaType: newVisaType,
                        duration: newDuration,
                        expiryDate: newExpiry,
                        notes: newNotes.isEmpty ? nil : newNotes,
                        attachmentFileNames: newAttachments,
                        coverage: newCoverage
                    )
                )
            }
        }
        .onChange(of: country) { _, newCountry in
            errorMessage = nil
            if !VisaCoverage.schengenCountryCodes.contains(newCountry?.code ?? "") {
                coverage = .issuingCountry
            }
        }
        .onChange(of: appState.pendingAddVisaCountryCode) { _, newCode in
            if let code = newCode {
                country = appState.country(for: code)
                appState.pendingAddVisaCountryCode = nil
            }
        }
        .onAppear {
            if let code = appState.pendingAddVisaCountryCode {
                country = appState.country(for: code)
                appState.pendingAddVisaCountryCode = nil
            }
        }
        .onDisappear {
            // Requirement: wipe everything when user leaves this tab
            resetDraft()
        }
    }

    // MARK: - Country Card

    @ViewBuilder
    private var countryCard: some View {
        if let country {
            VStack(spacing: 4) {
                Text(country.flag)
                    .font(.system(size: 28))
                Text(country.localizedName())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, minHeight: 72)
            .padding(.vertical, 12)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.gray.opacity(0.4), lineWidth: 1)
            )
        } else {
            ButtonCard(label: "Issuing Country", remark: "Tap to edit", color: .gray)
        }
    }

    // MARK: - Visa Details Card

    @ViewBuilder
    private var visaDetailsCard: some View {
        if isVisaDetailsFilled, let expiry {
            VStack(spacing: 4) {
                Text(duration)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(expiry.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 72)
            .padding(.vertical, 12)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.gray.opacity(0.4), lineWidth: 1)
            )
        } else {
            ButtonCard(label: "Visa Details", remark: "Tap to edit", color: .gray)
        }
    }

    /// Card only shows filled state when BOTH duration and expiry are set.
    private var isVisaDetailsFilled: Bool {
        !duration.isEmpty && expiry != nil
    }

    // MARK: - Logic

    private var canAdd: Bool {
        country != nil && !visaType.isEmpty && !duration.isEmpty && expiry != nil
    }

    private func addVisa() {
        // Validation with clear per-field messages
        guard let c = country else {
            withAnimation { errorMessage = String(localized: "Please select a country.") }
            return
        }
        if visaType.isEmpty || duration.isEmpty || expiry == nil {
            withAnimation {
                errorMessage = String(localized: "Please fill in Visa Type, Duration and Expiry Date.")
            }
            return
        }
        guard let expiryDate = expiry else { return }

        withAnimation { errorMessage = nil }

        let visa = PersonalVisa(
            id: draftVisaID,
            countryCode: c.code,
            visaType: visaType,
            duration: duration,
            expiryDate: expiryDate,
            notes: notes.isEmpty ? nil : notes,
            attachmentFileNames: attachmentFileNames,
            coverage: coverage
        )
        appState.addPersonalVisa(visa)
        resetDraft()
    }

    private func resetDraft() {
        country = nil
        visaType = ""
        duration = ""
        expiry = nil
        notes = ""
        coverage = .issuingCountry
        attachmentFileNames = []
        draftVisaID = UUID()
        errorMessage = nil
    }

    private func expiryReminderColor(for expiryDate: Date) -> Color {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let expiryDay = calendar.startOfDay(for: expiryDate)

        if today > expiryDay {
            return .red
        }
        if let warningStart = calendar.date(byAdding: .day, value: -31, to: expiryDay),
           today >= warningStart {
            return .orange
        }
        return .secondary
    }

    // MARK: - Saved visa row

    @ViewBuilder
    private func personalVisaRow(_ v: PersonalVisa) -> some View {
        let c = appState.country(for: v.countryCode)
        Button {
            visaBeingEdited = v
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(c?.flag ?? "")  \(c?.localizedName() ?? v.countryCode)")
                        .font(.subheadline.bold())
                    if v.coverage == .schengenArea {
                        Text("Schengen Area")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Text("\(v.visaType) · \(v.duration)").font(.caption)
                    Text("Expires \(v.expiryDate.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption2)
                        .foregroundStyle(expiryReminderColor(for: v.expiryDate))
                    if let notes = v.notes, !notes.isEmpty {
                        Text(notes).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .padding()
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .overlay(alignment: .trailing) {
            Button(role: .destructive) {
                visaPendingDeletion = v
                showDeleteConfirmation = true
            } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.gray)
            }
            .accessibilityLabel("Delete Personal Visa")
            .padding(.trailing)
        }
    }
}

// MARK: - Visa Details Bottom Sheet

private struct VisaDetailsSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var draftCountry: Country?
    @State private var showCountryPicker = false

    // Local draft — only committed to parent on "Done"
    @State private var draftVisaType: String
    @State private var draftDuration: String
    @State private var draftExpiry: Date
    @State private var draftHasExpiry: Bool
    @State private var draftNotes: String
    @State private var draftCoverage: VisaCoverage

    // Attachment draft
    @State private var draftAttachmentFileNames: [String]
    @State private var showAttachmentActionSheet = false
    @State private var showCamera = false
    @State private var showPhotoPicker = false
    @State private var photoPickerItem: PhotosPickerItem? = nil
    @State private var showFilePicker = false
    @State private var previewingAttachment: AttachmentPreviewItem? = nil

    let visaID: UUID
    let onDone: (Country?, String, String, Date?, String, [String], VisaCoverage) -> Void

    init(country: Country?,
         visaID: UUID,
         attachmentFileNames: [String] = [],
         visaType: String,
         duration: String,
         expiry: Date?,
         notes: String,
         coverage: VisaCoverage,
         onDone: @escaping (Country?, String, String, Date?, String, [String], VisaCoverage) -> Void) {
        _draftCountry = State(initialValue: country)
        self.visaID = visaID
        _draftAttachmentFileNames = State(initialValue: attachmentFileNames)
        _draftVisaType = State(initialValue: visaType)
        _draftDuration = State(initialValue: duration)
        _draftExpiry   = State(initialValue: expiry ?? Date().addingTimeInterval(60 * 60 * 24 * 365))
        _draftHasExpiry = State(initialValue: expiry != nil)
        _draftNotes    = State(initialValue: notes)
        _draftCoverage = State(initialValue: coverage)
        self.onDone = onDone
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    formLabel("ISSUING COUNTRY")
                    Button {
                        showCountryPicker = true
                    } label: {
                        HStack {
                            if let country = draftCountry {
                                Text(country.flag)
                                    .font(.title2)
                                Text(country.localizedName())
                                    .foregroundStyle(.primary)
                            } else {
                                Text("Select a country")
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding()
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .overlay(alignment: .trailing) {
                        if draftCountry != nil {
                            Button { draftCountry = nil } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .padding(.trailing, 16)
                        }
                    }

                    if VisaCoverage.schengenCountryCodes.contains(draftCountry?.code ?? "") {
                        Toggle("Valid throughout the Schengen Area", isOn: Binding(
                            get: { draftCoverage == .schengenArea },
                            set: { draftCoverage = $0 ? .schengenArea : .issuingCountry }
                        ))
                        .padding()
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
                    }

                    formLabel("VISA TYPE")
                    HStack {
                        TextField("e.g., Single / Multiple / Student / Work", text: $draftVisaType)
                        if !draftVisaType.isEmpty {
                            Button { draftVisaType = "" } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))

                    formLabel("DURATION PER VISIT")
                    HStack {
                        TextField("e.g., 90 days", text: $draftDuration)
                        if !draftDuration.isEmpty {
                            Button { draftDuration = "" } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))

                    formLabel("EXPIRY DATE")
                    if draftHasExpiry {
                        HStack {
                            DatePicker("", selection: $draftExpiry, displayedComponents: .date)
                                .labelsHidden()
                                .datePickerStyle(.graphical)
                            Spacer()
                            Button {
                                withAnimation { draftHasExpiry = false }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding()
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
                    } else {
                        Button {
                            withAnimation { draftHasExpiry = true }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "calendar.badge.plus")
                                Text("Set expiry date")
                                Spacer()
                            }
                            .padding()
                            .foregroundStyle(.primary)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                    }

                    formLabel("NOTES (OPTIONAL)")
                    TextField("Additional notes…", text: $draftNotes, axis: .vertical)
                        .lineLimit(3...6)
                        .padding()
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))

                    Divider()
                        .padding(.vertical, 4)

                    formLabel("ATTACHMENTS (OPTIONAL)")
                    Button {
                        showAttachmentActionSheet = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "paperclip")
                            Text("Add Attachment")
                            Spacer()
                        }
                        .padding()
                        .foregroundStyle(.primary)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .confirmationDialog("Add Attachment", isPresented: $showAttachmentActionSheet) {
                        Button("Take a Photo") { showCamera = true }
                        Button("Choose from Photo Album") { showPhotoPicker = true }
                        Button("Choose from File") { showFilePicker = true }
                    }

                    if !draftAttachmentFileNames.isEmpty {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 80), spacing: 8)],
                            spacing: 8
                        ) {
                            ForEach(draftAttachmentFileNames, id: \.self) { name in
                                AttachmentThumbnailView(
                                    fileName: name,
                                    visaID: visaID,
                                    onTap: { previewingAttachment = AttachmentPreviewItem(id: name) },
                                    onDelete: { draftAttachmentFileNames.removeAll { $0 == name } }
                                )
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Visa Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    // Swipe-down = cancel, this button is just an explicit alternative
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        onDone(
                            draftCountry,
                            draftVisaType,
                            draftDuration,
                            draftHasExpiry ? draftExpiry : nil,
                            draftNotes,
                            draftAttachmentFileNames,
                            draftCoverage
                        )
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(!canDone)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onChange(of: draftCountry) { _, newCountry in
            if !VisaCoverage.schengenCountryCodes.contains(newCountry?.code ?? "") {
                draftCoverage = .issuingCountry
            }
        }
        .sheet(isPresented: $showCountryPicker) {
            CountryPickerSheet(selected: $draftCountry)
        }
        .sheet(item: $previewingAttachment) { item in
            VisaAttachmentPreviewSheet(fileName: item.id, visaID: visaID)
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $photoPickerItem, matching: .images)
        .onChange(of: photoPickerItem) { _, item in
            Task { @MainActor in
                defer { photoPickerItem = nil }
                guard let item,
                      let data = try? await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data),
                      let jpeg = image.jpegData(compressionQuality: 0.85) else { return }
                saveAttachment(data: jpeg, ext: "jpg")
            }
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.image, .pdf],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }
            guard let data = try? Data(contentsOf: url) else { return }
            let ext = url.pathExtension.isEmpty ? "dat" : url.pathExtension
            saveAttachment(data: data, ext: ext)
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraImagePicker { image in
                guard let jpeg = image.jpegData(compressionQuality: 0.85) else { return }
                saveAttachment(data: jpeg, ext: "jpg")
            }
            .ignoresSafeArea()
        }
    }

    // MARK: - Validation

    private var canDone: Bool {
        draftCountry != nil && !draftVisaType.isEmpty && !draftDuration.isEmpty && draftHasExpiry
    }

    // MARK: - Save helper

    private func saveAttachment(data: Data, ext: String) {
        if let name = try? VisaAttachmentStore.save(data: data, fileExtension: ext, for: visaID) {
            draftAttachmentFileNames.append(name)
        }
    }

    private func formLabel(_ text: LocalizedStringResource) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}

// MARK: - Button Card (unchanged shape)

private struct ButtonCard: View {
    let label: LocalizedStringResource
    let remark: LocalizedStringResource
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(String(localized: label).uppercased(with: .current))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text(remark)
                .font(.caption2.weight(.thin))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 72)
        .padding(.vertical, 16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(color.opacity(0.4), lineWidth: 1)
        )
    }
}
