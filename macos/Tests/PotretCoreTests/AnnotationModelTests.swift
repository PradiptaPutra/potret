import CoreGraphics
import Foundation
import Testing
@testable import PotretCore

@Suite("Annotation model")
struct AnnotationModelTests {
    private let style = AnnotationElement.Style(color: AnnotationPalette.red)

    private func element(_ kind: AnnotationElement.Kind) -> AnnotationElement {
        AnnotationElement(kind: kind, style: style)
    }

    // MARK: Hit testing

    @Test("A stroked rectangle is hit on its outline, not its empty middle")
    func rectangleHitsOutlineOnly() {
        // Clicking inside an empty outline should not select it — otherwise a large rectangle
        // swallows every click over everything beneath it.
        let rect = element(.rectangle(CGRect(x: 10, y: 10, width: 100, height: 100)))
        #expect(rect.contains(CGPoint(x: 10, y: 50)))
        #expect(rect.contains(CGPoint(x: 110, y: 50)))
        #expect(!rect.contains(CGPoint(x: 60, y: 60)))
        #expect(!rect.contains(CGPoint(x: 200, y: 200)))
    }

    @Test("An effect region is hit anywhere inside it")
    func effectsAreFilled() {
        // Pixelate and blur are filled areas, so their middle is part of them.
        let pixelate = element(.pixelate(CGRect(x: 0, y: 0, width: 50, height: 50)))
        #expect(pixelate.contains(CGPoint(x: 25, y: 25)))
    }

