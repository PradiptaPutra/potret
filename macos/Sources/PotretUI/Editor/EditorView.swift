import AppKit
import PotretCore
import SwiftUI

/// Hosts the canvas so SwiftUI can own the chrome around it.
struct CanvasRepresentable: NSViewRepresentable {
    let model: EditorModel
    let onEditText: (AnnotationElement, CGRect, CGFloat) -> Void

    func makeNSView(context: Context) -> AnnotationCanvasView {
        let view = AnnotationCanvasView()
        view.model = model
        view.onEditText = onEditText
        return view
    }

    func updateNSView(_ view: AnnotationCanvasView, context: Context) {
        view.model = model
        // Cursor rects are cached until invalidated, so the pointer would keep showing the
        // previous tool's cursor after switching.
        view.toolDidChange()
    }
}

/// A text element being typed, positioned over the canvas exactly where it will render.
struct TextEditingSession: Equatable {
    let element: AnnotationElement
    /// View-space rect and font size, so the field matches the rendered result.
    let rect: CGRect
    let fontSize: CGFloat
}

/// The annotation editor.
public struct EditorView: View {
    @Bindable var model: EditorModel
    @State private var editing: TextEditingSession?
    @State private var draftText = ""
    @State private var showingInspector = false
    @FocusState private var textFocused: Bool

    public init(model: EditorModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            HStack(spacing: 0) {
                ZStack(alignment: .topLeading) {
                    Color(nsColor: .underPageBackgroundColor)
                    CanvasRepresentable(model: model) { element, rect, fontSize in
                        if case .text(let content) = element.kind {
                            draftText = content.string
                        }
                        editing = TextEditingSession(
                            element: element, rect: rect, fontSize: fontSize
                        )
                        textFocused = true
                    }
                    if let editing {
                        liveTextField(editing)
                    }
                }
                if showingInspector {
                    Divider()
                    BackgroundInspector(model: model)
                }
            }
        }
        .frame(minWidth: 720, minHeight: 520)
    }

    // MARK: Toolbar

    private var toolbar: some View {
        // Scrolls rather than clipping. Rendering the editor at its minimum width showed tool
        // buttons simply vanishing — a fixed HStack drops what does not fit, with no indication
        // that anything is missing.
        ScrollView(.horizontal) {
            toolbarContent
        }
        .scrollIndicators(.hidden)
        .frame(height: 34)
    }

    private var toolbarContent: some View {
        HStack(spacing: Space.xs) {
            // Undo and redo lead the toolbar, before the tools. ⌘Z works whether or not the
            // buttons are reachable, but a visible control that greys out when the stack is
            // empty is the only way the editor says out loud that a mistake is recoverable.
            Button {
                model.undo()
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .frame(width: Space.l, height: Space.l)
            }
            .buttonStyle(.accessoryBar)
            .disabled(!model.canUndo)
            .help(model.undoTitle)
            .keyboardShortcut("z", modifiers: .command)

            Button {
                model.redo()
            } label: {
                Image(systemName: "arrow.uturn.forward")
                    .frame(width: Space.l, height: Space.l)
            }
            .buttonStyle(.accessoryBar)
            .disabled(!model.canRedo)
            .help(model.redoTitle)
            .keyboardShortcut("z", modifiers: [.command, .shift])

            Divider().frame(height: Space.l)

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

            Button {
                showingInspector.toggle()
            } label: {
                Image(systemName: "photo.on.rectangle.angled")
                    .frame(width: Space.l, height: Space.l)
            }
            .buttonStyle(.accessoryBar)
            .background(
                showingInspector ? Color.accentColor.opacity(0.25) : .clear,
                in: Radius.shape(Radius.sm)
            )
            .help("Backdrop")

            Button("Done") { model.finish() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("s", modifiers: .command)
        }
        .padding(.horizontal, Space.m)
        .padding(.vertical, Space.s)
    }

    // MARK: Text

    /// Type directly on the canvas, at the position and size the text will actually render.
    ///
    /// Not a dialog floating in the middle of the window. The field sits exactly where the glyphs
    /// will land, in the ink colour, at the rendered point size — so the text is composed in
    /// place rather than typed somewhere else and dropped in afterwards. The rect and size come
    /// from the same DocumentTransform the renderer uses.
    private func liveTextField(_ session: TextEditingSession) -> some View {
        TextField("", text: $draftText)
            .textFieldStyle(.plain)
            .font(TypeRamp.ink(size: session.fontSize))
            .foregroundStyle(Color(cgColor: session.element.style.color.cgColor))
            .focused($textFocused)
            .frame(width: session.rect.width, height: session.rect.height, alignment: .leading)
            .background(
                // Just enough tint to find the caret against a busy screenshot, without hiding
                // what is underneath.
                Radius.shape(Radius.sm)
                    .fill(Color.accentColor.opacity(0.12))
                    .overlay(
                        Radius.shape(Radius.sm)
                            .strokeBorder(Color.accentColor.opacity(0.5), lineWidth: 1)
                    )
            )
            .offset(x: session.rect.minX, y: session.rect.minY)
            .onSubmit { commitText(session) }
            .onExitCommand { cancelText(session) }
            .onChange(of: draftText) { _, text in
                // Live: the document carries what has been typed so far, so the canvas behind the
                // field is already showing the real thing.
                guard case .text(var content) = session.element.kind else { return }
                content.string = text
                var updated = session.element
                updated.kind = .text(content)
                model.updateLive(updated)
            }
    }

    private func commitText(_ session: TextEditingSession) {
        defer { editing = nil }
        guard case .text(var content) = session.element.kind else { return }
        guard !draftText.trimmingCharacters(in: .whitespaces).isEmpty else {
            model.apply(.remove(session.element), name: "Text")
            return
        }
        content.string = draftText
        var updated = session.element
        updated.kind = .text(content)
        // One undoable edit for the finished string, not one per keystroke.
        model.replace(session.element, with: updated)
    }

    private func cancelText(_ session: TextEditingSession) {
        model.apply(.remove(session.element), name: "Text")
        editing = nil
    }
}
