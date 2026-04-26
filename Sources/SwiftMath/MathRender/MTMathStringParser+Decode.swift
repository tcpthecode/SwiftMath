//
//  MTMathStringParser+Decode.swift
//
//  This software may be modified and distributed under the terms of the
//  MIT license. See the LICENSE file for details.
//

import Foundation

#if os(iOS) || os(visionOS)
import UIKit
#else
import AppKit
#endif

extension MTMathStringParser {

    /// Replaces each `[<placeholderLabel>:N]` placeholder in `attributedString` with a
    /// rendered math image derived from `encodedArray[N]`.
    ///
    /// The font size for rendering is resolved in this order:
    /// 1. The font attribute on the attributed string at the placeholder's position.
    /// 2. The first font attribute found anywhere in the string.
    /// 3. A fallback of 14 pt.
    ///
    /// The text color is taken from the `.foregroundColor` attribute at the placeholder's
    /// position, defaulting to black if none is set.
    ///
    /// - Parameters:
    ///   - attributedString: The string produced by `encode(_:placeholderLabel:options:)`.
    ///   - encodedArray: The math entries returned alongside the encoded string.
    ///   - placeholderLabel: Must match the label used during encoding. Defaults to `"citation"`.
    /// - Returns: A new attributed string with placeholders replaced by math image attachments
    ///   sized and baseline-aligned to match the surrounding text.
    public static func decode(
        _ attributedString: NSAttributedString,
        encodedArray: [MathEntry],
        placeholderLabel: String = "citation"
    ) -> NSAttributedString {
        let mutable = NSMutableAttributedString(attributedString: attributedString)

        let fallbackFontSize = firstFontSize(in: attributedString) ?? 14

        let escaped = NSRegularExpression.escapedPattern(for: placeholderLabel)
        guard let regex = try? NSRegularExpression(pattern: "\\[\(escaped):(\\d+)\\]") else {
            return attributedString
        }

        let fullRange = NSRange(location: 0, length: (mutable.string as NSString).length)
        let matches = regex.matches(in: mutable.string, range: fullRange)

        for match in matches.reversed() {
            let matchRange = match.range
            guard let indexStrRange = Range(match.range(at: 1), in: mutable.string),
                  let entryIndex = Int(mutable.string[indexStrRange]),
                  entryIndex < encodedArray.count else { continue }

            let entry = encodedArray[entryIndex]
            let fontSize = fontSizeAt(matchRange.location, in: mutable) ?? fallbackFontSize
            let textColor = colorAt(matchRange.location, in: mutable) ?? MTColor.black

            let latex: String
            let labelMode: MTMathUILabelMode
            switch entry {
            case .inline(let s):  latex = s; labelMode = .text
            case .display(let s): latex = s; labelMode = .display
            }

            var mathImage = MathImage(
                latex: latex,
                fontSize: fontSize,
                textColor: textColor,
                labelMode: labelMode
            )
            let (error, renderedImage, layoutInfo) = mathImage.asImage()

            guard error == nil, let img = renderedImage, let info = layoutInfo else { continue }

            let attachment = NSTextAttachment()
            attachment.image = img
            attachment.bounds = CGRect(
                x: 0,
                y: -info.descent,
                width: img.size.width,
                height: img.size.height
            )

            mutable.replaceCharacters(in: matchRange, with: NSAttributedString(attachment: attachment))
        }

        return mutable
    }

    // MARK: - Private helpers

    private static func firstFontSize(in attrStr: NSAttributedString) -> CGFloat? {
        var result: CGFloat?
        attrStr.enumerateAttribute(
            .font,
            in: NSRange(location: 0, length: attrStr.length),
            options: []
        ) { value, _, stop in
            if let size = pointSize(of: value) {
                result = size
                stop.pointee = true
            }
        }
        return result
    }

    private static func fontSizeAt(_ location: Int, in attrStr: NSAttributedString) -> CGFloat? {
        guard location < attrStr.length else { return nil }
        return pointSize(of: attrStr.attribute(.font, at: location, effectiveRange: nil))
    }

    private static func colorAt(_ location: Int, in attrStr: NSAttributedString) -> MTColor? {
        guard location < attrStr.length else { return nil }
        return attrStr.attribute(.foregroundColor, at: location, effectiveRange: nil) as? MTColor
    }

    private static func pointSize(of fontAttribute: Any?) -> CGFloat? {
        #if os(iOS) || os(visionOS)
        return (fontAttribute as? UIFont)?.pointSize
        #else
        return (fontAttribute as? NSFont)?.pointSize
        #endif
    }
}
