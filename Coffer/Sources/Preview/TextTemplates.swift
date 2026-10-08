import Foundation
import UniformTypeIdentifiers

enum TextTemplates {
    static func escaped(_ text: String) -> String { text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;") }
    static func page(text: String, ext: String, rendered: Bool, markdown: Bool, dark: Bool, wrap: Bool, size: Int, highlight: Bool) throws -> String {
        let colors = dark ? ["#1A1916", "#24221E", "#2E2B26", "#F3EFE4", "#ABA597", "#7C776C", "#F7BDC9", "#3A3731", "#8FC08A", "#E0B570"] : ["#F8F4E6", "#FFFCF3", "#EFE9D8", "#2A2723", "#6E685D", "#9C9587", "#A84860", "#E3DCC8", "#4E7D4A", "#9A6B1F"]
        let variables = zip(["canvas", "surface", "sunken", "ink", "ink2", "ink3", "pinkInk", "hairline", "success", "number"], colors).map { "--\($0):\($1)" }.joined(separator: ";")
        let json = String(decoding: try JSONEncoder().encode(text), as: UTF8.self).replacingOccurrences(of: "<", with: "\\u003c")
        let language = language(ext)
        let css = """
        :root {\(variables);--pink:rgb(96.7% 74.3% 78.8%)}
        body{margin:0;background:var(--canvas);color:var(--ink);font:17px/1.65 -apple-system,sans-serif}
        .katex-display{overflow-x:auto;overflow-y:hidden;padding:8px 0}article{max-width:720px;margin:auto;padding:16px 20px 40px}h1,h2,h3{font-family:ui-serif,'New York',Georgia,serif;font-weight:600}h1{font-size:30px}h2{font-size:24px;border-bottom:1px solid var(--hairline);padding-bottom:6px}h3{font-size:20px}
        a{color:var(--pinkInk);text-decoration:none}code{font:13px ui-monospace,Menlo,monospace;background:var(--sunken);border-radius:6px;padding:2px 5px}pre{background:var(--sunken);border-radius:12px;padding:14px 16px;overflow:auto}pre code{padding:0;background:none}
        blockquote{border-left:3px solid var(--pink);padding-left:14px;color:var(--ink2)}table{border-collapse:collapse;width:100%}th,td{border:1px solid var(--hairline);padding:8px 12px;font-variant-numeric:tabular-nums}th{background:var(--sunken);position:sticky;top:0}tr:nth-child(odd){background:var(--surface)}img{max-width:100%;border-radius:10px}hr{border:0;border-top:1px solid var(--hairline)}input{accent-color:var(--pink)}
        .source{display:grid;grid-template-columns:auto 1fr;overflow:auto}.source pre{margin:0;padding:16px 20px 40px;background:none;border-radius:0;font:\(size)px/1.55 ui-monospace,Menlo,monospace;tab-size:4;white-space:\(wrap ? "pre-wrap" : "pre");\(wrap ? "word-break:break-word" : "")}.source code{font:inherit}.gutter{color:var(--ink3);text-align:right;user-select:none;\(wrap ? "display:none" : "")}
        .hljs-keyword,.hljs-selector-tag{color:var(--pinkInk)}.hljs-string{color:var(--success)}.hljs-comment{color:var(--ink3);font-style:italic}.hljs-number,.hljs-literal{color:var(--number)}.hljs-title,.hljs-function{color:var(--ink);font-weight:600}
        """
        var body: String; var script = "const src=\(json);"
        if rendered && markdown {
            body = "<article id='c'></article>"
            script += "document.getElementById('c').innerHTML=DOMPurify.sanitize(marked.parse(src,{gfm:true,breaks:false}));document.querySelectorAll('pre code').forEach(c=>hljs.highlightElement(c));renderMarkdownMath(document.getElementById('c'));"
        } else if rendered && ["csv", "tsv"].contains(ext) {
            let rows = csv(text, separator: ext == "tsv" ? "\t" : ",")
            let table = rows.prefix(2000).enumerated().map { index, row in "<tr>" + row.map { "<\(index == 0 ? "th" : "td")>\(escaped($0))</\(index == 0 ? "th" : "td")>" }.joined() + "</tr>" }.joined()
            body = "<article><table>\(table)</table>\(rows.count > 2000 ? "<p>Showing 2,000 of \(rows.count.formatted()) rows.</p>" : "")</article>"
        } else {
            body = "<div class='source'><pre class='gutter' id='g'></pre><pre><code id='s' class='language-\(language)'></code></pre></div>"
            script += "const c=document.getElementById('s');c.textContent=src;document.getElementById('g').textContent=Array.from({length:src.split('\\n').length},(_,i)=>i+1).join('\\n');"
            if highlight && language != "plaintext" { script += "hljs.highlightElement(c);" }
        }
        return "<!doctype html><html><head><meta name='viewport' content='width=device-width, initial-scale=1'><style>\(css)</style><script src='marked.umd.js'></script><script src='purify.min.js'></script><script src='highlight.min.js'></script><link rel='stylesheet' href='KaTeX/katex.min.css'><script src='KaTeX/katex.min.js'></script><script src='markdown-math.js'></script></head><body>\(body)<script>\(script)</script></body></html>"
    }
    static func language(_ ext: String) -> String {
        let aliases = ["js":"javascript", "mjs":"javascript", "jsx":"javascript", "ts":"typescript", "tsx":"typescript", "py":"python", "rb":"ruby", "rs":"rust", "kt":"kotlin", "kts":"kotlin", "h":"c", "cc":"cpp", "hpp":"cpp", "m":"objectivec", "mm":"objectivec", "cs":"csharp", "sh":"bash", "zsh":"bash", "pl":"perl", "htm":"xml", "html":"xml", "vue":"xml", "plist":"xml", "yml":"yaml", "toml":"ini", "conf":"ini", "md":"markdown"]
        if let name = aliases[ext] { return name }
        return "swift javascript typescript python ruby go rust java kotlin c cpp objectivec csharp php bash lua perl r sql css scss less xml json yaml ini markdown dockerfile makefile".split(separator: " ").contains(Substring(ext)) ? ext : "plaintext"
    }
    static func csv(_ text: String, separator: Character) -> [[String]] {
        var rows: [[String]] = [], row: [String] = [], field = "", quoted = false
        let characters = Array(text); var i = 0
        while i < characters.count {
            let c = characters[i]
            if c == "\"" {
                if quoted && i + 1 < characters.count && characters[i + 1] == "\"" { field.append("\""); i += 1 }
                else if quoted || field.isEmpty { quoted.toggle() } else { field.append(c) }
            } else if c == separator && !quoted { row.append(field); field = "" }
            else if (c == "\n" || c == "\r" || c == "\r\n") && !quoted {
                row.append(field); rows.append(row); row = []; field = ""
                if c == "\r" && i + 1 < characters.count && characters[i + 1] == "\n" { i += 1 }
            } else { field.append(c) }
            i += 1
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return rows
    }
    static func inlineImages(_ text: String, directory: URL) -> String {
        var output = text
        for pattern in ["(!\\[[^\\]]*\\]\\()([^\\)]+)(\\))", "(<img[^>]*src=[\"'])([^\"']+)([\"'])"] {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            let matches = regex.matches(in: output, range: NSRange(output.startIndex..., in: output))
            for match in matches.reversed() {
                guard let range = Range(match.range(at: 2), in: output) else { continue }
                let path = String(output[range])
                if URL(string: path)?.scheme != nil || path.hasPrefix("#") { continue }
                let url = directory.appending(path: path.removingPercentEncoding ?? path)
                guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 10 * 1024 * 1024, let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { continue }
                output.replaceSubrange(range, with: "data:\(UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream");base64,\(data.base64EncodedString())")
            }
        }
        return output
    }
}
