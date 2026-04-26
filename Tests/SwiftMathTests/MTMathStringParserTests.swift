import XCTest
@testable import SwiftMath

final class MTMathStringParserTests: XCTestCase {

    func testPlainTextOnly() {
        let result = MTMathStringParser.parse("lorem ipsum")
        XCTAssertEqual(result, [.text("lorem ipsum")])
    }

    func testInlineParens() {
        let result = MTMathStringParser.parse("before \\( a + b \\) after")
        XCTAssertEqual(result, [
            .text("before "),
            .inlineMath(" a + b "),
            .text(" after"),
        ])
    }

    func testDisplayBrackets() {
        let result = MTMathStringParser.parse("see \\[ x = y \\] above")
        XCTAssertEqual(result, [
            .text("see "),
            .displayMath(" x = y "),
            .text(" above"),
        ])
    }

    func testInlineDollar() {
        let result = MTMathStringParser.parse("value $n$.")
        XCTAssertEqual(result, [
            .text("value "),
            .inlineMath("n"),
            .text("."),
        ])
    }

    func testDisplayDoubleDollar() {
        let result = MTMathStringParser.parse("$$E = mc^2$$")
        XCTAssertEqual(result, [.displayMath("E = mc^2")])
    }

    func testDoubleDollarCheckedBeforeSingleDollar() {
        // $$...$$ must not be parsed as two empty $$ segments surrounding content.
        let result = MTMathStringParser.parse("$$x + y$$")
        XCTAssertEqual(result, [.displayMath("x + y")])
    }

    func testMixedInlineAndDisplay() {
        let result = MTMathStringParser.parse("lorem \\( a + b = c \\) and \\[ d + e = f \\] end")
        XCTAssertEqual(result, [
            .text("lorem "),
            .inlineMath(" a + b = c "),
            .text(" and "),
            .displayMath(" d + e = f "),
            .text(" end"),
        ])
    }

    func testMultipleInlineSegments() {
        let result = MTMathStringParser.parse("\\(x\\) and \\(y\\)")
        XCTAssertEqual(result, [
            .inlineMath("x"),
            .text(" and "),
            .inlineMath("y"),
        ])
    }

    func testEmptyInput() {
        XCTAssertEqual(MTMathStringParser.parse(""), [])
    }

    func testMathOnly() {
        let result = MTMathStringParser.parse("\\( a + b \\)")
        XCTAssertEqual(result, [.inlineMath(" a + b ")])
    }

    func testUnclosedDelimiterTreatedAsText() {
        // \( with no matching \) — the opener stays as plain text
        let result = MTMathStringParser.parse("text \\( no close")
        XCTAssertEqual(result, [.text("text \\( no close")])
    }

    // MARK: - ParseOptions

    func testBackslashOnlyOptionIgnoresDollar() {
        let result = MTMathStringParser.parse("value $n$.", options: .backslashOnly)
        XCTAssertEqual(result, [.text("value $n$.")])
    }

    func testBackslashOnlyOptionIgnoresDoubleDollar() {
        let result = MTMathStringParser.parse("$$E = mc^2$$", options: .backslashOnly)
        XCTAssertEqual(result, [.text("$$E = mc^2$$")])
    }

    func testBackslashOnlyOptionStillRecognisesBackslashDelimiters() {
        let result = MTMathStringParser.parse("$10 and \\( x + y \\) end", options: .backslashOnly)
        XCTAssertEqual(result, [
            .text("$10 and "),
            .inlineMath(" x + y "),
            .text(" end"),
        ])
    }

    func testDefaultOptionBehaviourUnchanged() {
        // Explicit .default should behave identically to omitting the parameter.
        let withDefault = MTMathStringParser.parse("value $n$.", options: .default)
        let withoutOption = MTMathStringParser.parse("value $n$.")
        XCTAssertEqual(withDefault, withoutOption)
    }

    // MARK: - Currency dollar sign ambiguity

