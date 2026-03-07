import XCTest
@testable import Ridler

final class TemplateManagerTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    private func promptsDir() -> URL {
        tempDir.appendingPathComponent("prompts")
    }

    private func writeTemplate(_ name: String, content: String) {
        let dir = promptsDir()
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try! content.write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    // MARK: - Render Default Templates with Mock Data

    func testRenderIterationContextWithMockData() throws {
        let templateContent = """
        ## Target Iteration

        - **ID:** {{ iteration.id }}
        - **Title:** {{ iteration.title }}
        - **Priority:** {{ iteration.priority }}
        - **Description:** {{ iteration.description }}

        ### Acceptance Criteria
        {% for criterion in iteration.acceptance_criteria %}- {{ criterion }}
        {% endfor %}
        """
        writeTemplate("iteration_context.liquid", content: templateContent)

        let context: [String: Any?] = [
            "iteration": [
                "id": "US-001",
                "title": "Test Story",
                "priority": 1,
                "description": "A test story description",
                "acceptance_criteria": ["AC1: first criterion", "AC2: second criterion"],
            ] as [String: Any],
            "project": [:] as [String: Any],
        ]

        let result = try TemplateManager.render(
            templateName: "iteration_context",
            projectDirectoryURL: tempDir,
            context: context
        )

        XCTAssertTrue(result.contains("US-001"), "Should contain story ID")
        XCTAssertTrue(result.contains("Test Story"), "Should contain story title")
        XCTAssertTrue(result.contains("A test story description"), "Should contain story description")
        XCTAssertTrue(result.contains("AC1: first criterion"), "Should contain first acceptance criterion")
        XCTAssertTrue(result.contains("AC2: second criterion"), "Should contain second acceptance criterion")
    }

    func testRenderEditFileTemplate() throws {
        let templateContent = """
        I want to edit the PRD file at: {{ file_path }}

        Please read the file and help me modify it. Show me the current contents first.
        """
        writeTemplate("edit_file.liquid", content: templateContent)

        let context: [String: Any?] = [
            "file_path": "/Users/test/project/ridl/prd.md",
            "file_name": "prd.md",
            "file_exists": true,
        ]

        let result = try TemplateManager.render(
            templateName: "edit_file",
            projectDirectoryURL: tempDir,
            context: context
        )

        XCTAssertTrue(result.contains("/Users/test/project/ridl/prd.md"))
        XCTAssertTrue(result.contains("Please read the file"))
    }

    func testRenderCreateFileTemplateRidlMd() throws {
        let templateContent = """
        {% if file_name == "ridl.md" %}Create ridl.md from prd.md at {{ file_path }}.{% elsif file_name == "ridl.json" %}Create ridl.json at {{ file_path }}.{% else %}Create {{ file_path }}.{% endif %}
        """
        writeTemplate("create_file.liquid", content: templateContent)

        let context: [String: Any?] = [
            "file_path": "/tmp/ridl.md",
            "file_name": "ridl.md",
            "file_exists": false,
        ]

        let result = try TemplateManager.render(
            templateName: "create_file",
            projectDirectoryURL: tempDir,
            context: context
        )

        XCTAssertTrue(result.contains("Create ridl.md from prd.md"))
        XCTAssertTrue(result.contains("/tmp/ridl.md"))
    }

    func testRenderProgressFormatWithContent() throws {
        let templateContent = """
        ## Stop Condition

        After completing, reply with:
        <ridler-complete/>
        {% if progress_content %}

        ## Previous Progress

        {{ progress_content }}
        {% endif %}
        """
        writeTemplate("progress_format.liquid", content: templateContent)

        let context: [String: Any?] = [
            "iteration": ["id": "US-001"] as [String: Any],
            "progress_content": "## 2026-01-01 - US-000\n- Completed setup",
        ]

        let result = try TemplateManager.render(
            templateName: "progress_format",
            projectDirectoryURL: tempDir,
            context: context
        )

        XCTAssertTrue(result.contains("<ridler-complete/>"))
        XCTAssertTrue(result.contains("Previous Progress"))
        XCTAssertTrue(result.contains("Completed setup"))
    }

    func testRenderProgressFormatWithoutContent() throws {
        let templateContent = """
        <ridler-complete/>
        {% if progress_content %}
        ## Previous Progress
        {{ progress_content }}
        {% endif %}
        """
        writeTemplate("progress_format.liquid", content: templateContent)

        let context: [String: Any?] = [
            "iteration": ["id": "US-001"] as [String: Any],
            "progress_content": nil,
        ]

        let result = try TemplateManager.render(
            templateName: "progress_format",
            projectDirectoryURL: tempDir,
            context: context
        )

        XCTAssertTrue(result.contains("<ridler-complete/>"))
        XCTAssertFalse(result.contains("Previous Progress"))
    }

    // MARK: - Custom Templates Override Defaults

    func testCustomTemplateUsedInsteadOfDefault() throws {
        let customContent = "CUSTOM: Iteration {{ iteration.id }} is being worked on."
        writeTemplate("iteration_context.liquid", content: customContent)

        let context: [String: Any?] = [
            "iteration": ["id": "US-042"] as [String: Any],
        ]

        let result = try TemplateManager.render(
            templateName: "iteration_context",
            projectDirectoryURL: tempDir,
            context: context
        )

        XCTAssertEqual(result, "CUSTOM: Iteration US-042 is being worked on.")
    }

    func testCustomAgentInstructionsOverride() throws {
        let customContent = "You are a specialized agent for {{ iteration.id }}."
        writeTemplate("agent_instructions.liquid", content: customContent)

        let context: [String: Any?] = [
            "iteration": ["id": "US-100"] as [String: Any],
        ]

        let result = try TemplateManager.render(
            templateName: "agent_instructions",
            projectDirectoryURL: tempDir,
            context: context
        )

        XCTAssertEqual(result, "You are a specialized agent for US-100.")
    }

    // MARK: - Malformed Template Validation

    func testValidTemplateReturnsNoError() {
        let content = """
        Hello {{ name }}
        {% if show %}Visible{% endif %}
        {% for item in items %}- {{ item }}
        {% endfor %}
        """
        let error = TemplateManager.validateTemplate(content: content, fileName: "test.liquid")
        XCTAssertNil(error, "Valid template should not produce an error")
    }

    func testUnclosedVariableTagDetected() {
        let content = "Hello {{ name\nWorld"
        let error = TemplateManager.validateTemplate(content: content, fileName: "bad.liquid")
        XCTAssertNotNil(error)
        XCTAssertTrue(error!.message.contains("Line 1"))
        XCTAssertTrue(error!.message.contains("Unclosed variable tag"))
    }

    func testUnclosedBlockTagDetected() {
        let content = "{% if true\nsome text"
        let error = TemplateManager.validateTemplate(content: content, fileName: "bad.liquid")
        XCTAssertNotNil(error)
        XCTAssertTrue(error!.message.contains("Line 1"))
        XCTAssertTrue(error!.message.contains("Unclosed block tag"))
    }

    func testMissingEndifDetected() {
        let content = """
        {% if show %}
        Content here
        """
        let error = TemplateManager.validateTemplate(content: content, fileName: "bad.liquid")
        XCTAssertNotNil(error)
        XCTAssertTrue(error!.message.contains("endif"), "Error should mention missing endif")
    }

    func testMissingEndforDetected() {
        let content = """
        {% for item in items %}
        - {{ item }}
        """
        let error = TemplateManager.validateTemplate(content: content, fileName: "bad.liquid")
        XCTAssertNotNil(error)
        XCTAssertTrue(error!.message.contains("endfor"), "Error should mention missing endfor")
    }

    func testMismatchedBlockTags() {
        let content = """
        {% if show %}
        {% for item in items %}
        {% endif %}
        """
        let error = TemplateManager.validateTemplate(content: content, fileName: "bad.liquid")
        XCTAssertNotNil(error)
        XCTAssertTrue(error!.message.contains("endif") || error!.message.contains("endfor"))
    }

    func testExtraEndifDetected() {
        let content = """
        {% endif %}
        """
        let error = TemplateManager.validateTemplate(content: content, fileName: "bad.liquid")
        XCTAssertNotNil(error)
        XCTAssertTrue(error!.message.contains("no matching opening tag"))
    }

    func testValidateAllTemplatesWithBrokenFile() {
        writeTemplate("good.liquid", content: "Hello {{ name }}")
        writeTemplate("broken.liquid", content: "{% if true %}\nunclosed")

        let errors = TemplateManager.validateAllTemplates(in: tempDir)

        XCTAssertNil(errors["good.liquid"], "Good template should have no error")
        XCTAssertNotNil(errors["broken.liquid"], "Broken template should have an error")
    }

    func testValidateAllTemplatesAllGood() {
        writeTemplate("a.liquid", content: "{{ name }}")
        writeTemplate("b.liquid", content: "{% if x %}y{% endif %}")

        let errors = TemplateManager.validateAllTemplates(in: tempDir)

        XCTAssertTrue(errors.isEmpty, "All valid templates should produce no errors")
    }

    // MARK: - Template Error Blocks Loop Start

    func testTemplateErrorMessageIncludesFileName() {
        let error = TemplateManager.TemplateError(fileName: "broken.liquid", message: "Line 5: Unclosed block")
        XCTAssertTrue(error.errorDescription!.contains("broken.liquid"))
        XCTAssertTrue(error.errorDescription!.contains("Line 5"))
    }

    // MARK: - List Template Files

    func testListTemplateFilesReturnsLiquidFiles() {
        writeTemplate("agent.liquid", content: "test")
        writeTemplate("iteration.liquid", content: "test")
        // Write a non-liquid file
        let dir = promptsDir()
        try! "not a template".write(to: dir.appendingPathComponent("readme.txt"), atomically: true, encoding: .utf8)

        let files = TemplateManager.listTemplateFiles(in: tempDir)

        XCTAssertEqual(files.count, 2)
        XCTAssertTrue(files.contains("agent.liquid"))
        XCTAssertTrue(files.contains("iteration.liquid"))
        XCTAssertFalse(files.contains("readme.txt"))
    }

    func testListTemplateFilesEmptyWhenNoDirectory() {
        let files = TemplateManager.listTemplateFiles(in: tempDir)
        XCTAssertTrue(files.isEmpty)
    }
}
