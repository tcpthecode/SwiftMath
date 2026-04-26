import XCTest
@testable import SwiftMath

#if os(iOS) || os(visionOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Visual regression tests for `MTMathStringParser.decode`.
///
/// Each test encodes a mixed string, decodes it into an `NSAttributedString` with
/// math image attachments, renders the result via `NSLayoutManager`, and writes the
/// PNG to the system temp directory. Open the saved files to verify visually.
///
/// Run individual tests with:
///   swift test --filter MTMathStringParserDecodeVisualTests.<testName>
final class MTMathStringParserDecodeVisualTests: XCTestCase {

    // MARK: - Rendering helpers

    /// Renders an attributed string (including NSTextAttachment images) into an MTImage
    /// using the NSLayoutManager pipeline, with a white background and 16 pt padding.
    /// NSLayoutManager is available on both iOS and macOS and handles attachments correctly.
    private func render(_ attrStr: NSAttributedString, maxWidth: CGFloat = 600) -> MTImage? {
        let textStorage = NSTextStorage(attributedString: attrStr)
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)

        let container = NSTextContainer(size: CGSize(width: maxWidth, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        layoutManager.addTextContainer(container)

        layoutManager.ensureLayout(for: container)
        let used = layoutManager.usedRect(for: container)

        let padding: CGFloat = 16
        let imageSize = CGSize(
            width: ceil(used.width) + padding * 2,
            height: ceil(used.height) + padding * 2
        )
        let glyphRange = layoutManager.glyphRange(for: container)
        let origin = CGPoint(x: padding, y: padding)

        #if os(iOS) || os(visionOS)
        let renderer = UIGraphicsImageRenderer(size: imageSize)
        return renderer.image { _ in
            UIColor.white.setFill()
            UIBezierPath(rect: CGRect(origin: .zero, size: imageSize)).fill()
            layoutManager.drawBackground(forGlyphRange: glyphRange, at: origin)
            layoutManager.drawGlyphs(forGlyphRange: glyphRange, at: origin)
        }
        #elseif os(macOS)
        // flipped: true gives a top-left origin matching NSLayoutManager's drawing direction.
        return NSImage(size: imageSize, flipped: true) { _ in
            NSColor.white.setFill()
            NSBezierPath.fill(NSRect(origin: .zero, size: imageSize))
            layoutManager.drawBackground(forGlyphRange: glyphRange, at: origin)
            layoutManager.drawGlyphs(forGlyphRange: glyphRange, at: origin)
            return true
        }
        #endif
    }

    /// Saves an MTImage as PNG to the system temp directory and prints the path.
    @discardableResult
    private func save(_ image: MTImage, as name: String) -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("\(name).png")
        #if os(iOS) || os(visionOS)
        if let data = image.pngData() {
            try? data.write(to: url)
        }
        #elseif os(macOS)
        if let data = image.pngData() {
            try? data.write(to: url)
        }
        #endif
        print("Saved: \(url.path)")
        return url
    }

    /// Full pipeline: encode the input, apply font + color to the encoded string, decode.
    private func makeDecoded(
        _ input: String,
        fontSize: CGFloat,
        color: MTColor = .black,
        placeholderLabel: String = "citation",
        options: MTMathStringParser.ParseOptions = .default
    ) -> NSAttributedString {
        let (encoded, entries) = MTMathStringParser.encode(
            input,
            placeholderLabel: placeholderLabel,
            options: options
        )

        #if os(iOS) || os(visionOS)
        let font = UIFont.systemFont(ofSize: fontSize)
        #elseif os(macOS)
        let font = NSFont.systemFont(ofSize: fontSize)
        #endif

        let attrStr = NSAttributedString(
            string: encoded,
            attributes: [.font: font, .foregroundColor: color]
        )

        return MTMathStringParser.decode(
            attrStr,
            encodedArray: entries,
            placeholderLabel: placeholderLabel
        )
    }

    // MARK: - Visual tests

    /// Sentence containing an inline quadratic formula and a short inline condition.
    func testVisualInlineMathInSentence() throws {
        let input = "The quadratic formula: \\( x = \\frac{-b \\pm \\sqrt{b^2 - 4ac}}{2a} \\) where \\( a \\neq 0 \\)."
        let decoded = makeDecoded(input, fontSize: 18)

        let image = try XCTUnwrap(render(decoded), "Rendering failed")
        save(image, as: "decode-visual-inline-sentence")

        XCTAssertFalse(decoded.string.contains("[citation:"), "No raw placeholders should remain")
        XCTAssertTrue(decoded.string.contains("\u{FFFC}"), "Attachment characters should be present")
    }