    // This test documents a known limitation: the parser cannot distinguish a currency
    // "$" from a LaTeX math delimiter "$". Every even-positioned "$" is treated as an
    // opening delimiter and paired with the next "$" as its close. The content between
    // the pair becomes an inlineMath segment even though it is plain currency text.
    //
    // Input:  *   Năm 1: $10
    //         *   Năm 2: $10
    //         *   Năm 3: $10
    //         *   Năm 4: $10 + $100 (mệnh giá) = $110
    //
    // Pairs formed:   $10\n*   Năm 2: $   →  inlineMath("10\n*   Năm 2: ")
    //                 $10\n*   Năm 4: $   →  inlineMath("10\n*   Năm 4: ")
    //                 $100 (mệnh giá) = $ →  inlineMath("100 (mệnh giá) = ")
    //                 "110" is left over as trailing text, no closing $ for it.
    //
    // If your input can contain currency "$" signs, pre-escape them to "\$" or
    // use a different delimiter convention (e.g. \(...\) for all math expressions)
    // before passing the string to this parser.
    func testCurrencyDollarAmbiguityWithDefaultOptions() {
        let input = "*   Năm 1: $10\n*   Năm 2: $10\n*   Năm 3: $10\n*   Năm 4: $10 + $100 (mệnh giá) = $110"
        let result = MTMathStringParser.parse(input)

        XCTAssertEqual(result, [
            .text("*   Năm 1: "),
            .inlineMath("10\n*   Năm 2: "),    // wrongly parsed as math
            .text("10\n*   Năm 3: "),
            .inlineMath("10\n*   Năm 4: "),    // wrongly parsed as math
            .text("10 + "),
            .inlineMath("100 (mệnh giá) = "),  // wrongly parsed as math
            .text("110"),                       // no closing $ — left as plain text
        ])
    }

    func testCurrencyDollarCorrectWithBackslashOnly() {
        let input = "*   Năm 1: $10\n*   Năm 2: $10\n*   Năm 3: $10\n*   Năm 4: $10 + $100 (mệnh giá) = $110"
        let result = MTMathStringParser.parse(input, options: .backslashOnly)

        XCTAssertEqual(result, [.text(input)])
    }

    // MARK: - encode

    func testEncodeExampleFromSpec() {
        let input = "lorem \\( a + b = c \\) ipsum \\[ d + e = f \\] and \\(a + b = c \\) ..."
        let (string, encodedArray) = MTMathStringParser.encode(input)

        XCTAssertEqual(string, "lorem [citation:0] ipsum [citation:1] and [citation:0] ...")
        XCTAssertEqual(encodedArray, [
            .inline("a + b = c"),
            .display("d + e = f"),
        ])
    }

    func testEncodeDeduplicatesTrimmedContent() {
        // Leading/trailing spaces around math content are stripped before deduplication.
        let (string, encodedArray) = MTMathStringParser.encode("\\( x \\) and \\(x\\) and \\(  x  \\)")

        XCTAssertEqual(string, "[citation:0] and [citation:0] and [citation:0]")
        XCTAssertEqual(encodedArray, [.inline("x")])
    }

    func testEncodeInlineAndDisplayWithSameContentAreDistinct() {
        // Same LaTeX content but different delimiter type → separate entries.
        let (string, encodedArray) = MTMathStringParser.encode("\\( x \\) and \\[ x \\]")

        XCTAssertEqual(string, "[citation:0] and [citation:1]")
        XCTAssertEqual(encodedArray, [.inline("x"), .display("x")])
    }

    func testEncodePlainTextOnly() {
        let (string, encodedArray) = MTMathStringParser.encode("no math here")

        XCTAssertEqual(string, "no math here")
        XCTAssertEqual(encodedArray, [])
    }

