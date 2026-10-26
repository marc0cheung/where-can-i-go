import SwiftUI
import UniformTypeIdentifiers

struct ExportDataView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var service: UserDataTransferService
    @State private var options = UserDataTransferService.ExportOptions()
    @State private var isPreparing = false
    @State private var showExporter = false
    @State private var result: UserDataExportResult?
    @State private var exportCompleted = false
    @State private var notice: TransferNotice?

    private var isBusy: Bool { isPreparing || showExporter || appState.isRestoring }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("export.recordsOnly.note")
                    Toggle("transfer.profilePhoto", isOn: $options.includeProfilePhoto)
                    Toggle("transfer.visaAttachments", isOn: $options.includeVisaAttachments)
                } footer: {
                    if options.includeProfilePhoto || options.includeVisaAttachments {
                        Text("export.mediaPrivacy.note")
                    }
                }
                BackupRecordCounts(
                    visas: appState.data.personalVisas.count,
                    visits: appState.data.visits.count,
                    wishlist: appState.data.plannedTrips.count
                )
                if exportCompleted, let result, !result.skippedFileNames.isEmpty {
                    Section("export.skipped.title") {
                        ForEach(Array(result.skippedFileNames.enumerated()), id: \.offset) { _, name in
                            Text(verbatim: name)
                        }
                    }
                }
            }
            .disabled(isBusy)
            .navigationTitle("Export Data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .disabled(isBusy)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if isPreparing {
                        ProgressView()
                            .accessibilityLabel("export.preparing")
                    } else {
                        Button("export.action") {
                            exportCompleted = false
                            result = nil
                            isPreparing = true
                        }
                        .disabled(isBusy)
                    }
                }
            }
            .fileExporter(
                isPresented: $showExporter,
                document: result.map { UserDataBackupDocument(backup: $0.backup) },
                contentType: .json,
                defaultFilename: UserDataBackupDocument.defaultFileName(),
                onCompletion: finishExport
            )
            .task(id: isPreparing) {
                guard isPreparing else { return }
                defer { isPreparing = false }
                do {
                    try Task.checkCancellation()
                    result = try service.makeBackup(options: options)
                    showExporter = true
                } catch is CancellationError {
                    // Cancellation does not mean an export failed.
                } catch {
                    notice = TransferNotice(title: "export.error.title", message: error.localizedDescription)
                }
            }
            .alert(item: $notice) { notice in
                Alert(title: Text(notice.title), message: Text(verbatim: notice.message),
                      dismissButton: .default(Text("OK")))
            }
        }
        .interactiveDismissDisabled(isBusy)
    }

    private func finishExport(_ completion: Result<URL, Error>) {
        switch completion {
        case .success:
            exportCompleted = true
            var message = String(localized: "export.success.message")
            if let result, !result.skippedFileNames.isEmpty {
                message += "\n\n" + String(localized: "export.skipped.title")
            }
            notice = TransferNotice(title: "export.success.title", message: message)
        case .failure(let error):
            if let cocoaError = error as? CocoaError, cocoaError.code == .userCancelled { return }
            notice = TransferNotice(title: "export.error.title", message: error.localizedDescription)
        }
    }
}