    /// A single display-mode formula, rendered at 24 pt.
    func testVisualDisplayMathAlone() throws {
        let input = "\\[ E = mc^2 \\]"
        let decoded = makeDecoded(input, fontSize: 24)

        let image = try XCTUnwrap(render(decoded), "Rendering failed")
        save(image, as: "decode-visual-display-alone")

        XCTAssertFalse(decoded.string.contains("[citation:"))
        XCTAssertTrue(decoded.string.contains("\u{FFFC}"))
    }

    /// Mixed inline and display formulas across multiple sentences.
    func testVisualMixedInlineAndDisplay() throws {
        let input = """
        Area of a circle: \\( A = \\pi r^2 \\). \
        The general integral form is:
        \\[ \\int_a^b f(x)\\, dx = F(b) - F(a) \\]
        where \\( F \\) is the antiderivative of \\( f \\).
        """
        let decoded = makeDecoded(input, fontSize: 16)

        let image = try XCTUnwrap(render(decoded, maxWidth: 500), "Rendering failed")
        save(image, as: "decode-visual-mixed")

        // 4 unique math expressions, 4 attachment occurrences
        let attachments = decoded.string.filter { $0 == "\u{FFFC}" }.count
        XCTAssertEqual(attachments, 4)
    }

    /// Identical formulas share one encoded entry and both render as the same image.
    func testVisualDeduplicatedFormulas() throws {
        let input = "First: \\( a + b \\). Second: \\( a + b \\). Third: \\( c + d \\)."
        let (_, entries) = MTMathStringParser.encode(input)
        XCTAssertEqual(entries.count, 2, "Only 2 unique math expressions")

        let decoded = makeDecoded(input, fontSize: 18)
        let image = try XCTUnwrap(render(decoded), "Rendering failed")
        save(image, as: "decode-visual-deduplicated")

        let attachments = decoded.string.filter { $0 == "\u{FFFC}" }.count
        XCTAssertEqual(attachments, 3)
    }

    /// 12 pt and 32 pt font sizes — verify the math image height scales with font size.
    func testVisualFontSizeScaling() throws {
        let input = "\\( \\frac{x}{y} \\)"

        let smallDecoded = makeDecoded(input, fontSize: 12)
        let largeDecoded = makeDecoded(input, fontSize: 32)

        let smallImage = try XCTUnwrap(render(smallDecoded), "Small render failed")
        let largeImage = try XCTUnwrap(render(largeDecoded), "Large render failed")

        save(smallImage, as: "decode-visual-font-small")
        save(largeImage, as: "decode-visual-font-large")

        XCTAssertGreaterThan(largeImage.size.height, smallImage.size.height,
                             "Larger font should produce a taller rendered image")
    }

    /// Math rendered in system blue to verify color attribute is passed through.
    func testVisualColoredMath() throws {
        let input = "Blue: \\( x^2 + y^2 = z^2 \\)"
        let decoded = makeDecoded(input, fontSize: 18, color: .systemBlue)

        let image = try XCTUnwrap(render(decoded), "Rendering failed")
        save(image, as: "decode-visual-colored")

        XCTAssertFalse(decoded.string.contains("[citation:"))
    }

    /// Encode and decode with a custom placeholder label "formula".
    func testVisualCustomPlaceholderLabel() throws {
        let input = "Euler's identity: \\( e^{i\\pi} + 1 = 0 \\)"
        let decoded = makeDecoded(input, fontSize: 20, placeholderLabel: "formula")

        let image = try XCTUnwrap(render(decoded), "Rendering failed")
        save(image, as: "decode-visual-custom-label")

        XCTAssertFalse(decoded.string.contains("[formula:"))
        XCTAssertTrue(decoded.string.contains("\u{FFFC}"))
    }

    /// Dollar signs stay as literal currency text when using .backslashOnly option.
    func testVisualCurrencyStringWithBackslashOnly() throws {
        let input = "Coupon payments: $10 per year. Present value: \\( PV = \\frac{C}{r} \\)"
        let decoded = makeDecoded(input, fontSize: 16, options: .backslashOnly)

        let image = try XCTUnwrap(render(decoded), "Rendering failed")
        save(image, as: "decode-visual-currency-safe")

        XCTAssertTrue(decoded.string.contains("$10"), "Currency $ should be preserved as plain text")
        XCTAssertTrue(decoded.string.contains("\u{FFFC}"), "\\(...\\) formula should still become an attachment")
    }
}
