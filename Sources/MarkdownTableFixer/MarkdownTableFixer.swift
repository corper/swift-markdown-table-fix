import Foundation

/// 修复 Markdown 表格中分隔行列数不匹配的问题。
///
/// 大语言模型（LLM）生成的 Markdown 表格经常出现分隔行（delimiter row）的 `|` 数量
/// 少于表头（header row）的情况，导致 cmark/GFM 解析器拒绝识别整张表格。
///
/// `MarkdownTableFixer` 通过轻量块级扫描安全修复这类错误：
/// - 正确识别并跳过围栏代码块、缩进代码块，不误伤普通内容
/// - 向前回溯匹配表头，自动补齐缺失的 `|---|` 列
/// - 支持引用块 `>` 和列表项内的表格
///
/// 零外部依赖，不依赖 cmark、swift-markdown 或任何 Markdown 解析库。
public enum MarkdownTableFixer {
    /// 修复 Markdown 文本中的表格分隔行。
    ///
    /// - Parameter markdown: 原始 Markdown 文本
    /// - Returns: 修复后的 Markdown 文本
    public static func fixTableDelimiters(in markdown: String) -> String {
        var lines = markdown.components(separatedBy: "\n")
        var scanState: ScanState = .normal

        for i in lines.indices {
            let line = lines[i]

            // 更新块级扫描状态机
            switch scanState {
            case .normal:
                if let fence = fencedCodeBlockFence(in: line) {
                    scanState = .fencedCodeBlock(fence: fence)
                    continue
                }
                if isIndentedCodeBlockStart(line) {
                    scanState = .indentedCodeBlock
                    continue
                }
            case .fencedCodeBlock(let fence):
                if isClosingFence(line, for: fence) {
                    scanState = .normal
                }
                continue
            case .indentedCodeBlock:
                if shouldExitIndentedCodeBlock(line) {
                    scanState = .normal
                    // 不 continue：退出后的当前行本身属于 normal 区域
                } else {
                    continue
                }
            }

            // 只有 normal 状态下才进行表格修复
            if case .normal = scanState {} else { continue }

            // 提取可能的前缀（引用块或列表项）
            let (prefix, content) = splitPrefix(from: line)
            let contentTrimmed = content.trimmingCharacters(in: .whitespaces)

            // 分隔行候选检测
            guard isDelimiterCandidate(contentTrimmed) else { continue }

            // 表头回溯（要求表头与分隔行具有相同前缀）
            guard let headerIndex = findHeaderIndex(in: lines, before: i, withSamePrefix: prefix) else { continue }
            let headerLine = lines[headerIndex]
            let (_, headerContent) = splitPrefix(from: headerLine)

            let headerPipes = headerContent.filter { $0 == "|" }.count
            let delimiterPipes = contentTrimmed.filter { $0 == "|" }.count

            let headerCols = headerPipes - 1
            let delimiterCols = delimiterPipes - 1

            guard delimiterCols < headerCols else { continue }

            // 修复分隔行，保留前缀和原始内容中的前导空白
            let contentLeading = content.prefix(while: { $0.isWhitespace })
            let fixed = fixDelimiterLine(contentTrimmed, toColumns: headerCols)
            lines[i] = prefix + contentLeading + fixed
        }

        return lines.joined(separator: "\n")
    }
}

// MARK: - 块级扫描状态机

/// 块级扫描状态。
/// 用于区分当前行处于普通文本区域还是代码块内，防止误修复。
private enum ScanState {
    case normal
    case fencedCodeBlock(fence: String)
    case indentedCodeBlock
}

/// 检测一行是否为围栏代码块的起始标记，返回 fence 字符串（如 `` ``` ``）。
/// 要求：行首（去除前导空白后）有至少 3 个连续的 `` ` `` 或 `~`。
private func fencedCodeBlockFence(in line: String) -> String? {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    guard let first = trimmed.first, first == "`" || first == "~" else { return nil }

    var count = 0
    for char in trimmed {
        if char == first {
            count += 1
        } else {
            break
        }
    }
    guard count >= 3 else { return nil }

    return String(repeating: first, count: count)
}