    func testEncodeMathOnly() {
        let (string, encodedArray) = MTMathStringParser.encode("\\( x + y \\)")

        XCTAssertEqual(string, "[citation:0]")
        XCTAssertEqual(encodedArray, [.inline("x + y")])
    }

    func testEncodePreservesTextBetweenCitations() {
        let (string, encodedArray) = MTMathStringParser.encode("a \\(x\\) b \\(y\\) c")

        XCTAssertEqual(string, "a [citation:0] b [citation:1] c")
        XCTAssertEqual(encodedArray, [.inline("x"), .inline("y")])
    }

    func testEncodeCustomEncodedText() {
        let input = "lorem \\( a + b = c \\) ipsum \\[ d + e = f \\] and \\(a + b = c \\) ..."
        let (string, encodedArray) = MTMathStringParser.encode(input, placeholderLabel: "ref")

        XCTAssertEqual(string, "lorem [ref:0] ipsum [ref:1] and [ref:0] ...")
        XCTAssertEqual(encodedArray, [.inline("a + b = c"), .display("d + e = f")])
    }

    func testEncodeRespectsBackslashOnlyOption() {
        let input = "price $10 and \\( x \\)"
        let (string, encodedArray) = MTMathStringParser.encode(input, options: .backslashOnly)

        XCTAssertEqual(string, "price $10 and [citation:0]")
        XCTAssertEqual(encodedArray, [.inline("x")])
    }

    func testSegmentsCanBePassedToBuilder() {
        let input = "Area: \\( A = \\pi r^2 \\), result."
        let segments = MTMathStringParser.parse(input)

        for segment in segments {
            if case .inlineMath(let latex) = segment {
                var error: NSError?
                let list = MTMathListBuilder.build(fromString: latex, error: &error)
                XCTAssertNil(error, "Builder error: \(error!)")
                XCTAssertNotNil(list)
            }
        }
    }

    // MARK: - decode

    // The Object Replacement Character (U+FFFC) is what NSTextAttachment inserts.
    private let attachmentChar = "\u{FFFC}"

    func testDecodeReplacesPlaceholderWithAttachment() {
        let (encoded, entries) = MTMathStringParser.encode("hello \\( x + y \\) world")
        // encoded = "hello [citation:0] world"

        let attrStr = NSAttributedString(string: encoded)
        let result = MTMathStringParser.decode(attrStr, encodedArray: entries)

        XCTAssertTrue(result.string.hasPrefix("hello "))
        XCTAssertTrue(result.string.hasSuffix(" world"))
        XCTAssertTrue(result.string.contains(attachmentChar), "Placeholder should be replaced with attachment character")
        XCTAssertFalse(result.string.contains("[citation:"), "Raw placeholder should no longer appear")
    }

    func testDecodeMultiplePlaceholders() {
        let input = "\\( a \\) and \\[ b \\]"
        let (encoded, entries) = MTMathStringParser.encode(input)

        let attrStr = NSAttributedString(string: encoded)
        let result = MTMathStringParser.decode(attrStr, encodedArray: entries)

        let attachmentCount = result.string.filter { $0 == "\u{FFFC}" }.count
        XCTAssertEqual(attachmentCount, 2, "Each placeholder should become one attachment")
        XCTAssertFalse(result.string.contains("[citation:"))
    }

    func testDecodeDeduplicatedPlaceholdersBothReplaced() {
        // encode deduplicates, so two identical math expressions share citation:0
        let input = "\\( x \\) and \\( x \\)"
        let (encoded, entries) = MTMathStringParser.encode(input)
        XCTAssertEqual(entries.count, 1, "Deduplication should produce one entry")

        let attrStr = NSAttributedString(string: encoded)
        let result = MTMathStringParser.decode(attrStr, encodedArray: entries)

        let attachmentCount = result.string.filter { $0 == "\u{FFFC}" }.count
        XCTAssertEqual(attachmentCount, 2, "Both citation:0 references should each become an attachment")
    }

