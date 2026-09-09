import PotretCore
import SwiftUI

/// Backdrop controls, as an inspector beside the canvas.
///
/// Not a separate modal tool. In the Tauri app this was a 594-line full-screen overlay with its
/// own compositor, its own preview scaling and its own clipboard path — so a backdrop could not be
/// combined with annotations, was not undoable, and exported through different code than
/// everything else. Here it is a document property drawn by the same renderer.
struct BackgroundInspector: View {
    @Bindable var model: EditorModel

    private var style: Backdrop {
        model.document.background ?? Backdrop()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.l) {
                Toggle("Backdrop", isOn: enabledBinding)
                    .toggleStyle(.switch)
                    .font(TypeRamp.heading)

                if model.document.background != nil {
                    presets
                    sliders
                    Toggle("Drop shadow", isOn: shadowBinding)
                    Text(outputDescription)
                        .font(TypeRamp.mono)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(Space.m)
        }
        .frame(width: 220)
    }

    // MARK: Controls

    private var presets: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text("Style")
                .font(TypeRamp.caption)
                .foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: Space.s)], spacing: Space.s) {
                ForEach(GradientPreset.allCases, id: \.self) { preset in
                    Button {
                        update { $0.fill = .gradient(preset) }
                    } label: {
                        LinearGradient(
                            colors: preset.stops.map { Color(cgColor: $0.cgColor) },
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .frame(height: 34)
                        .clipShape(Radius.shape(Radius.sm))
                        .overlay(
                            Radius.shape(Radius.sm)
                                .strokeBorder(
                                    isSelected(preset) ? Color.accentColor : Color.primary.opacity(0.15),
                                    lineWidth: isSelected(preset) ? 2 : 0.5
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .help(preset.name)
                }
            }
        }
    }

    private var sliders: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            labelled("Padding") {
                Slider(
                    value: Binding(
                        get: { style.paddingFraction },
                        set: { value in update { $0.paddingFraction = value } }
                    ),
                    in: 0.01...0.25
                )
            }
            labelled("Corners") {
                Slider(
                    value: Binding(
                        get: { style.cornerFraction },
                        set: { value in update { $0.cornerFraction = value } }
                    ),
                    in: 0...0.06
                )
            }
        }
    }

    private func labelled(_ title: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(TypeRamp.caption)
                .foregroundStyle(.secondary)
            content()
        }
    }

    /// The old tool never told you how big the result would be.
    private var outputDescription: String {
        let size = model.document.outputSize
        return "\(Int(size.width)) × \(Int(size.height))"
    }

    private func isSelected(_ preset: GradientPreset) -> Bool {
        if case .gradient(let current) = style.fill { return current == preset }
        return false
    }

    // MARK: Bindings

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { model.document.background != nil },
            set: { on in
                model.apply(
                    .setBackground(old: model.document.background, new: on ? Backdrop() : nil),
                    name: "Backdrop"
                )
            }
        )
    }

    private var shadowBinding: Binding<Bool> {
        Binding(
            get: { style.shadow != nil },
            set: { on in update { $0.shadow = on ? .default : nil } }
        )
    }

    /// Every change is one undoable edit, so the backdrop participates in Cmd+Z like anything else.
    private func update(_ mutate: (inout Backdrop) -> Void) {
        var next = style
        mutate(&next)
        model.apply(
            .setBackground(old: model.document.background, new: next),
            name: "Backdrop"
        )
    }
}
