import Foundation
import Markdown

/// Converts Markdown text to HTML using swift-markdown's Document parser.
/// Generates clean HTML with data-line attributes for scroll synchronization.
struct MarkdownHTMLGenerator {
    /// Parse Markdown text and produce an HTML string.
    /// Strips YAML front matter (if present) and renders it as a styled table.
    func generateHTML(from markdown: String) -> String {
        let (frontMatter, body) = extractFrontMatter(from: markdown)
        let document = Document(parsing: body, options: [.parseBlockDirectives, .parseSymbolLinks])
        var walker = HTMLRenderer()
        walker.visit(document)

        var html = ""
        if let fm = frontMatter {
            html += renderFrontMatter(fm)
        }
        html += walker.html
        return html
    }

    /// Extract YAML front matter delimited by `---` at the start of the file.
    private func extractFrontMatter(from text: String) -> (frontMatter: String?, body: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("---") else { return (nil, text) }

        // Find the closing ---
        let lines = text.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return (nil, text) }

        var closingIndex: Int?
        for i in 1..<lines.count {
            if lines[i].trimmingCharacters(in: .whitespaces) == "---" {
                closingIndex = i
                break
            }
        }

        guard let endIndex = closingIndex, endIndex > 1 else { return (nil, text) }

        let fmLines = lines[1..<endIndex]
        let bodyLines = lines[(endIndex + 1)...]
        return (fmLines.joined(separator: "\n"), bodyLines.joined(separator: "\n"))
    }

    /// Render front matter as a styled HTML table.
    private func renderFrontMatter(_ yaml: String) -> String {
        var rows = ""
        let lines = yaml.components(separatedBy: "\n")
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            if let colonIdx = trimmed.firstIndex(of: ":") {
                let key = String(trimmed[trimmed.startIndex..<colonIdx]).trimmingCharacters(in: .whitespaces)
                let value = String(trimmed[trimmed.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)
                let displayValue = formatFrontMatterValue(value)
                rows += "<tr><td class=\"fm-key\">\(escapeHTML(key))</td><td class=\"fm-value\">\(displayValue)</td></tr>\n"
            } else if trimmed.hasPrefix("- ") {
                // List item continuation
                let value = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                rows += "<tr><td class=\"fm-key\"></td><td class=\"fm-value fm-list-item\">\(escapeHTML(value))</td></tr>\n"
            }
        }

        return """
        <details class="front-matter" open>
            <summary>Front Matter</summary>
            <table class="fm-table">\(rows)</table>
        </details>
        """
    }

    private func formatFrontMatterValue(_ value: String) -> String {
        // Handle quoted strings
        var v = value
        if (v.hasPrefix("\"") && v.hasSuffix("\"")) || (v.hasPrefix("'") && v.hasSuffix("'")) {
            v = String(v.dropFirst().dropLast())
        }
        // Boolean values
        if v == "true" || v == "false" {
            return "<span class=\"fm-bool\">\(v)</span>"
        }
        // Empty (likely a list follows)
        if v.isEmpty {
            return ""
        }
        return escapeHTML(v)
    }

    private func escapeHTML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// Wraps generated HTML body in the full template with CSS and JS references.
    func generateFullPage(from markdown: String, theme: PreviewTheme) -> String {
        let body = generateHTML(from: markdown)

        let cssLinks: String
        switch theme {
        case .light:
            cssLinks = "<link rel=\"stylesheet\" href=\"preview-light.css\">"
        case .dark:
            cssLinks = "<link rel=\"stylesheet\" href=\"preview-dark.css\">"
        case .system:
            cssLinks = """
            <link rel="stylesheet" href="preview-light.css" media="(prefers-color-scheme: light)">
            <link rel="stylesheet" href="preview-dark.css" media="(prefers-color-scheme: dark)">
            """
        }

        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            \(cssLinks)
        </head>
        <body>
            <article class="markdown-body">
                \(body)
            </article>
        </body>
        </html>
        """
    }
}

enum PreviewTheme: String, CaseIterable {
    case system
    case light
    case dark
}

// MARK: - HTML Renderer using swift-markdown MarkupWalker

private struct HTMLRenderer: MarkupWalker {
    var html = ""
    private var listNestingLevel = 0

    // MARK: - Block elements

    mutating func visitDocument(_ document: Document) -> () {
        descendInto(document)
    }

    mutating func visitHeading(_ heading: Heading) -> () {
        let tag = "h\(heading.level)"
        let line = heading.range?.lowerBound.line ?? 0
        html += "<\(tag) data-line=\"\(line)\">"
        descendInto(heading)
        html += "</\(tag)>\n"
    }

    mutating func visitParagraph(_ paragraph: Paragraph) -> () {
        let line = paragraph.range?.lowerBound.line ?? 0
        html += "<p data-line=\"\(line)\">"
        descendInto(paragraph)
        html += "</p>\n"
    }

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) -> () {
        let line = blockQuote.range?.lowerBound.line ?? 0
        html += "<blockquote data-line=\"\(line)\">"
        descendInto(blockQuote)
        html += "</blockquote>\n"
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) -> () {
        let line = codeBlock.range?.lowerBound.line ?? 0
        let lang = codeBlock.language ?? ""
        let langClass = lang.isEmpty ? "" : " class=\"language-\(escapeHTML(lang))\""
        html += "<pre data-line=\"\(line)\"><code\(langClass)>"
        html += escapeHTML(codeBlock.code)
        html += "</code></pre>\n"
    }

    mutating func visitOrderedList(_ orderedList: OrderedList) -> () {
        let line = orderedList.range?.lowerBound.line ?? 0
        let start = orderedList.startIndex
        html += start != 1 ? "<ol start=\"\(start)\" data-line=\"\(line)\">" : "<ol data-line=\"\(line)\">"
        listNestingLevel += 1
        descendInto(orderedList)
        listNestingLevel -= 1
        html += "</ol>\n"
    }

    mutating func visitUnorderedList(_ unorderedList: UnorderedList) -> () {
        let line = unorderedList.range?.lowerBound.line ?? 0
        html += "<ul data-line=\"\(line)\">"
        listNestingLevel += 1
        descendInto(unorderedList)
        listNestingLevel -= 1
        html += "</ul>\n"
    }

    mutating func visitListItem(_ listItem: ListItem) -> () {
        if let checkbox = listItem.checkbox {
            let checked = checkbox == .checked ? " checked" : ""
            html += "<li class=\"task-list-item\"><input type=\"checkbox\" disabled\(checked)> "
        } else {
            html += "<li>"
        }
        descendInto(listItem)
        html += "</li>\n"
    }

    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) -> () {
        html += "<hr>\n"
    }

    mutating func visitHTMLBlock(_ htmlBlock: HTMLBlock) -> () {
        html += htmlBlock.rawHTML
    }

    mutating func visitTable(_ table: Table) -> () {
        let line = table.range?.lowerBound.line ?? 0
        html += "<table data-line=\"\(line)\">\n"
        descendInto(table)
        html += "</table>\n"
    }

    mutating func visitTableHead(_ tableHead: Table.Head) -> () {
        html += "<thead><tr>"
        descendInto(tableHead)
        html += "</tr></thead>\n"
    }

    mutating func visitTableBody(_ tableBody: Table.Body) -> () {
        html += "<tbody>"
        descendInto(tableBody)
        html += "</tbody>\n"
    }

    mutating func visitTableRow(_ tableRow: Table.Row) -> () {
        html += "<tr>"
        descendInto(tableRow)
        html += "</tr>\n"
    }

    mutating func visitTableCell(_ tableCell: Table.Cell) -> () {
        let tag = tableCell.parent is Table.Head ? "th" : "td"
        html += "<\(tag)>"
        descendInto(tableCell)
        html += "</\(tag)>"
    }

    // MARK: - Inline elements

    mutating func visitText(_ text: Markdown.Text) -> () {
        html += escapeHTML(text.string)
    }

    mutating func visitEmphasis(_ emphasis: Emphasis) -> () {
        html += "<em>"
        descendInto(emphasis)
        html += "</em>"
    }

    mutating func visitStrong(_ strong: Strong) -> () {
        html += "<strong>"
        descendInto(strong)
        html += "</strong>"
    }

    mutating func visitInlineCode(_ inlineCode: InlineCode) -> () {
        html += "<code>"
        html += escapeHTML(inlineCode.code)
        html += "</code>"
    }

    mutating func visitLink(_ link: Markdown.Link) -> () {
        let dest = link.destination ?? ""
        html += "<a href=\"\(escapeHTML(dest))\">"
        descendInto(link)
        html += "</a>"
    }

    mutating func visitImage(_ image: Markdown.Image) -> () {
        let src = image.source ?? ""
        let alt = image.plainText
        html += "<img src=\"\(escapeHTML(src))\" alt=\"\(escapeHTML(alt))\">"
    }

    mutating func visitLineBreak(_ lineBreak: LineBreak) -> () {
        html += "<br>\n"
    }

    mutating func visitSoftBreak(_ softBreak: SoftBreak) -> () {
        html += "\n"
    }

    mutating func visitStrikethrough(_ strikethrough: Strikethrough) -> () {
        html += "<del>"
        descendInto(strikethrough)
        html += "</del>"
    }

    mutating func visitInlineHTML(_ inlineHTML: InlineHTML) -> () {
        html += inlineHTML.rawHTML
    }

    // MARK: - Helpers

    private func escapeHTML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
