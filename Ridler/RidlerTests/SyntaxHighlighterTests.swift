import XCTest
@testable import Ridler

final class SyntaxHighlighterTests: XCTestCase {

    // MARK: - Segment Parsing

    func testParseSegmentsPlainText() {
        let segments = SyntaxHighlighter.parseSegments("Hello, world!")
        XCTAssertEqual(segments, [.text("Hello, world!")])
    }

    func testParseSegmentsSingleCodeBlock() {
        let input = "Before\n```swift\nlet x = 1\n```\nAfter"
        let segments = SyntaxHighlighter.parseSegments(input)
        XCTAssertEqual(segments.count, 3)
        XCTAssertEqual(segments[0], .text("Before"))
        XCTAssertEqual(segments[1], .codeBlock(language: "swift", code: "let x = 1"))
        XCTAssertEqual(segments[2], .text("\nAfter"))
    }

    func testParseSegmentsNoLanguage() {
        let input = "```\nsome code\n```"
        let segments = SyntaxHighlighter.parseSegments(input)
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0], .codeBlock(language: nil, code: "some code"))
    }

    func testParseSegmentsMultipleCodeBlocks() {
        let input = "Text1\n```python\ndef foo():\n    pass\n```\nText2\n```js\nconst x = 1;\n```\nText3"
        let segments = SyntaxHighlighter.parseSegments(input)
        XCTAssertEqual(segments.count, 5)
        XCTAssertEqual(segments[0], .text("Text1"))
        XCTAssertEqual(segments[1], .codeBlock(language: "python", code: "def foo():\n    pass"))
        XCTAssertEqual(segments[2], .text("\nText2"))
        XCTAssertEqual(segments[3], .codeBlock(language: "js", code: "const x = 1;"))
        XCTAssertEqual(segments[4], .text("\nText3"))
    }

    func testParseSegmentsUnclosedCodeBlock() {
        let input = "Before\n```swift\nlet x = 1"
        let segments = SyntaxHighlighter.parseSegments(input)
        // Unclosed code block treated as text — "Before" is first segment, then the unclosed block text
        XCTAssertGreaterThanOrEqual(segments.count, 1)
        // All segments should be text (no code blocks)
        for segment in segments {
            if case .codeBlock = segment {
                XCTFail("Unclosed code block should not produce a .codeBlock segment")
            }
        }
        // The content should contain the code
        let allText = segments.compactMap { segment -> String? in
            if case .text(let text) = segment { return text }
            return nil
        }.joined()
        XCTAssertTrue(allText.contains("let x = 1"))
        XCTAssertTrue(allText.contains("Before"))
    }

    func testParseSegmentsEmptyCodeBlock() {
        let input = "```swift\n```"
        let segments = SyntaxHighlighter.parseSegments(input)
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0], .codeBlock(language: "swift", code: ""))
    }

    func testParseSegmentsLanguageCaseNormalized() {
        let input = "```TypeScript\nconst x = 1\n```"
        let segments = SyntaxHighlighter.parseSegments(input)
        XCTAssertEqual(segments[0], .codeBlock(language: "typescript", code: "const x = 1"))
    }

    func testParseSegmentsOnlyText() {
        let input = "Just plain text\nwith multiple lines"
        let segments = SyntaxHighlighter.parseSegments(input)
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0], .text("Just plain text\nwith multiple lines"))
    }

    func testParseSegmentsMultilineCode() {
        let input = "```go\npackage main\n\nimport \"fmt\"\n\nfunc main() {\n    fmt.Println(\"hello\")\n}\n```"
        let segments = SyntaxHighlighter.parseSegments(input)
        XCTAssertEqual(segments.count, 1)
        if case .codeBlock(let lang, let code) = segments[0] {
            XCTAssertEqual(lang, "go")
            XCTAssertTrue(code.contains("package main"))
            XCTAssertTrue(code.contains("func main()"))
        } else {
            XCTFail("Expected code block")
        }
    }

    // MARK: - Highlighting

    func testHighlightSwiftKeywords() {
        let code = "let x = 1"
        let result = SyntaxHighlighter.highlight(code: code, language: "swift")
        XCTAssertEqual(result.string, code)
        // Verify the attributed string has attributes (colors applied)
        var range = NSRange()
        let attrs = result.attributes(at: 0, effectiveRange: &range)
        XCTAssertNotNil(attrs[.foregroundColor])
    }

    func testHighlightPythonKeywords() {
        let code = "def hello():\n    return True"
        let result = SyntaxHighlighter.highlight(code: code, language: "python")
        XCTAssertEqual(result.string, code)
    }

    func testHighlightTypeScript() {
        let code = "const x: string = \"hello\";"
        let result = SyntaxHighlighter.highlight(code: code, language: "typescript")
        XCTAssertEqual(result.string, code)
    }

    func testHighlightUnknownLanguage() {
        let code = "let x = 1"
        let result = SyntaxHighlighter.highlight(code: code, language: "brainfuck")
        XCTAssertEqual(result.string, code)
        // Should still highlight with generic keywords
    }

    func testHighlightNilLanguage() {
        let code = "function test() { return 42; }"
        let result = SyntaxHighlighter.highlight(code: code, language: nil)
        XCTAssertEqual(result.string, code)
    }

    func testHighlightEmptyCode() {
        let result = SyntaxHighlighter.highlight(code: "", language: "swift")
        XCTAssertEqual(result.string, "")
    }

    func testHighlightPreservesContent() {
        let code = "import Foundation\n\nstruct Foo {\n    let bar: Int = 42\n    var baz: String = \"hello\"\n}"
        let result = SyntaxHighlighter.highlight(code: code, language: "swift")
        XCTAssertEqual(result.string, code)
    }

    func testHighlightRust() {
        let code = "fn main() {\n    let x: i32 = 42;\n    println!(\"{}\", x);\n}"
        let result = SyntaxHighlighter.highlight(code: code, language: "rust")
        XCTAssertEqual(result.string, code)
    }

    func testHighlightGo() {
        let code = "func main() {\n    fmt.Println(\"Hello\")\n}"
        let result = SyntaxHighlighter.highlight(code: code, language: "go")
        XCTAssertEqual(result.string, code)
    }

    func testHighlightBash() {
        let code = "#!/bin/bash\necho \"hello\"\nif [ -f file ]; then\n    echo \"exists\"\nfi"
        let result = SyntaxHighlighter.highlight(code: code, language: "bash")
        XCTAssertEqual(result.string, code)
    }

    // MARK: - Supported Languages

    func testSupportedLanguages() {
        let languages = ["swift", "typescript", "ts", "tsx", "javascript", "js", "jsx",
                         "python", "py", "go", "golang", "rust", "rs",
                         "bash", "sh", "shell", "zsh", "json", "html", "xml", "css", "scss"]
        for lang in languages {
            let result = SyntaxHighlighter.highlight(code: "let x = 1", language: lang)
            XCTAssertEqual(result.string, "let x = 1", "Failed for language: \(lang)")
        }
    }
}
