import XCTest
@testable import MarkdownTableFixer

final class MarkdownTableFixerTests: XCTestCase {

    // MARK: - 基础修复

    func testMissingTrailingColumns() {
        let input = """
        | 任务 | 时间 | ID | 功能 |
        |——|——| 
        """
        let expected = """
        | 任务 | 时间 | ID | 功能 |
        |——|——|---|---|
        """
        XCTAssertEqual(MarkdownTableFixer.fixTableDelimiters(in: input), expected)
    }

    func testEmptyLinesBetweenHeaderAndDelimiter() {
        let input = """
        | A | B | C |


        |---|---|
        """
        let expected = """
        | A | B | C |


        |---|---|---|
        """
        XCTAssertEqual(MarkdownTableFixer.fixTableDelimiters(in: input), expected)
    }

    func testMissingMultipleColumns() {
        let input = """
        | A | B | C | D |
        |---|---|
        """
        let expected = """
        | A | B | C | D |
        |---|---|---|---|
        """
        XCTAssertEqual(MarkdownTableFixer.fixTableDelimiters(in: input), expected)
    }

    func testDelimiterWithMoreColumnsThanHeaderNotModified() {
        let input = """
        | A | B |
        |---|---|---|
        """
        XCTAssertEqual(MarkdownTableFixer.fixTableDelimiters(in: input), input)
    }

    func testCorrectDelimiterRowNotModified() {
        let input = """
        | A | B | C |
        |---|---|---|
        """
        XCTAssertEqual(MarkdownTableFixer.fixTableDelimiters(in: input), input)
    }

    func testOnlyOneDelimiterCell() {
        let input = """
        | 项目 | 旧路径 | 新路径 |
        |--------|
        """
        let expected = """
        | 项目 | 旧路径 | 新路径 |
        |--------|--------|--------|
        """
        XCTAssertEqual(MarkdownTableFixer.fixTableDelimiters(in: input), expected)
    }

    // MARK: - 不应修改

    func testCodeBlockSkipped() {
        let input = """
        ```swift
        let pattern = "|——|——|"
        ```
        """
        XCTAssertEqual(MarkdownTableFixer.fixTableDelimiters(in: input), input)
    }

    func testPlainParagraphSkipped() {
        let input = """
        这段文字里有 | A | B |，但不是表格。
        """
        XCTAssertEqual(MarkdownTableFixer.fixTableDelimiters(in: input), input)
    }

    func testDelimiterWithoutHeaderNotModified() {
        let input = """
        这是一段普通文字
        |---|---|
        """
        XCTAssertEqual(MarkdownTableFixer.fixTableDelimiters(in: input), input)
    }

    func testHorizontalRuleSkipped() {
        let input = """
        ---
        """
        XCTAssertEqual(MarkdownTableFixer.fixTableDelimiters(in: input), input)
    }

    /// 围栏代码块内有类似表格的结构，当前缺少状态机，此测试预期失败。
    func testFencedCodeBlockWithTableLikeContentSkipped() {
        let input = """
        ```
        | A | B |
        |---|
        ```
        """
        XCTAssertEqual(MarkdownTableFixer.fixTableDelimiters(in: input), input)
    }

    /// 用 ~~~ 的围栏代码块内有类似表格的结构，当前缺少状态机，此测试预期失败。
    func testTildeFencedCodeBlockSkipped() {
        let input = """
        ~~~
        | X | Y | Z |
        |---|---|
        ~~~
        """
        XCTAssertEqual(MarkdownTableFixer.fixTableDelimiters(in: input), input)
    }

    /// 缩进代码块（4 空格缩进）内有类似表格的结构，当前缺少状态机，此测试预期失败。
    func testIndentedCodeBlockSkipped() {
        let input = """
            | A | B |
            |---|
        """
        XCTAssertEqual(MarkdownTableFixer.fixTableDelimiters(in: input), input)
    }

    /// 缩进代码块中包含空行时不应退出代码块；
    /// 空行后的非缩进行若被误判为分隔行，会导致误修复。
    func testIndentedCodeBlockWithEmptyLineNotExited() {
        let input = """
            | A | B | C |

        |---|
        """
        XCTAssertEqual(MarkdownTableFixer.fixTableDelimiters(in: input), input)
    }

    // MARK: - 引用块内

    func testBlockquoteTableFixed() {
        let input = """
        > | A | B | C |
        > |---|---|
        """
        let expected = """
        > | A | B | C |
        > |---|---|---|
        """
        XCTAssertEqual(MarkdownTableFixer.fixTableDelimiters(in: input), expected)
    }

    // MARK: - 列表项内

    func testListItemTableFixed() {
        let input = """
        - | A | B | C |
          |---|---|
        """
        let expected = """
        - | A | B | C |
          |---|---|---|
        """
        XCTAssertEqual(MarkdownTableFixer.fixTableDelimiters(in: input), expected)
    }

    // MARK: - 多个表格

    func testMultipleTablesOnlyFixBrokenOnes() {
        let input = """
        | X | Y |
        |---|---|

        | 任务 | 时间 | ID | 功能 |
        |——|——| 

        | A | B |
        |---|
        """
        let expected = """
        | X | Y |
        |---|---|

        | 任务 | 时间 | ID | 功能 |
        |——|——|---|---|

        | A | B |
        |---|---|
        """
        XCTAssertEqual(MarkdownTableFixer.fixTableDelimiters(in: input), expected)
    }
}
