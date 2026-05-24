# swift-markdown-table-fix

修复 LLM 生成的 Markdown 表格中分隔行（delimiter row）列数不匹配的问题。

## 问题

大语言模型（LLM）返回的 Markdown 表格经常出现两类格式问题：

1. **分隔行列数不匹配**：分隔行中的 `|` 数量少于表头列数。
2. **使用中文破折号**：分隔行中使用全角破折号 `——` 而非半角连字符 `---`，导致分隔行无法被识别。

例如：

```markdown
| 任务 | 时间 | ID | 功能 |
|——|——| 
```

由于 [cmark](https://github.com/commonmark/cmark) 的 GFM 表格扩展要求分隔行列数**严格等于**表头列数，且分隔单元格必须由 `-` 和 `:` 组成，上述格式错误会导致**整张表格**无法被识别，退化为普通段落文本。

## 解决方案

`MarkdownTableFixer` 是一个轻量的 Swift 工具，在渲染前自动修复分隔行：

- ✅ **块级感知**：正确识别围栏代码块、缩进代码块，不误伤普通内容
- ✅ **零依赖**：纯 Swift 实现，不依赖 cmark、swift-markdown 或任何 Markdown 解析库
- ✅ **引用块/列表支持**：支持 `>` 引用块和列表项内的表格
- ✅ **跨平台**：支持 macOS、iOS、tvOS、watchOS、Linux

## 使用

```swift
import MarkdownTableFixer

let rawMarkdown = llmResponse.text
let fixedMarkdown = MarkdownTableFixer.fixTableDelimiters(in: rawMarkdown)

// 将 fixedMarkdown 送入渲染器
```

## 示例

**输入：**

```markdown
| 任务 | 时间 | ID | 功能 |
|——|——| 
```

**输出：**

```markdown
| 任务 | 时间 | ID | 功能 |
|——|——|---|---|
```

---

**输入（中文破折号）：**

```markdown
| 姓名 | 年龄 | 城市 |
|——|——|——|
```

**输出：**

```markdown
| 姓名 | 年龄 | 城市 |
|---|---|---|
```

## 设计文档

详细实现规范见 [docs/Spec.md](docs/Spec.md)。

## 局限性

- 只处理以 `|` 开头/结尾的表格（GFM 宽松语法中省略首尾 `|` 的表格不处理）
- 分隔行补齐时使用 `|---|`（不保留原始对齐标记 `:---:` 的精确格式）
- 不支持多行单元格（cmark 本身也不支持）

## License

MIT
