import CoreGraphics
import Foundation
import Testing
@testable import PotretCore

@Suite("Document transform")
struct DocumentTransformTests {
    @Test("Round-trips a point at any scale and offset")
    func roundTrips() {
        // The absence of this guarantee is the shipped Retina text bug: the editor placed its text
        // input in one space and drew the text in another, so on a 2x capture the glyph landed at
        // twice the intended offset.
        let point = CGPoint(x: 123.5, y: 87.25)
        for scale in [0.25, 0.5, 1.0, 2.0, 3.7] as [CGFloat] {
            for offset in [CGVector.zero, CGVector(dx: 40, dy: -18)] {
                let transform = DocumentTransform(scale: scale, offset: offset)
                let there = transform.toView(point)
                let back = transform.toDocument(there)
                #expect(abs(back.x - point.x) < 0.0001)
                #expect(abs(back.y - point.y) < 0.0001)
            }
        }
    }

    @Test("Round-trips a rect")
    func roundTripsRect() {
        let rect = CGRect(x: 10, y: 20, width: 300, height: 200)
        let transform = DocumentTransform(scale: 2, offset: CGVector(dx: 15, dy: 5))
        let back = transform.toDocument(transform.toView(rect))
        #expect(abs(back.minX - rect.minX) < 0.0001)
        #expect(abs(back.width - rect.width) < 0.0001)
    }

    @Test("Lengths scale with the view, so a 3pt stroke stays 3pt at 1:1")
    func lengthsScale() {
        #expect(DocumentTransform(scale: 1).toView(length: 3) == 3)
        #expect(DocumentTransform(scale: 2).toView(length: 3) == 6)
        #expect(DocumentTransform(scale: 0.5).toView(length: 3) == 1.5)
    }

    @Test("Fitting centres the document in the viewport")
    func fittingCentres() {
        let transform = DocumentTransform.fitting(
            document: CGSize(width: 100, height: 100),
            in: CGSize(width: 300, height: 200)
        )
        // Not upscaled by default, so scale stays 1 and it is centred in both axes.
        #expect(transform.scale == 1)
        #expect(transform.offset.dx == 100)
        #expect(transform.offset.dy == 50)
    }

    @Test("Fitting shrinks an oversized document to fit the shorter axis")
    func fittingShrinks() {
        let transform = DocumentTransform.fitting(
            document: CGSize(width: 4000, height: 1000),
            in: CGSize(width: 1000, height: 1000)
        )
        #expect(transform.scale == 0.25)
        #expect(transform.offset.dx == 0)
        #expect(transform.offset.dy == 375) // (1000 - 250) / 2
    }

    @Test("Fitting does not magnify unless asked")
    func fittingDoesNotUpscaleByDefault() {
        // A small crop blown up to fill the window looks broken; the Tauri editor capped with
        // maxWidth: 100% for the same reason.
        let small = CGSize(width: 50, height: 50)
        let viewport = CGSize(width: 500, height: 500)
        #expect(DocumentTransform.fitting(document: small, in: viewport).scale == 1)
        #expect(
            DocumentTransform.fitting(document: small, in: viewport, allowUpscaling: true).scale
                == 10
        )
    }

    @Test("A zero-sized document does not divide by zero")
    func degenerateDocument() {
        let transform = DocumentTransform.fitting(document: .zero, in: CGSize(width: 10, height: 10))
        #expect(transform.scale == 1)
    }
}