    @Test("A line is hit near the stroke and missed away from it")
    func lineProximity() {
        let line = element(.line(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 100, y: 0)))
        #expect(line.contains(CGPoint(x: 50, y: 3)))
        #expect(!line.contains(CGPoint(x: 50, y: 40)))
        // Past the end, not merely near the infinite line it lies on.
        #expect(!line.contains(CGPoint(x: 160, y: 0)))
    }

    @Test("Freehand is hit near any segment")
    func freehandProximity() {
        let path = element(.freehand([
            CGPoint(x: 0, y: 0), CGPoint(x: 50, y: 0), CGPoint(x: 50, y: 50),
        ]))
        #expect(path.contains(CGPoint(x: 50, y: 25)))
        #expect(!path.contains(CGPoint(x: 0, y: 50)))
    }

    @Test("A step badge is hit within its radius")
    func stepProximity() {
        let step = element(.step(center: CGPoint(x: 100, y: 100), number: 1))
        #expect(step.contains(CGPoint(x: 105, y: 105)))
        #expect(!step.contains(CGPoint(x: 160, y: 100)))
    }

    @Test("Hit testing returns the front-most element")
    func frontMostWins() {
        let back = element(.pixelate(CGRect(x: 0, y: 0, width: 100, height: 100)))
        let front = element(.pixelate(CGRect(x: 0, y: 0, width: 100, height: 100)))
        let document = AnnotationDocument(
            sourceSize: CGSize(width: 200, height: 200),
            elements: [back, front]
        )
        #expect(document.hitTest(CGPoint(x: 50, y: 50))?.id == front.id)
    }

    // MARK: Moving

    @Test("Every kind moves by the same delta")
    func movingIsUniform() {
        let delta = CGVector(dx: 10, dy: -5)
        let kinds: [AnnotationElement.Kind] = [
            .rectangle(CGRect(x: 0, y: 0, width: 10, height: 10)),
            .ellipse(CGRect(x: 0, y: 0, width: 10, height: 10)),
            .line(from: .zero, to: CGPoint(x: 10, y: 10)),
            .arrow(from: .zero, to: CGPoint(x: 10, y: 10)),
            .freehand([.zero, CGPoint(x: 5, y: 5)]),
            .highlight([.zero, CGPoint(x: 5, y: 5)]),
            .text(.init(string: "hi", origin: .zero, fontSize: 12)),
            .step(center: .zero, number: 1),
            .pixelate(CGRect(x: 0, y: 0, width: 10, height: 10)),
            .blur(CGRect(x: 0, y: 0, width: 10, height: 10)),
        ]
        for kind in kinds {
            let original = element(kind)
            let moved = original.moved(by: delta)
            #expect(moved.boundingBox.minX == original.boundingBox.minX + 10)
            #expect(moved.boundingBox.minY == original.boundingBox.minY - 5)
            #expect(moved.id == original.id) // moving is not a new element
        }
    }

    // MARK: Step numbering

    @Test("Step numbers reuse freed values after an undo")
    func stepNumbersAreDerived() {
        // The Tauri editor kept a monotonic counter it never decremented, so undoing step 3 and
        // drawing again produced 1, 2, 4.
        var document = AnnotationDocument(sourceSize: CGSize(width: 100, height: 100))
        #expect(document.nextStepNumber == 1)

        document.elements.append(element(.step(center: .zero, number: 1)))
        document.elements.append(element(.step(center: .zero, number: 2)))
        #expect(document.nextStepNumber == 3)

        document.elements.removeLast()
        #expect(document.nextStepNumber == 2)
    }

    // MARK: Undo

    @Test("Every edit is exactly reversed by its inverse")
    func editsRoundTrip() {
        let original = AnnotationDocument(
            sourceSize: CGSize(width: 100, height: 100),
            elements: [element(.rectangle(CGRect(x: 1, y: 2, width: 3, height: 4)))]
        )
        let existing = original.elements[0]
        let edits: [DocumentEdit] = [
            .add(element(.ellipse(CGRect(x: 5, y: 5, width: 5, height: 5)))),
            .remove(existing),
            .replace(old: existing, new: existing.moved(by: CGVector(dx: 3, dy: 3))),
            .setCrop(old: nil, new: CGRect(x: 0, y: 0, width: 50, height: 50)),
        ]

        for edit in edits {
            var document = original
            edit.apply(to: &document)
            #expect(document != original, "edit should change the document")
            edit.inverse.apply(to: &document)
            #expect(document == original, "inverse should restore it exactly")
        }
    }

    @Test("A random sequence of edits undoes back to the original")
    func randomSequenceUndoes() {
        // Property test: the invariant that makes undo trustworthy is that applying N edits and
        // then their inverses in reverse order returns the exact starting document.
        var generator = SystemRandomNumberGenerator()
        for _ in 0..<50 {
            let original = AnnotationDocument(sourceSize: CGSize(width: 200, height: 200))
            var document = original
            var applied: [DocumentEdit] = []

            for _ in 0..<Int.random(in: 1...8, using: &generator) {
                let edit: DocumentEdit
                if document.elements.isEmpty || Bool.random(using: &generator) {
                    edit = .add(
                        element(.rectangle(CGRect(
                            x: CGFloat.random(in: 0...100, using: &generator),
                            y: CGFloat.random(in: 0...100, using: &generator),
                            width: 10, height: 10
                        )))
                    )
                } else {
                    edit = .remove(document.elements.randomElement(using: &generator)!)
                }
                edit.apply(to: &document)
                applied.append(edit)
            }

            for edit in applied.reversed() {
                edit.inverse.apply(to: &document)
            }
            #expect(document == original)
        }
    }

    @Test("Crop is a normal undoable edit, not a rasterise")
    func cropIsUndoable() {
        // The Tauri crop baked every annotation into the image and cleared undo/redo entirely.
        var document = AnnotationDocument(
            sourceSize: CGSize(width: 100, height: 100),
            elements: [element(.rectangle(CGRect(x: 10, y: 10, width: 20, height: 20)))]
        )
        let crop = DocumentEdit.setCrop(old: nil, new: CGRect(x: 5, y: 5, width: 40, height: 40))
        crop.apply(to: &document)

        #expect(document.visibleRect == CGRect(x: 5, y: 5, width: 40, height: 40))
        #expect(document.elements.count == 1, "cropping must not destroy annotations")

        crop.inverse.apply(to: &document)
        #expect(document.cropRect == nil)
        #expect(document.visibleRect == CGRect(x: 0, y: 0, width: 100, height: 100))
    }
}
