import Foundation
import Markdown

/// Converts Markdown text to HTML using swift-markdown's Document parser.
/// Generates clean HTML with data-line attributes for scroll synchronization.
struct MarkdownHTMLGenerator {
    /// Parse Markdown text and produce an HTML string.
    func generateHTML(from markdown: String) -> String {
        let document = Document(parsing: markdown, options: [.parseBlockDirectives, .parseSymbolLinks])
        var walker = HTMLRenderer()
        walker.visit(document)
        return walker.html
    }

    /// Wraps generated HTML body in the full template with CSS and JS references.
    func generateFullPage(from markdown: String, theme: PreviewTheme) -> String {
        let body = generateHTML(from: markdown)
        let themeClass = theme == .dark ? "dark" : theme == .light ? "light" : "auto"

        return """
        <!DOCTYPE html>
        <html class="\(themeClass)">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <link rel="stylesheet" href="preview-light.css" media="(prefers-color-scheme: light)">
            <link rel="stylesheet" href="preview-dark.css" media="(prefers-color-scheme: dark)">
            <link rel="stylesheet" href="preview-light.css" class="theme-light">
            <link rel="stylesheet" href="preview-dark.css" class="theme-dark">
            <link rel="stylesheet" href="prism/prism.css">
            <style>
                html.light .theme-dark { display: none; }
                html.dark .theme-light { display: none; }
                html.auto .theme-light, html.auto .theme-dark { display: initial; }
            </style>
        </head>
        <body>
            <article class="markdown-body">
                \(body)
            </article>
            <script src="prism/prism.js"></script>
            <script>
                // Re-highlight when content updates
                if (typeof Prism !== 'undefined') {
                    Prism.highlightAll();
                }
            </script>
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
