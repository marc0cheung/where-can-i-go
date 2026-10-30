import SwiftUI

/// Footer note reminding users that bundled entry policies must be confirmed before travel.
struct TravelConfirmationNotice: View {
    var body: some View {
        Text("travel.warning.body")
            .font(.footnote)
            .foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
    }
}