struct ImportPreviewView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var service: UserDataTransferService
    let backup: UserDataBackup
    @State private var mode: UserDataImportMode = .merge
    @State private var initialized = false
    @State private var summary: UserDataRestoreSummary?
    @State private var showReplaceConfirmation = false
    @State private var isImporting = false
    @State private var didImport = false
    @State private var notice: TransferNotice?

    private var isBusy: Bool { isImporting || appState.isRestoring }

    var body: some View {
        NavigationStack {
            Form {
                let details = backup.previewDetails
                Section("import.backupDetails") {
                    LabeledContent("import.exportedAt") {
                        Text(details.exportedAt, format: .dateTime.year().month().day().hour().minute())
                    }
                    LabeledContent("import.appVersion", value: displayValue(details.appVersion))
                    LabeledContent("Passport", value: displayValue(details.passportCode))
                    LabeledContent("transfer.profilePhoto", value: inclusionText(details.includesProfilePhoto))
                    LabeledContent("transfer.visaAttachments", value: inclusionText(details.includesVisaAttachments))
                }
                BackupRecordCounts(
                    visas: details.personalVisaCount,
                    visits: details.visitCount,
                    wishlist: details.wishlistCount
                )
                Section {
                    Picker("import.mode", selection: $mode) {
                        Text("import.mode.replace").tag(UserDataImportMode.replace)
                        Text("import.mode.merge").tag(UserDataImportMode.merge)
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    switch mode {
                    case .replace: Text("import.replace.note")
                    case .merge: Text("import.merge.note")
                    }
                }
                if !details.includesVisaAttachments {
                    Section {
                        Text("import.attachmentsNotIncluded.note")
                            .foregroundStyle(.secondary)
                    }
                }
                if let summary {
                    Section {
                        let rows = restoreSummaryRows(summary, completed: didImport)
                        ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                            LabeledContent {
                                Text(verbatim: row.value)
                            } label: {
                                Text(row.title)
                            }
                        }
                        if summary.mediaSkipped > 0 || summary.entryPoliciesSkipped > 0 {
                            Text("import.newerContent.note")
                                .foregroundStyle(.secondary)
                        }
                    } header: {
                        if didImport {
                            Text("import.success.title")
                        } else {
                            Text("import.preview.title")
                        }
                    }
                }
            }
            .disabled(isBusy || didImport)
            .navigationTitle("Import Data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .disabled(isBusy || didImport)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if isImporting {
                        ProgressView()
                            .accessibilityLabel("import.progress")
                    } else {
                        Button("import.action") {
                            switch mode {
                            case .replace: showReplaceConfirmation = true
                            case .merge: isImporting = true
                            }
                        }
                        .disabled(isBusy || didImport || summary == nil)
                    }
                }
            }
            .onAppear {
                guard !initialized else { return }
                initialized = true
                mode = appState.data.personalVisas.isEmpty
                    && appState.data.visits.isEmpty
                    && appState.data.plannedTrips.isEmpty ? .replace : .merge
                refreshPreview()
            }
            .onChange(of: mode) { _, _ in refreshPreview() }
            .onChange(of: appState.dataRevision) { _, _ in
                guard !isBusy, !didImport else { return }
                showReplaceConfirmation = false
                refreshPreview()
            }
            .confirmationDialog("import.replace.confirm.title", isPresented: $showReplaceConfirmation,
                                titleVisibility: .visible) {
                Button("import.mode.replace", role: .destructive) { isImporting = true }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("import.replace.confirm.message")
            }
            .task(id: isImporting) {
                guard isImporting else { return }
                defer { isImporting = false }
                do {
                    let restored = try await service.importBackup(backup, mode: mode)
                    summary = restored
                    didImport = true
                    let message = restoreSummaryRows(restored, completed: true).map {
                        String(localized: $0.title) + ": " + $0.value
                    }.joined(separator: "\n")
                    notice = TransferNotice(title: "import.success.title", message: message)
                } catch is CancellationError {
                    // The service checks cancellation before committing any data.
                } catch {
                    refreshPreview()
                    notice = TransferNotice(title: "import.error.title", message: error.localizedDescription)
                }
            }
            .alert(item: $notice) { notice in
                Alert(title: Text(notice.title), message: Text(verbatim: notice.message),
                      dismissButton: .default(Text("OK")) {
                          if didImport { dismiss() }
                      })
            }
        }
        .interactiveDismissDisabled(isBusy || didImport)
    }

    private func refreshPreview() {
        do {
            summary = try service.preview(backup, mode: mode)
        } catch {
            summary = nil
            notice = TransferNotice(title: "import.error.title", message: error.localizedDescription)
        }
    }

    private func displayValue(_ value: String) -> String {
        value.isEmpty ? String(localized: "transfer.notProvided") : value
    }

    private func inclusionText(_ included: Bool) -> String {
        included ? String(localized: "transfer.included") : String(localized: "transfer.notIncluded")
    }
}

private struct BackupRecordCounts: View {
    let visas: Int
    let visits: Int
    let wishlist: Int

    var body: some View {
        Section("transfer.records") {
            LabeledContent("My Visas", value: visas.formatted())
            LabeledContent("transfer.visits", value: visits.formatted())
            LabeledContent("Wishlist", value: wishlist.formatted())
        }
    }
}

private struct TransferNotice: Identifiable {
    let id = UUID()
    let title: LocalizedStringKey
    let message: String
}

private func restoreSummaryRows(
    _ summary: UserDataRestoreSummary, completed: Bool
) -> [(title: LocalizedStringResource, value: String)] {
    let counts = summary.previewCounts
    func countText(_ added: Int, _ skipped: Int) -> String {
        switch summary.mode {
        case .replace:
            let format = completed
                ? String(localized: "import.count.imported")
                : String(localized: "import.count.willImport")
            return String.localizedStringWithFormat(format, added)
        case .merge:
            let format = completed
                ? String(localized: "import.count.merged")
                : String(localized: "import.count.willMerge")
            return String.localizedStringWithFormat(format, added, skipped)
        }
    }
    var rows: [(title: LocalizedStringResource, value: String)] = [
        ("My Visas", countText(counts.personalVisasAdded, counts.personalVisasSkipped)),
        ("transfer.visits", countText(counts.visitsAdded, counts.visitsSkipped)),
        ("Wishlist", countText(counts.wishlistAdded, counts.wishlistSkipped))
    ]
    if summary.mediaSkipped > 0 {
        rows.append(("import.summary.mediaSkipped", summary.mediaSkipped.formatted()))
    }
    if summary.entryPoliciesSkipped > 0 {
        rows.append(("import.summary.entryPoliciesSkipped", summary.entryPoliciesSkipped.formatted()))
    }
    if summary.wishlistResolvedAsVisited > 0 {
        rows.append(("import.summary.wishlistResolved", summary.wishlistResolvedAsVisited.formatted()))
    }
    if summary.passportChanged {
        rows.append((
            "Passport",
            completed ? String(localized: "import.updated") : String(localized: "import.willUpdate")
        ))
    }
    if completed, summary.profileUpdated {
        rows.append(("User Profile", String(localized: "import.updated")))
    }
    return rows
}