    func testDecodeUsesLocalFontSize() {
        #if os(iOS) || os(visionOS)
        let smallFont = UIFont.systemFont(ofSize: 12)
        let largeFont = UIFont.systemFont(ofSize: 36)
        #else
        let smallFont = NSFont.systemFont(ofSize: 12)
        let largeFont = NSFont.systemFont(ofSize: 36)
        #endif

        let (encoded, entries) = MTMathStringParser.encode("\\( x \\) and \\( y \\)")
        // encoded = "[citation:0] and [citation:1]"

        let attrStr = NSMutableAttributedString(string: encoded)
        // Apply small font to citation:0 range, large font to citation:1 range
        let nsEncoded = encoded as NSString
        if let range0 = encoded.range(of: "[citation:0]") {
            attrStr.addAttribute(.font, value: smallFont, range: NSRange(range0, in: encoded))
        }
        if let range1 = encoded.range(of: "[citation:1]") {
            attrStr.addAttribute(.font, value: largeFont, range: NSRange(range1, in: encoded))
        }
        _ = nsEncoded  // suppress warning

        let result = MTMathStringParser.decode(attrStr, encodedArray: entries)

        // Verify attachments exist; their image sizes reflect different font sizes
        var attachmentBounds: [CGRect] = []
        result.enumerateAttribute(.attachment, in: NSRange(location: 0, length: result.length)) { value, _, _ in
            if let attachment = value as? NSTextAttachment {
                attachmentBounds.append(attachment.bounds)
            }
        }
        XCTAssertEqual(attachmentBounds.count, 2)
        // The larger font should produce a taller image
        XCTAssertGreaterThan(attachmentBounds[1].height, attachmentBounds[0].height,
                             "Larger font size should produce a taller math image")
    }

    func testDecodeFallsBackToFirstFontWhenPlaceholderHasNone() {
        #if os(iOS) || os(visionOS)
        let font = UIFont.systemFont(ofSize: 24)
        #else
        let font = NSFont.systemFont(ofSize: 24)
        #endif

        let (encoded, entries) = MTMathStringParser.encode("\\( x \\)")
        // Apply font only to surrounding text, not the placeholder itself
        let attrStr = NSMutableAttributedString(string: "prefix " + encoded)
        attrStr.addAttribute(.font, value: font, range: NSRange(location: 0, length: 7)) // "prefix "

        let result = MTMathStringParser.decode(attrStr, encodedArray: entries)

        var found = false
        result.enumerateAttribute(.attachment, in: NSRange(location: 0, length: result.length)) { value, _, _ in
            if value is NSTextAttachment { found = true }
        }
        XCTAssertTrue(found, "Attachment should be created even when placeholder has no font attribute")
    }

    func testDecodeWithCustomPlaceholderLabel() {
        let (encoded, entries) = MTMathStringParser.encode("\\( x \\)", placeholderLabel: "ref")
        let attrStr = NSAttributedString(string: encoded)
        let result = MTMathStringParser.decode(attrStr, encodedArray: entries, placeholderLabel: "ref")

        XCTAssertTrue(result.string.contains(attachmentChar))
        XCTAssertFalse(result.string.contains("[ref:"))
    }

    func testDecodeIgnoresOutOfBoundsIndex() {
        // encodedArray has 1 entry but the placeholder references index 5 — should be left as-is
        let attrStr = NSAttributedString(string: "text [citation:5] end")
        let entries: [MTMathStringParser.MathEntry] = [.inline("x")]
        let result = MTMathStringParser.decode(attrStr, encodedArray: entries)

        XCTAssertFalse(result.string.contains(attachmentChar))
        XCTAssertEqual(result.string, "text [citation:5] end")
    }

    func testDecodePlainTextUnchanged() {
        let attrStr = NSAttributedString(string: "no placeholders here")
        let result = MTMathStringParser.decode(attrStr, encodedArray: [])

        XCTAssertEqual(result.string, "no placeholders here")
    }
}
