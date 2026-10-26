import SwiftUI

struct ProfilePhotoSelection: Identifiable {
    let id = UUID()
    let image: UIImage
}

struct ProfilePhotoEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let image: UIImage
    let onChoose: (Data) -> Void

    @State private var zoom: CGFloat = 1
    @State private var offset = CGSize.zero
    @State private var cropDiameter: CGFloat = 1
    @State private var photoError: String?
    @GestureState private var adjustment = Adjustment()

    private struct Adjustment {
        var translation = CGSize.zero
        var magnification: CGFloat = 1
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                GeometryReader { geometry in
                    let diameter = max(1, min(geometry.size.width, geometry.size.height) - 32)
                    let currentZoom = clampedZoom(zoom * adjustment.magnification)
                    let currentOffset = clampedOffset(
                        CGSize(
                            width: offset.width + adjustment.translation.width,
                            height: offset.height + adjustment.translation.height),
                        diameter: diameter, zoom: currentZoom)
                    let size = displayedSize(diameter: diameter, zoom: currentZoom)

                    VStack(spacing: 0) {
                        ZStack {
                            Color.black
                            Image(uiImage: image)
                                .resizable()
                                .frame(width: size.width, height: size.height)
                                .position(
                                    x: geometry.size.width / 2 + currentOffset.width,
                                    y: geometry.size.height / 2 + currentOffset.height)

                            Path { path in
                                path.addRect(CGRect(origin: .zero, size: geometry.size))
                                path.addEllipse(
                                    in: CGRect(
                                        x: (geometry.size.width - diameter) / 2,
                                        y: (geometry.size.height - diameter) / 2,
                                        width: diameter, height: diameter))
                            }
                            .fill(.black.opacity(0.6), style: FillStyle(eoFill: true))
                            .allowsHitTesting(false)

                            Circle()
                                .stroke(.white.opacity(0.5), lineWidth: 1)
                                .frame(width: diameter, height: diameter)
                                .allowsHitTesting(false)
                        }
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture()
                                .simultaneously(with: MagnifyGesture())
                                .updating($adjustment) { value, state, _ in
                                    state.translation = value.first?.translation ?? .zero
                                    state.magnification = value.second?.magnification ?? 1
                                }
                                .onEnded { value in
                                    zoom = clampedZoom(zoom * (value.second?.magnification ?? 1))
                                    let translation = value.first?.translation ?? .zero
                                    offset = clampedOffset(
                                        CGSize(
                                            width: offset.width + translation.width,
                                            height: offset.height + translation.height),
                                        diameter: diameter, zoom: zoom)
                                }
                        )
                        .accessibilityLabel("Photo crop preview")
                        .accessibilityHint("Drag to move the photo. Pinch to scale.")
                        .onChange(of: diameter, initial: true) { _, newDiameter in
                            cropDiameter = newDiameter
                            offset = clampedOffset(offset, diameter: newDiameter, zoom: zoom)
                        }
                    }
                }
                VStack(spacing: 16) {
                    Slider(value: $zoom, in: 1...6) {
                        Text("Photo zoom")
                    }
                    .onChange(of: zoom) { _, newZoom in
                        offset = clampedOffset(offset, diameter: cropDiameter, zoom: newZoom)
                    }
                    HStack {
                        Button("Cancel") { dismiss() }
                        Spacer()
                        Button("Choose") {
                            choose(diameter: cropDiameter)
                        }
                        .fontWeight(.semibold)
                    }
                    .frame(minHeight: 44)
                }
                .padding()
                .background(.black)
            }
            .background(.black)
            .navigationTitle("Move & Scale")
            .navigationBarTitleDisplayMode(.inline)
            .alert(
                "Unable to Load Photo",
                isPresented: Binding(
                    get: { photoError != nil },
                    set: { if !$0 { photoError = nil } }
                )
            ) {
                Button("OK", role: .cancel) { photoError = nil }
            } message: {
                Text(photoError ?? "")
            }
        }
        .preferredColorScheme(.dark)
        .tint(.white)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func clampedZoom(_ value: CGFloat) -> CGFloat {
        min(max(value, 1), 6)
    }

    private func displayedSize(diameter: CGFloat, zoom: CGFloat) -> CGSize {
        let scale = max(diameter / image.size.width, diameter / image.size.height) * zoom
        return CGSize(width: image.size.width * scale, height: image.size.height * scale)
    }

    private func clampedOffset(_ value: CGSize, diameter: CGFloat, zoom: CGFloat) -> CGSize {
        let size = displayedSize(diameter: diameter, zoom: zoom)
        let limitX = max(0, (size.width - diameter) / 2)
        let limitY = max(0, (size.height - diameter) / 2)
        return CGSize(
            width: min(max(value.width, -limitX), limitX),
            height: min(max(value.height, -limitY), limitY))
    }

    private func choose(diameter: CGFloat) {
        let size = displayedSize(diameter: diameter, zoom: zoom)
        let position = clampedOffset(offset, diameter: diameter, zoom: zoom)
        let outputSide: CGFloat = 512
        let scale = outputSide / diameter
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: outputSide, height: outputSide), format: format)
        let cropped = renderer.image { context in
            UIColor.black.setFill()
            context.fill(CGRect(x: 0, y: 0, width: outputSide, height: outputSide))
            image.draw(
                in: CGRect(
                    x: (diameter / 2 + position.width - size.width / 2) * scale,
                    y: (diameter / 2 + position.height - size.height / 2) * scale,
                    width: size.width * scale, height: size.height * scale))
        }
        guard let data = cropped.jpegData(compressionQuality: 0.85) else {
            photoError = ProfilePhotoError.invalidImage.localizedDescription
            return
        }
        onChoose(data)
    }
}
