import SwiftUI
import UIKit

/// Presety minut jak w klawiaturze inline bota, plus suwak na resztę przypadków.
struct ActivitySheet: View {
    let onSave: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var minutes = 30

    private let presets = [15, 30, 45, 60, 90, 120]

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                Kicker(text: "ile ruchu dzisiaj")

                Text("\(minutes) min")
                    .font(AtlasFont.display(52))
                    .monospacedDigit()
                    .foregroundStyle(Palette.ochre)
                    .contentTransition(.numericText())
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 18)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 9), count: 3), spacing: 9) {
                    ForEach(presets, id: \.self) { value in
                        Button {
                            withAnimation(.easeOut(duration: 0.15)) { minutes = value }
                        } label: {
                            Text("\(value) min")
                                .font(AtlasFont.body(14, .medium))
                                .foregroundStyle(minutes == value ? .white : Palette.ink)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(
                                    minutes == value ? Palette.pine : Palette.card,
                                    in: RoundedRectangle(cornerRadius: 12)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Palette.line, lineWidth: minutes == value ? 0 : 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }

                Slider(value: .init(get: { Double(minutes) }, set: { minutes = Int($0) }), in: 0...240, step: 5)
                    .tint(Palette.pine)
                    .padding(.top, 20)

                Text("Zapisuje się na dzisiaj i nadpisuje wcześniejszy wpis.")
                    .font(AtlasFont.mono(10.5))
                    .foregroundStyle(Palette.muted)
                    .padding(.top, 10)

                Spacer()

                Button {
                    onSave(minutes)
                    dismiss()
                } label: {
                    Text("Zapisz")
                        .font(AtlasFont.body(15, .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(Palette.pine, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }
            .padding(20)
            .background(Palette.panel)
            .navigationTitle("Aktywność")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Anuluj") { dismiss() }.tint(Palette.muted)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Trzy pytania, które bot zadaje w `/checkin` — sen, stres, nastrój.
struct CheckinSheet: View {
    let onSave: (Int, Int, Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var sleep = 3
    @State private var stress = 3
    @State private var mood = 3

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 22) {
                scale("Jak spałeś?", subtitle: "1 = fatalnie, 5 = świetnie", value: $sleep)
                scale("Poziom stresu", subtitle: "1 = spokój, 5 = bardzo wysoki", value: $stress)
                scale("Nastrój", subtitle: "1 = kiepski, 5 = świetny", value: $mood)

                Text("Aktywność liczy się osobno — z Apple Watcha albo z przycisku w czacie.")
                    .font(AtlasFont.mono(10.5))
                    .foregroundStyle(Palette.muted)
                    .lineSpacing(3)

                Spacer()

                Button {
                    onSave(sleep, stress, mood)
                    dismiss()
                } label: {
                    Text("Zapisz check-in")
                        .font(AtlasFont.body(15, .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(Palette.pine, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }
            .padding(20)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(Palette.panel)
            .navigationTitle("Check-in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Anuluj") { dismiss() }.tint(Palette.muted)
                }
            }
        }
        .presentationDetents([.large])
    }

    private func scale(_ title: String, subtitle: String, value: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(AtlasFont.body(15, .medium))
                .foregroundStyle(Palette.ink)

            Text(subtitle)
                .font(AtlasFont.mono(10.5))
                .foregroundStyle(Palette.muted)

            HStack(spacing: 8) {
                ForEach(1...5, id: \.self) { step in
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) { value.wrappedValue = step }
                    } label: {
                        Text("\(step)")
                            .font(AtlasFont.display(17))
                            .monospacedDigit()
                            .foregroundStyle(value.wrappedValue == step ? .white : Palette.ink)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(
                                value.wrappedValue == step ? Palette.pine : Palette.card,
                                in: RoundedRectangle(cornerRadius: 12)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Palette.line, lineWidth: value.wrappedValue == step ? 0 : 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(title): \(step) z 5")
                }
            }
            .padding(.top, 2)
        }
    }
}

/// Aparat. `PhotosPicker` sięga tylko do biblioteki, a posiłek zwykle
/// fotografuje się na miejscu.
struct CameraPicker: UIViewControllerRepresentable {
    let onCapture: (Data) -> Void

    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture, onFinish: { dismiss() })
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let onCapture: (Data) -> Void
        private let onFinish: () -> Void

        init(onCapture: @escaping (Data) -> Void, onFinish: @escaping () -> Void) {
            self.onCapture = onCapture
            self.onFinish = onFinish
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            // Pełna jakość — skalowanie i kompresja i tak dzieje się w `MealPhoto`.
            if let image = info[.originalImage] as? UIImage, let data = image.jpegData(compressionQuality: 1) {
                onCapture(data)
            }
            onFinish()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onFinish()
        }
    }
}

#Preview("Aktywność") {
    ActivitySheet { _ in }
}

#Preview("Check-in") {
    CheckinSheet { _, _, _ in }
}
