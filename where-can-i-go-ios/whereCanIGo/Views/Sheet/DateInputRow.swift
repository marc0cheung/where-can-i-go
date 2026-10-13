import SwiftUI

enum DateInputPolicy {
    static func initialDate(value: Date?, preferredDate: Date?, range: ClosedRange<Date>,
                            calendar: Calendar = .current) -> Date {
        let candidate = calendar.startOfDay(for: value ?? preferredDate ?? Date())
        return min(max(candidate, range.lowerBound), range.upperBound)
    }

    static func isValidVisaPeriod(expiryDate: Date?, effectiveDate: Date?,
                                 requiresEffectiveDate: Bool, calendar: Calendar = .current) -> Bool {
        guard let expiryDate else { return false }
        guard requiresEffectiveDate else { return true }
        guard let effectiveDate else { return false }
        return calendar.startOfDay(for: effectiveDate) <= calendar.startOfDay(for: expiryDate)
    }
}

struct DateInputRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let title: LocalizedStringResource
    let clearLabel: LocalizedStringResource
    @Binding var date: Date?
    var range: ClosedRange<Date> = Date.distantPast...Date.distantFuture
    var preferredDate: Date? = nil

    @State private var selection: DateSelection?

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
            Spacer(minLength: 8)
            Button {
                selection = DateSelection(date: DateInputPolicy.initialDate(
                    value: date, preferredDate: preferredDate, range: range
                ))
            } label: {
                Group {
                    if let date {
                        Text(date, format: .dateTime.year().month(.abbreviated).day())
                    } else {
                        Text("Select date")
                    }
                }
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .frame(minHeight: 44)
                .contentShape(Capsule())
                .glassEffect(.regular.interactive(), in: .capsule)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(title))

            if date != nil {
                Button { date = nil } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(clearLabel))
                .help(Text(clearLabel))
                .transition(.opacity.combined(with: .scale(scale: 0.85, anchor: .trailing)))
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .animation(reduceMotion ? nil : .smooth(duration: 0.22), value: date != nil)
        .popover(item: $selection, attachmentAnchor: .rect(.bounds), arrowEdge: .top) { selection in
            DateInputSheet(title: title, initialDate: selection.date, range: range) { date = $0 }
                .presentationCompactAdaptation(.sheet)
                .presentationDetents([.height(360), .large])
                .presentationDragIndicator(.visible)
        }
    }
}

private struct DateSelection: Identifiable {
    let id = UUID()
    let date: Date
}

private struct DateInputSheet: View {
    @Environment(\.dismiss) private var dismiss

    let title: LocalizedStringResource
    let range: ClosedRange<Date>
    let onDone: (Date) -> Void
    @State private var selectedDate: Date

    init(title: LocalizedStringResource, initialDate: Date, range: ClosedRange<Date>,
         onDone: @escaping (Date) -> Void) {
        self.title = title
        self.range = range
        self.onDone = onDone
        _selectedDate = State(initialValue: initialDate)
    }

    var body: some View {
        NavigationStack {
            DatePicker(selection: $selectedDate, in: range, displayedComponents: .date) {
                Text(title)
            }
            .datePickerStyle(.wheel)
            .labelsHidden()
            .accessibilityLabel(Text(title))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .padding(.horizontal)
            .navigationTitle(Text(title))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        onDone(Calendar.current.startOfDay(for: selectedDate))
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .frame(minWidth: 320, minHeight: 300)
    }
}

struct VisaValidityFields: View {
    @Binding var hasEffectiveDate: Bool
    @Binding var effectiveDate: Date?
    @Binding var expiryDate: Date?

    var body: some View {
        VStack(spacing: 12) {
            Toggle("Has effective date", isOn: $hasEffectiveDate)

            if hasEffectiveDate {
                DateInputRow(
                    title: "Effective date", clearLabel: "Clear effective date", date: $effectiveDate,
                    range: Date.distantPast...(expiryDate ?? Date.distantFuture)
                )
            }

            DateInputRow(
                title: "Expiry date", clearLabel: "Clear expiry date", date: $expiryDate,
                range: ((hasEffectiveDate ? effectiveDate : nil) ?? Date.distantPast)...Date.distantFuture,
                preferredDate: Calendar.current.date(byAdding: .year, value: 1, to: Date())
            )
        }
        .onChange(of: hasEffectiveDate) { _, enabled in
            if !enabled { effectiveDate = nil }
        }
    }
}