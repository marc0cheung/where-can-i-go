import SwiftUI

struct FAQView: View {
    private struct Item: Identifiable {
        let id: Int
        let question: LocalizedStringKey
        let answer: LocalizedStringKey
    }

    private let items: [Item] = [
        Item(id: 1, question: "faq.colors.q", answer: "faq.colors.a"),
        Item(id: 2, question: "faq.accuracy.q", answer: "faq.accuracy.a"),
        Item(id: 3, question: "faq.passports.q", answer: "faq.passports.a"),
        Item(id: 4, question: "faq.myvisa.q", answer: "faq.myvisa.a"),
        Item(id: 5, question: "faq.data.q", answer: "faq.data.a"),
        Item(id: 6, question: "faq.transfer.q", answer: "faq.transfer.a"),
        Item(id: 7, question: "faq.friends.q", answer: "faq.friends.a"),
        Item(id: 8, question: "faq.dice.q", answer: "faq.dice.a"),
        Item(id: 9, question: "faq.contact.q", answer: "faq.contact.a"),
    ]

    @State private var expanded: Set<Int> = []

    var body: some View {
        List {
            ForEach(items) { item in
                DisclosureGroup(isExpanded: Binding {
                    expanded.contains(item.id)
                } set: { isOpen in
                    if isOpen { expanded.insert(item.id) } else { expanded.remove(item.id) }
                }) {
                    Text(item.answer)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                } label: {
                    Text(item.question)
                        .font(.body.weight(.semibold))
                }
            }

            Section {
                NavigationLink {
                    FeedbackView()
                } label: {
                    Label("Send Feedback", systemImage: "paperplane")
                        .foregroundStyle(Color.primary)
                }
            } footer: {
                Text("Can't find your answer? Let us know.")
            }
        }
        .navigationTitle("FAQ")
        .navigationBarTitleDisplayMode(.inline)
    }
}
