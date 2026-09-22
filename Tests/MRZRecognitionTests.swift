import Foundation
import Testing
import CoreGraphics
import CoreText
import ImageIO
@testable import SesamePassSecurity

private func syntheticPage(_ lines: [String]) throws -> Data {
    let context = try #require(CGContext(data: nil, width: 1500, height: 420, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 1500, height: 420))
    let font = CTFontCreateWithName("Menlo" as CFString, 40, nil)
    for (index, text) in lines.enumerated() {
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1)
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        context.textPosition = CGPoint(x: 70, y: 280 - index * 90)
        CTLineDraw(line, context)
    }
    let image = try #require(context.makeImage())
    let data = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, nil)
    #expect(CGImageDestinationFinalize(destination))
    return data as Data
}

@Test func visionReadsSyntheticPassportImage() async throws {
    // Public ICAO specimen; never use a real passport as a test fixture.
    let lines = ["P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<", "L898902C36UTO7408122F1204159ZE184226B<<<<<10"]
    let image = try syntheticPage(lines)
    let result = try await MRZRecognition().recognize(image)
    #expect(result == (try MRZAccess.parseTD3(lines.joined(separator: "\n"))))
}

@Test func visionRejectsImageWithoutPassportAccessData() async throws {
    let image = try syntheticPage(["THIS IS NOT A PASSPORT"])
    do {
        _ = try await MRZRecognition().recognize(image)
        Issue.record("An unrelated image must not produce access data")
    } catch is MRZError { }
}

@Test func visionReadsSyntheticTD1CardImage() async throws {
    let first = "I<UTOD231458907".padding(toLength: 30, withPad: "<", startingAt: 0)
    let second = "7408122F1204159UTO".padding(toLength: 29, withPad: "<", startingAt: 0) + "6"
    let name = "ERIKSSON<<ANNA<MARIA".padding(toLength: 30, withPad: "<", startingAt: 0)
    let lines = [first, second, name]
    let image = try syntheticPage(lines)
    let access = try await MRZRecognition().recognize(image, kind: .identityCard)
    #expect(access == (try MRZAccess.parseTD1(lines.joined(separator: "\n"))))
}
