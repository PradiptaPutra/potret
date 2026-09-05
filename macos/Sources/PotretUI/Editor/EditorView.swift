import AppKit
import PotretCore
import SwiftUI

/// Hosts the canvas so SwiftUI can own the chrome around it.
struct CanvasRepresentable: NSViewRepresentable {
    let model: EditorModel
    let onEditText: (AnnotationElement) -> Void

    func makeNSView(context: Context) -> AnnotationCanvasView {
        let view = AnnotationCanvasView()
        view.model = model
        view.onEditText = onEditText
        return view
    }

    func updateNSView(_ view: AnnotationCanvasView, context: Context) {
        view.model = model
        view.needsDisplay = true
    }
}

/// The annotation editor.
public struct EditorView: View {
    @Bindable var model: EditorModel
    @State private var editingElement: AnnotationElement?
    @State private var draftText = ""

    public init(model: EditorModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            ZStack {
                Color(nsColor: .underPageBackgroundColor)
                CanvasRepresentable(model: model) { element in
                    editingElement = element
                    draftText = ""
                }
                if let editingElement {
                    textEditor(for: editingElement)
                }
            }
        }
        .frame(minWidth: 720, minHeight: 520)
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: Space.xs) {
            ForEach(EditorTool.allCases, id: \.self) { tool in
                Button {
                    model.tool = tool
                } label: {
                    Image(systemName: tool.symbol)
                        .frame(width: Space.l, height: Space.l)
                }
                .buttonStyle(.accessoryBar)
                .background(
                    model.tool == tool
                        ? Color.accentColor.opacity(0.25) : .clear,
                    in: Radius.shape(Radius.sm)
                )
                // Every tool has a single-key shortcut; the Tauri editor had none at all.
                .help("\(tool.label) (\(tool.key.uppercased()))")
                .keyboardShortcut(KeyEquivalent(Character(tool.key)), modifiers: [])
            }

            Divider().frame(height: Space.l)

            ForEach(AnnotationPalette.all, id: \.self) { ink in
                Button {
                    model.color = ink
                } label: {
                    Circle()
                        .fill(Color(cgColor: ink.cgColor))
                        .frame(width: Space.m, height: Space.m)
                        .overlay(
                            Circle().strokeBorder(
                                model.color == ink ? Color.primary : Color.primary.opacity(0.2),
                                lineWidth: model.color == ink ? 2 : 0.5
                            )
                        )
                }
                .buttonStyle(.plain)
                .help("Ink colour")
            }

            // The width control the old editor's data model implied and never offered.
            Slider(value: $model.lineWidth, in: 1...16, step: 1)
                .frame(width: 90)
                .help("Stroke width")

            Spacer(minLength: Space.s)

            Button("Done") { model.finish() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("s", modifiers: .command)
        }
        .padding(.horizontal, Space.m)
        .padding(.vertical, Space.s)
    }

    // MARK: Text

    /// Text is edited in a real field positioned by the same transform that renders it, so what is
    /// typed is where it lands. The Tauri editor placed a 12px input in CSS pixels and drew 30px
    /// text in canvas pixels.
    private func textEditor(for element: AnnotationElement) -> some View {
        VStack {
            TextField("Type, then press Return", text: $draftText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 260)
                .onSubmit { commitText(for: element) }
                .onExitCommand { cancelText(for: element) }
            Text("Return to place · Esc to cancel")
                .font(TypeRamp.caption)
                .foregroundStyle(.secondary)
        }
        .padding(Space.m)
        .potretSurface(.popover, radius: Radius.md)
    }

    private func commitText(for element: AnnotationElement) {
        defer { editingElement = nil }
        guard case .text(var content) = element.kind else { return }
        guard !draftText.trimmingCharacters(in: .whitespaces).isEmpty else {
            model.apply(.remove(element), name: "Text")
            return
        }
        content.string = draftText
        var updated = element
        updated.kind = .text(content)
        model.replace(element, with: updated)
    }

    private func cancelText(for element: AnnotationElement) {
        model.apply(.remove(element), name: "Text")
        editingElement = nil
    }
}