/// 检测一行是否为指定 fence 的闭合标记。
/// 要求：去除前导空白后以相同 fence 字符开头，且连续长度 >= 原始 fence 长度，其后只有空白。
private func isClosingFence(_ line: String, for fence: String) -> Bool {
    guard let first = fence.first else { return false }
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    guard trimmed.first == first else { return false }

    var count = 0
    for char in trimmed {
        if char == first {
            count += 1
        } else {
            break
        }
    }
    guard count >= fence.count else { return false }

    let remainderStart = trimmed.index(trimmed.startIndex, offsetBy: count)
    guard remainderStart < trimmed.endIndex else { return true }
    let remainder = trimmed[remainderStart...]
    return remainder.allSatisfy { $0.isWhitespace }
}

/// 获取一行的前导缩进信息：空格数和是否包含 Tab。
private func leadingIndent(of line: String) -> (spaces: Int, hasTab: Bool) {
    var spaces = 0
    var hasTab = false
    for char in line {
        if char == " " {
            spaces += 1
        } else if char == "\t" {
            hasTab = true
            break
        } else {
            break
        }
    }
    return (spaces, hasTab)
}

/// 判断一行是否以列表标记开头。
private func isListItemMarker(_ line: String) -> Bool {
    if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") {
        return true
    }
    // 检查数字. 空格前缀，如 "1. "
    var digits = 0
    for char in line {
        if char.isNumber {
            digits += 1
        } else if char == "." && digits > 0 {
            let dotIndex = line.index(line.startIndex, offsetBy: digits)
            let afterDot = line.index(after: dotIndex)
            if afterDot < line.endIndex, line[afterDot] == " " {
                return true
            }
            break
        } else {
            break
        }
    }
    return false
}

/// 尝试从行首提取 Markdown 结构前缀（引用块 `>` 或列表项标记），
/// 返回 (前缀, 剩余内容)。无前缀时返回 ("", line)。
private func splitPrefix(from line: String) -> (prefix: String, content: String) {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    
    // 引用块前缀：行首（忽略前导空白）为 `>`，后可选空格
    if trimmed.hasPrefix(">") {
        var index = line.startIndex
        while index < line.endIndex && line[index].isWhitespace {
            index = line.index(after: index)
        }
        let afterGT = line.index(after: index)
        if afterGT < line.endIndex && line[afterGT] == " " {
            let contentStart = line.index(after: afterGT)
            return (String(line[..<contentStart]), String(line[contentStart...]))
        } else {
            return (String(line[..<afterGT]), String(line[afterGT...]))
        }
    }
    
    // 无序列表项前缀
    let unorderedMarkers = ["- ", "* ", "+ "]
    for marker in unorderedMarkers {
        if trimmed.hasPrefix(marker) {
            var index = line.startIndex
            while index < line.endIndex && line[index].isWhitespace {
                index = line.index(after: index)
            }
            let contentStart = line.index(index, offsetBy: marker.count)
            return (String(line[..<contentStart]), String(line[contentStart...]))
        }
    }
    
    // 有序列表项前缀：数字 + "." + 空格
    var digits = 0
    for char in trimmed {
        if char.isNumber {
            digits += 1
        } else {
            break
        }
    }
    if digits > 0 {
        let numberEnd = trimmed.index(trimmed.startIndex, offsetBy: digits)
        let afterNumber = trimmed.index(after: numberEnd)
        if afterNumber < trimmed.endIndex,
           trimmed[numberEnd] == ".",
           trimmed[afterNumber] == " " {
            var index = line.startIndex
            while index < line.endIndex && line[index].isWhitespace {
                index = line.index(after: index)
            }
            let markerLength = digits + 2 // 数字 + "." + " "
            let contentStart = line.index(index, offsetBy: markerLength)
            return (String(line[..<contentStart]), String(line[contentStart...]))
        }
    }
    
    return ("", line)
}

