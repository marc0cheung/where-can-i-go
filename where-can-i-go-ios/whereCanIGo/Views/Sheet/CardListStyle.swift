import SwiftUI

extension View {
    func cardListStyle() -> some View {
        self
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .listRowSpacing(0)
            .contentMargins(.top, 8, for: .scrollContent)
            .contentMargins(.bottom, 24, for: .scrollContent)
            .environment(\.defaultMinListRowHeight, 0)
    }

    func cardListRow() -> some View {
        self
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}

struct RecordDeletion {
    let title: String
    let message: String
    var buttonTitle = String(localized: "Delete")
    var failureMessage = String(localized: "The record couldn't be deleted. Please try again.")
    let perform: () throws -> Void

    static func visa(country: String, type: String, perform: @escaping () throws -> Void) -> Self {
        Self(
            title: String(localized: "Delete Personal Visa?"),
            message:
                "\(country) · \(type)\n\n\(String(localized: "This saved visa will be permanently deleted. This cannot be undone."))",
            perform: perform
        )
    }

    static func visits(country: String, count: Int, perform: @escaping () throws -> Void) -> Self {
        Self(
            title: String(localized: "Delete All Visits?"),
            message: String(
                localized: "Delete.Visits.Message",
                defaultValue:
                    "Permanently delete \(count) recorded visits to \(country)? Planned trips and saved visas will not be affected. This cannot be undone."
            ),
            buttonTitle: String(localized: "Delete All Visits"),
            perform: perform
        )
    }

    static func plannedTrips(country: String, count: Int, perform: @escaping () throws -> Void) -> Self {
        Self(
            title: String(localized: "Delete All Planned Trips?"),
            message: String(
                localized: "Delete.Plans.Message",
                defaultValue:
                    "Permanently delete \(count) planned trips to \(country)? Recorded visits and saved visas will not be affected. This cannot be undone."
            ),
            buttonTitle: String(localized: "Delete All Planned Trips"),
            failureMessage: String(
                localized: "Some planned trips may already have been deleted. Check the remaining trips and try again."),
            perform: perform
        )
    }
}

private struct RecordDeletionModifier: ViewModifier {
    @Binding var request: RecordDeletion?
    @State private var failureMessage: String?

    func body(content: Content) -> some View {
        content
            .alert(
                Text(verbatim: request?.title ?? ""),
                isPresented: Binding(
                    get: { request != nil },
                    set: { if !$0 { request = nil } }
                ),
                presenting: request
            ) { deletion in
                Button(role: .destructive) {
                    request = nil
                    do {
                        try deletion.perform()
                    } catch {
                        failureMessage = deletion.failureMessage
                    }
                } label: {
                    Text(verbatim: deletion.buttonTitle)
                }
                Button("Cancel", role: .cancel) { request = nil }
            } message: { deletion in
                Text(verbatim: deletion.message)
            }
            .alert(
                "Couldn't Delete",
                isPresented: Binding(
                    get: { failureMessage != nil },
                    set: { if !$0 { failureMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) { failureMessage = nil }
            } message: {
                Text(verbatim: failureMessage ?? "")
            }
    }
}

extension View {
    func recordDeletionConfirmation(_ request: Binding<RecordDeletion?>) -> some View {
        modifier(RecordDeletionModifier(request: request))
    }
}
