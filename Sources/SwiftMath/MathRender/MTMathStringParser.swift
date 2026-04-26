//
//  MTMathStringParser.swift
//
//  This software may be modified and distributed under the terms of the
//  MIT license. See the LICENSE file for details.
//

import Foundation

/// Splits a string that mixes plain text and LaTeX math delimiters into typed segments.
///
/// Supported delimiter pairs:
/// - `\[...\]`  — display math
/// - `$$...$$`  — display math  (requires `.dollarDelimiters` option, enabled by default)
/// - `\(...\)`  — inline math
/// - `$...$`    — inline math   (requires `.dollarDelimiters` option, enabled by default)
///
/// Usage:
/// ```swift
/// // Default: all delimiters active
/// let segments = MTMathStringParser.parse("Area: \\( A = \\pi r^2 \\), where \\( r \\) is the radius.")
///
/// // Disable $ recognition when input may contain currency symbols
/// let segments = MTMathStringParser.parse(priceText, options: .backslashOnly)
///
/// for segment in segments {
///     switch segment {
///     case .text(let s):        // render with UILabel / NSTextField
///     case .inlineMath(let s):  // pass s to MTMathListBuilder.build(fromString:)
///     case .displayMath(let s): // pass s to MTMathListBuilder.build(fromString:)
///     }
/// }
/// ```
public struct MTMathStringParser {

    /// Controls which delimiter styles the parser recognises.
    public struct ParseOptions: OptionSet {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        /// Recognise `$...$` (inline) and `$$...$$` (display) as math delimiters.
        /// Disable this when the input may contain literal currency `$` signs.
        public static let dollarDelimiters = ParseOptions(rawValue: 1 << 0)

        /// All delimiter styles active. This is the default.
        public static let `default`: ParseOptions = [.dollarDelimiters]

        /// Only `\(...\)` and `\[...\]` are recognised. Safe for text containing `$`.
        public static let backslashOnly: ParseOptions = []
    }

    public enum Segment: Equatable {
        case text(String)
        case inlineMath(String)
        case displayMath(String)
    }

    /// Parses `input` into an ordered array of plain-text and math segments.
    ///
    /// - Parameters:
    ///   - input: The string to parse.
    ///   - options: Controls which delimiter styles are recognised. Defaults to `.default`
    ///              (all delimiters). Pass `.backslashOnly` to ignore `$` signs, which is
    ///              useful when the input may contain currency symbols.
    ///
    /// Unmatched opening delimiters (no closing counterpart) are treated as plain text.
    public static func parse(_ input: String, options: ParseOptions = .default) -> [Segment] {
        var result: [Segment] = []
        var textStart = input.startIndex
        var i = input.startIndex

        while i < input.endIndex {
            guard let (open, close, isDisplay) = delimiter(in: input, at: i, options: options) else {
                i = input.index(after: i)
                continue
            }

            let contentStart = input.index(i, offsetBy: open.count)
            guard let closeRange = input.range(of: close, range: contentStart..<input.endIndex) else {
                // No matching close delimiter — treat the opener as plain text and keep scanning.
                i = input.index(after: i)
                continue
            }

            // Confirmed match — flush accumulated plain text before the opener.
            let textChunk = String(input[textStart..<i])
            if !textChunk.isEmpty {
                result.append(.text(textChunk))
            }

            let content = String(input[contentStart..<closeRange.lowerBound])
            result.append(isDisplay ? .displayMath(content) : .inlineMath(content))
            i = closeRange.upperBound
            textStart = i
        }

        let trailing = String(input[textStart...])
        if !trailing.isEmpty {
            result.append(.text(trailing))
        }

        return result
    }

    // MARK: - Encode

    /// A unique, deduplicated math expression extracted by `encode(_:options:)`.
    /// Content strings are trimmed of surrounding whitespace.
    public enum MathEntry: Equatable {
        case inline(String)
        case display(String)
    }

    /// Parses `input` and returns:
    /// - `string`: the original text with each math expression replaced by `[<placeholderLabel>:N]`,
    ///   where N is the index into `encodedArray`.
    /// - `encodedArray`: deduplicated math expressions in order of first appearance.
    ///   Identical expressions (same type, same trimmed content) share one entry and
    ///   therefore the same index wherever they appear.
    ///
    /// - Parameters:
    ///   - input: The string to parse.
    ///   - placeholderLabel: The label used inside the placeholder brackets. Defaults to `"citation"`,
    ///     producing `[citation:0]`, `[citation:1]`, etc. Pass a custom value such as `"ref"` or
    ///     `"math"` to produce `[ref:0]`, `[math:0]`, etc.
    ///   - options: Controls which delimiter styles are recognised. Defaults to `.default`.
    ///
    /// Example:
    /// ```
    /// Input:  "lorem \( a + b = c \) ipsum \[ d + e = f \] and \(a + b = c \)"
    /// encode(input)
    ///   string:       "lorem [citation:0] ipsum [citation:1] and [citation:0]"
    ///   encodedArray: [.inline("a + b = c"), .display("d + e = f")]
    ///
    /// encode(input, placeholderLabel: "ref")
    ///   string:       "lorem [ref:0] ipsum [ref:1] and [ref:0]"
    ///   encodedArray: [.inline("a + b = c"), .display("d + e = f")]
    /// ```
    public static func encode(
        _ input: String,
        placeholderLabel: String = "citation",
        options: ParseOptions = .default
    ) -> (string: String, encodedArray: [MathEntry]) {
        let segments = parse(input, options: options)
        var encodedArray: [MathEntry] = []
        var output = ""

        for segment in segments {
            switch segment {
            case .text(let s):
                output += s
            case .inlineMath(let s):
                let entry = MathEntry.inline(s.trimmingCharacters(in: .whitespaces))
                output += "[\(placeholderLabel):\(index(of: entry, in: &encodedArray))]"
            case .displayMath(let s):
                let entry = MathEntry.display(s.trimmingCharacters(in: .whitespaces))
                output += "[\(placeholderLabel):\(index(of: entry, in: &encodedArray))]"
            }
        }

        return (string: output, encodedArray: encodedArray)
    }

    /// Returns the index of `entry` in `array`, appending it first if not already present.
    private static func index(of entry: MathEntry, in array: inout [MathEntry]) -> Int {
        if let existing = array.firstIndex(of: entry) {
            return existing
        }
        array.append(entry)
        return array.count - 1
    }

    // MARK: - Private

    private static let allDelimiters: [(open: String, close: String, isDisplay: Bool)] = [
        ("\\[", "\\]", true),
        ("$$",  "$$",  true),
        ("\\(", "\\)", false),
        ("$",   "$",   false),
    ]

    private static func delimiter(
        in input: String,
        at index: String.Index,
        options: ParseOptions
    ) -> (open: String, close: String, isDisplay: Bool)? {
        for entry in allDelimiters {
            let isDollar = entry.open == "$" || entry.open == "$$"
            if isDollar && !options.contains(.dollarDelimiters) { continue }
            if input[index...].hasPrefix(entry.open) { return entry }
        }
        return nil
    }
}