/// 判断一行是否触发进入缩进代码块。
/// 要求：前导空格 >= 4 或包含 Tab；且不以列表标记开头。
private func isIndentedCodeBlockStart(_ line: String) -> Bool {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    if isListItemMarker(trimmed) { return false }

    let (spaces, hasTab) = leadingIndent(of: line)
    return spaces >= 4 || hasTab
}

/// 判断当前行是否导致退出缩进代码块。
/// 空行或前导空格 < 4 且不含 Tab 时退出。
private func shouldExitIndentedCodeBlock(_ line: String) -> Bool {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    if trimmed.isEmpty { return false }

    let (spaces, hasTab) = leadingIndent(of: line)
    return spaces < 4 && !hasTab
}

// MARK: - 表格识别与修复

/// 判断一行是否为分隔行候选。
/// 要求：以 `|` 开头；只含 `-`、`:`、`|`、空白；至少含一个 `-`（或中文破折号）；至少两个 `|`。
private func isDelimiterCandidate(_ line: String) -> Bool {
    guard line.hasPrefix("|") else { return false }
    guard line.contains("-") || line.contains("\u{2014}") else { return false }

    let validChars = CharacterSet(charactersIn: "|-: \t\u{2014}")
    let lineSet = CharacterSet(charactersIn: line)
    guard validChars.isSuperset(of: lineSet) else { return false }

    let pipeCount = line.filter { $0 == "|" }.count
    return pipeCount >= 2
}

/// 判断一行是否为表头行。
/// 要求：以 `|` 开头和结尾；至少两个 `|`；包含非空白且非 `|` 的字符。
private func isHeaderRow(_ line: String) -> Bool {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    guard trimmed.hasPrefix("|"), trimmed.hasSuffix("|") else { return false }

    let pipeCount = trimmed.filter { $0 == "|" }.count
    guard pipeCount >= 2 else { return false }

    let hasContent = trimmed.contains { char in
        char != "|" && !char.isWhitespace
    }
    return hasContent
}

/// 向上回溯找表头行。
/// 从给定索引往前扫描，跳过空行，要求表头行与当前分隔行具有相同前缀，
/// 返回最近一个表头行的索引；遇到非空非表头行则停止。
private func findHeaderIndex(in lines: [String], before index: Int, withSamePrefix prefix: String) -> Int? {
    for i in (0..<index).reversed() {
        let line = lines[i]
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { continue }
        
        let (linePrefix, lineContent) = splitPrefix(from: line)
        // 分隔行若无显式前缀（如列表项缩进延续行），仍允许匹配带前缀的表头
        guard prefix.isEmpty || linePrefix == prefix else { return nil }
        
        // 跳过缩进代码块内容：去除前缀后仍有 >=4 空格前导缩进
        let (spaces, hasTab) = leadingIndent(of: lineContent)
        if spaces >= 4 || hasTab { continue }
        
        if isHeaderRow(lineContent) { return i }
        return nil
    }
    return nil
}

/// 将分隔行补齐到目标列数。
/// 保留原有单元格内容，缺失列使用第一个不含中文破折号的单元格作为模板，否则默认 `---`。
private func fixDelimiterLine(_ line: String, toColumns targetCols: Int) -> String {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    let hasTrailingPipe = trimmed.hasSuffix("|")

    let cells: [String]
    if hasTrailingPipe {
        let inner = trimmed.dropFirst().dropLast()
        cells = inner.split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    } else {
        var parts = trimmed.split(separator: "|", omittingEmptySubsequences: false)
            .map(String.init)
        if parts.first?.isEmpty == true { parts.removeFirst() }
        cells = parts.map { $0.trimmingCharacters(in: .whitespaces) }
    }

    let missing = targetCols - cells.count
    guard missing > 0 else { return line }

    let template = cells.first(where: { !$0.contains("\u{2014}") }) ?? "---"
    let newCells = cells + Array(repeating: template, count: missing)
    return "|" + newCells.joined(separator: "|") + "|"
}
