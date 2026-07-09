import SwiftUI

struct MyVisasTab: View {
    @EnvironmentObject var appState: AppState

    // MARK: - Committed draft state (used by "Add Visa")
    @State private var country: Country? = nil
    @State private var visaType: String = ""
    @State private var duration: String = ""
    @State private var expiry: Date? = nil
    @State private var notes: String = ""

    // MARK: - Sheet presentation
    @State private var showCountryPicker = false
    @State private var showVisaDetailsSheet = false

    // MARK: - Error handling
    @State private var errorMessage: String? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Add Personal Visa").font(.headline)

                // MARK: Input Cards (Flighty-style)
                HStack(spacing: 10) {
                    Button {
                        showCountryPicker = true
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

                // MARK: Excel import (unchanged)
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
            }
            .padding()
        }
        .sheet(isPresented: $showCountryPicker) {
            CountryPickerSheet(selected: $country)
        }
        .sheet(isPresented: $showVisaDetailsSheet) {
            VisaDetailsSheet(
                visaType: visaType,
                duration: duration,
                expiry: expiry,
                notes: notes
            ) { newVisaType, newDuration, newExpiry, newNotes in
                // Commit only when user taps Done
                visaType = newVisaType
                duration = newDuration
                expiry = newExpiry
                notes = newNotes
                errorMessage = nil
            }
        }
        .onChange(of: country) { _, _ in
            errorMessage = nil
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
                Text(country.name)
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
            ButtonCard(label: "Country", remark: "Tap to edit", color: .gray)
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
            withAnimation { errorMessage = "Please select a country." }
            return
        }
        if visaType.isEmpty || duration.isEmpty || expiry == nil {
            withAnimation {
                errorMessage = "Please fill in Visa Type, Duration and Expiry Date."
            }
            return
        }
        guard let expiryDate = expiry else { return }

        withAnimation { errorMessage = nil }

        let visa = PersonalVisa(
            countryCode: c.code,
            visaType: visaType,
            duration: duration,
            expiryDate: expiryDate,
            notes: notes.isEmpty ? nil : notes
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
        errorMessage = nil
    }

    // MARK: - Saved visa row (unchanged)

    @ViewBuilder
    private func personalVisaRow(_ v: PersonalVisa) -> some View {
        let c = appState.country(for: v.countryCode)
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(c?.flag ?? "")  \(c?.name ?? v.countryCode)")
                    .font(.subheadline.bold())
                Text("\(v.visaType) · \(v.duration)").font(.caption)
                Text("Expires \(v.expiryDate.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption2).foregroundStyle(.secondary)
                if let notes = v.notes, !notes.isEmpty {
                    Text(notes).font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button(role: .destructive) {
                appState.removePersonalVisa(v.id)
            } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.gray)
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Visa Details Bottom Sheet

private struct VisaDetailsSheet: View {
    @Environment(\.dismiss) private var dismiss

    // Local draft — only committed to parent on "Done"
    @State private var draftVisaType: String
    @State private var draftDuration: String
    @State private var draftExpiry: Date
    @State private var draftHasExpiry: Bool
    @State private var draftNotes: String

    let onDone: (String, String, Date?, String) -> Void

    init(visaType: String,
         duration: String,
         expiry: Date?,
         notes: String,
         onDone: @escaping (String, String, Date?, String) -> Void) {
        _draftVisaType = State(initialValue: visaType)
        _draftDuration = State(initialValue: duration)
        _draftExpiry   = State(initialValue: expiry ?? Date().addingTimeInterval(60 * 60 * 24 * 365))
        _draftHasExpiry = State(initialValue: expiry != nil)
        _draftNotes    = State(initialValue: notes)
        self.onDone = onDone
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    formLabel("VISA TYPE")
                    TextField("e.g., Single / Multiple / Student / Work", text: $draftVisaType)
                        .padding()
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))

                    formLabel("DURATION PER VISIT")
                    TextField("e.g., 90 days", text: $draftDuration)
                        .padding()
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))

                    formLabel("EXPIRY DATE")
                    if draftHasExpiry {
                        HStack {
                            DatePicker("", selection: $draftExpiry, displayedComponents: .date)
                                .labelsHidden()
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
                            draftVisaType,
                            draftDuration,
                            draftHasExpiry ? draftExpiry : nil,
                            draftNotes
                        )
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func formLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}

// MARK: - Button Card (unchanged shape)

private struct ButtonCard: View {
    let label: String
    let remark: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(label.uppercased())
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
