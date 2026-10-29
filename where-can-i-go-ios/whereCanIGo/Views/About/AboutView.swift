import SwiftUI

struct AboutView: View {
    var body: some View {
        Form {
            Section {
                VStack(spacing: 10) {
                    Image("AppIconPreview")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 84, height: 84)
                        .clipShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
                        .accessibilityHidden(true)
                    Text(verbatim: AppInfo.displayName)
                        .font(.title2.weight(.bold))
                    Text("Version \(AppInfo.version) (\(AppInfo.build))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
            }

            Section {
                Text("about.mission")
                    .font(.body)
            }

            Section {
                Link(destination: AppInfo.instagramURL) {
                    LabeledContent {
                        Text(verbatim: "@\(AppInfo.instagramHandle)")
                    } label: {
                        Label("Instagram", systemImage: "camera")
                            .foregroundStyle(Color.primary)
                    }
                }
                Link(destination: AppInfo.repositoryURL) {
                    LabeledContent {
                        Image(systemName: "arrow.up.right")
                            .foregroundStyle(.secondary)
                    } label: {
                        Label("Source Code on GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                            .foregroundStyle(Color.primary)
                    }
                }
            } header: {
                Text("Follow Us")
            }

            Section {
                NavigationLink {
                    AcknowledgementsView()
                } label: {
                    Label("Acknowledgements & Sources", systemImage: "heart")
                        .foregroundStyle(Color.primary)
                }
                Link(destination: AppInfo.licenseURL) {
                    LabeledContent {
                        Text(verbatim: "MIT")
                    } label: {
                        Label("License", systemImage: "doc.text")
                            .foregroundStyle(Color.primary)
                    }
                }
            } footer: {
                Text("about.disclaimer")
            }
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct AcknowledgementsView: View {
    private struct Source: Identifiable {
        let id: String
        let title: LocalizedStringKey
        let url: URL
    }

    private let sources: [Source] = [
        Source(id: "HKG", title: "Hong Kong: Immigration Department",
               url: URL(string: "https://www.immd.gov.hk/hkt/service/travel_document/visa_free_access.html")!),
        Source(id: "MAC", title: "Macao: Identification Services Bureau",
               url: URL(string: "https://www.dsi.gov.mo/en/visa")!),
        Source(id: "CHN", title: "China: source summary",
               url: URL(string: "https://github.com/marc0cheung/where-can-i-go/blob/main/where-can-i-go-ios/whereCanIGo/Resources/Source/default_visas_CHN.sources.md")!),
        Source(id: "TWN", title: "Taiwan: source summary",
               url: URL(string: "https://github.com/marc0cheung/where-can-i-go/blob/main/where-can-i-go-ios/whereCanIGo/Resources/Source/default_visas_TWN.sources.md")!),
    ]

    var body: some View {
        Form {
            Section {
                ForEach(sources) { source in
                    Link(destination: source.url) {
                        LabeledContent {
                            Image(systemName: "arrow.up.right")
                                .foregroundStyle(.secondary)
                        } label: {
                            Text(source.title)
                                .foregroundStyle(Color.primary)
                        }
                    }
                }
            } header: {
                Text("Entry Policy Sources")
            } footer: {
                Text("acknowledgements.sources.footer")
            }
        }
        .navigationTitle("Acknowledgements & Sources")
        .navigationBarTitleDisplayMode(.inline)
    }
}
