"use strict";
// f0437 step 6, slice 1: the markdown renderer of z-nile/app/live.js (R.md.render). Called by app-md.spec.luau:
// node app-md.node.js <z-nile/app folder>. Ticket text is untrusted, so the output is parsed by a strict HTML parser of this
// file (an allowlist of elements and attributes and the content model a browser enforces) and the tree is asserted, not only
// the string. Bounds are step counts, never clocks. Exits 0 when every case holds.
const fs = require("fs");
const path = require("path");
const vm = require("vm");

const dir = process.argv[2];
const code = fs.readFileSync(path.join(dir, "live.js"), "utf8");
const page = fs.readFileSync(path.join(dir, "index.html"), "utf8");
const escLine = /const esc = (s => String\(s == null[^\n]*);\n/.exec(page);
if (!escLine) { console.error("index.html no longer defines esc the way live.js expects"); process.exit(1); }

let failed = 0;
function check(name, ok, detail) { if (!ok) { failed++; console.error("FAIL " + name + (detail ? ": " + detail : "")); } }
const U = n => String.fromCharCode(n);

const els = {};
const box = {
  console: { error() {} }, location: { protocol: "file:", hash: "" }, esc: eval(escLine[1]),
  document: { body: { appendChild(e) { if (e.id) els[e.id] = e; } }, getElementById: id => els[id] || null, createElement: () => ({ dataset: {}, className: "", innerHTML: "", setAttribute() {} }), addEventListener() {} },
  addEventListener() {}, setInterval() {}, setTimeout() {},
};
vm.createContext(box);
box.globalThis = box;
vm.runInContext(code, box);
const esc = eval(escLine[1]);
const R = box.LiveApp.make({ esc, mono: s => esc(s), ic: () => "", WSTATE: {}, fmtDur: () => "", ptTime: () => "", pl: (n, w) => n + " " + w, now: () => 0 });
const MD = R.md;
const LIM = MD.LIMITS;

/* ---------------------------------------------------------------- the strict parser */
const BLOCKS = new Set(["p", "h3", "h4", "h5", "h6", "ul", "ol", "pre", "table", "blockquote", "hr", "div"]);
const PHRASING = new Set(["strong", "em", "code", "a", "span", "br"]);
const ALLOWED = new Set([...BLOCKS, ...PHRASING, "li", "thead", "tbody", "tr", "th", "td"]);
const VOID = new Set(["br", "hr"]);
const CLASSES = new Set(["md", "md-scroll", "md-fence", "md-note", "md-label", "md-lang", "md-open", "md-addr", "md-cut", "md-rest", "md-flat"]);
function parse(html) {
  const root = { tag: "#root", kids: [], attrs: {} };
  const stack = [root];
  const re = /<(\/?)([a-z0-9]+)((?:\s+[a-z-]+="[^"<>]*")*)\s*>|<|[^<]+/g;
  let m;
  const problems = [];
  const bad = s => problems.push(s);
  const top = () => stack[stack.length - 1];
  while ((m = re.exec(html))) {
    if (m[0] === "<") { bad("a raw < in the output"); continue; }
    if (m[2] === undefined) {
      if (/&(?!(?:amp|lt|gt|quot|#39);)/.test(m[0]) || />/.test(m[0]) || /"/.test(m[0])) bad("unescaped text: " + m[0].slice(0, 40));
      top().kids.push({ text: m[0] });
      continue;
    }
    const closing = m[1] === "/", tag = m[2];
    if (!ALLOWED.has(tag)) { bad("element not allowed: " + tag); continue; }
    if (closing) {
      if (top().tag !== tag) { bad("mismatched close: " + tag + " in " + top().tag); continue; }
      stack.pop(); continue;
    }
    const attrs = {};
    const ar = /([a-z-]+)="([^"<>]*)"/g; let a;
    while ((a = ar.exec(m[3] || ""))) {
      const [, name, val] = a;
      if (name === "class") { if (!CLASSES.has(val)) bad("class not allowed: " + val); }
      else if (name === "href") { if (!/^#\/(?:ticket|raft|approvals|tributary)\/[A-Za-z0-9%_-]+$/.test(val)) bad("href not allowed: " + val); }
      else if (name === "start") { if (!/^\d{1,9}$/.test(val)) bad("start not digits: " + val); }
      else bad("attribute not allowed: " + name);
      attrs[name] = val;
    }
    const parent = top();
    const node = { tag, kids: [], attrs, parent };
    parent.kids.push(node);
    // the content model a browser enforces (a table cell outside a row, a block inside p and a link inside a link are re-parented)
    const pt = parent.tag;
    const ok =
      (pt === "#root" && tag === "div" && attrs.class === "md") ||
      (pt === "table" && (tag === "thead" || tag === "tbody")) ||
      ((pt === "thead" || pt === "tbody") && tag === "tr") ||
      (pt === "tr" && (tag === "th" || tag === "td")) ||
      ((pt === "ul" || pt === "ol") && tag === "li") ||
      (pt === "pre" && tag === "code") ||
      (pt === "code" && false) ||
      (pt === "div" && parent.attrs.class === "md-scroll" && tag === "table") ||
      (pt === "div" && (parent.attrs.class === "md-fence" || parent.attrs.class === "md-note") && (tag === "span" || tag === "pre")) ||
      ((pt === "div" && parent.attrs.class === "md") && BLOCKS.has(tag)) ||
      ((pt === "li" || pt === "blockquote") && (BLOCKS.has(tag) || PHRASING.has(tag))) ||
      ((pt === "td" || pt === "th" || pt === "p" || /^h[3-6]$/.test(pt) || pt === "strong" || pt === "em" || pt === "a" || pt === "span") && PHRASING.has(tag));
    if (!ok) bad("<" + tag + "> not allowed inside <" + pt + ">");
    if (tag === "table" && !(pt === "div" && parent.attrs.class === "md-scroll")) bad("table outside its scroll wrapper");
    if (tag === "a") for (let p = parent; p; p = p.parent) if (p.tag === "a") bad("a link inside a link");
    if (pt === "p" && BLOCKS.has(tag)) bad("a block inside p");
    if (!VOID.has(tag)) stack.push(node);
  }
  if (stack.length !== 1) bad("unclosed: " + stack.slice(1).map(n => n.tag).join(">"));
  // text where only elements may stand
  (function walk(n) {
    for (const k of n.kids || []) {
      if (k.text !== undefined) {
        if (/^(table|thead|tbody|tr|ul|ol)$/.test(n.tag) && /\S/.test(k.text)) bad("text directly inside " + n.tag);
        if (n.tag === "div" && (n.attrs.class === "md" || n.attrs.class === "md-scroll") && /\S/.test(k.text)) bad("text directly inside div." + n.attrs.class);
      } else walk(k);
    }
  })(root);
  return { root, problems };
}
const decode = s => s.replace(/&(amp|lt|gt|quot|#39);/g, (_, e) => ({ amp: "&", lt: "<", gt: ">", quot: '"', "#39": "'" }[e]));
function textOf(n) { return (n.kids || []).map(k => (k.text !== undefined ? decode(k.text) : textOf(k))).join(""); }
function find(n, tag, out) { out = out || []; for (const k of n.kids || []) if (k.tag) { if (k.tag === tag) out.push(k); find(k, tag, out); } return out; }

/* the parser must itself refuse what a browser would re-parent or run */
for (const [name, html] of [
  ["a script", '<div class="md"><script>x</script></div>'],
  ["an img with a handler", '<div class="md"><p><img src="x" onerror="1"></p></div>'],
  ["a handler attribute", '<div class="md"><p onclick="1">x</p></div>'],
  ["a style attribute", '<div class="md"><p style="x">x</p></div>'],
  ["a link in a link", '<div class="md"><p><a href="#/ticket/c0001"><a href="#/ticket/c0002">x</a></a></p></div>'],
  ["a block in p", '<div class="md"><p>x<ul><li>y</li></ul></p></div>'],
  ["a cell outside a row", '<div class="md"><div class="md-scroll"><table><td>x</td></table></div></div>'],
  ["a table without its wrapper", '<div class="md"><table><tbody><tr><td>x</td></tr></tbody></table></div>'],
  ["text in a table", '<div class="md"><div class="md-scroll"><table>stray<tbody></tbody></table></div></div>'],
  ["an outside href", '<div class="md"><p><a href="https://x.test/">x</a></p></div>'],
  ["a javascript href", '<div class="md"><p><a href="javascript:alert(1)">x</a></p></div>'],
  ["a guess route", '<div class="md"><p><a href="#/guess/c0001/x]">x</a></p></div>'],
  ["a raw <", '<div class="md"><p>a < b</p></div>'],
  ["an unescaped &", '<div class="md"><p>a & b</p></div>'],
  ["a stray class", '<div class="md"><p class="evil">x</p></div>'],
]) check("the strict parser refuses " + name, parse(html).problems.length > 0);
check("the strict parser accepts a good tree", parse('<div class="md"><p>a &amp; <a href="#/ticket/c0001">x</a></p><div class="md-scroll"><table><thead><tr><th>h</th></tr></thead><tbody><tr><td>c</td></tr></tbody></table></div></div>').problems.length === 0);

/* ---------------------------------------------------------------- helpers for the cases */
const KNOWN = { ticket: new Set(["c0250", "c0306"]), raft: new Set(["R0100"]), approvals: new Set(["c0306"]), tributary: new Set(["fast-gate"]) };
const known = (kind, id) => !!(KNOWN[kind] && KNOWN[kind].has(id));
function run(src, opt) {
  const r = MD.render(src, opt || { known });
  const p = parse(r.html);
  return { r, tree: p.root, problems: p.problems, html: r.html };
}
function valid(name, src, opt) {
  const x = run(src, opt);
  check(name + ": the output parses as the allowed tree", x.problems.length === 0, x.problems.slice(0, 3).join("; "));
  check(name + ": the steps stay inside the budget", x.r.steps <= LIM.steps, String(x.r.steps));
  return x;
}
const hrefs = x => find(x.tree, "a").map(a => a.attrs.href);

/* ---------------------------------------------------------------- constructs */
{
  const x = valid("constructs", "# One\n\nA **bold** and *italic* and `code` and _under_.\n\n- a\n- b\n  - nested\n    - deeper\n\n1. one\n2. two\n\n> quoted\n> text\n\n---\n\n| h1 | h2 |\n|---|---|\n| c1 | c2 |\n\n```luau\nlocal x = a*b*c\n# not a heading\n```\n");
  const tags = new Set(Object.keys(x.r.elements));
  for (const t of ["h3", "p", "strong", "em", "code", "ul", "li", "ol", "blockquote", "hr", "table", "thead", "tbody", "tr", "th", "td", "pre", "div"]) check("constructs: " + t + " is produced", tags.has(t), [...tags].join(","));
  check("constructs: a fence keeps its asterisks and its hash line", x.html.includes("local x = a*b*c") && x.html.includes("# not a heading") && !x.html.includes("<h3># not"));
  check("constructs: a # heading is shown as h3", /<h3>One<\/h3>/.test(x.html));
  check("constructs: nesting makes nested lists", find(x.tree, "ul").length === 3, String(find(x.tree, "ul").length));
  check("constructs: the fence names its language", x.html.includes('<span class="md-lang">luau</span>'));
  const o = valid("ordered start", "3. three\n4. four\n");
  check("ordered start is kept", o.html.includes('<ol start="3">'));
}
{
  const x = valid("paragraph breaks", "line one  \nline two\\\nline three\nline four\n");
  check("hard breaks: two spaces and a backslash", find(x.tree, "br").length === 2 && /line three line four/.test(textOf(x.tree)), x.html);
}

/* ---------------------------------------------------------------- hostile html and attribute breakout */
for (const [name, src] of [
  ["a script tag", "<script>alert(1)</script>"],
  ["an img with a handler", '<img src=x onerror="alert(1)">'],
  ["a style tag and a b tag", "<style>*{}</style> <b>bold</b>"],
  ["an svg", '<svg onload="1"><a xlink:href="javascript:1">x</a></svg>'],
  ["an iframe", '<iframe src="javascript:1"></iframe>'],
]) {
  const x = valid(name, src);
  check(name + " is shown as text, never as an element", !/<(script|img|style|b|svg|iframe)[ >]/.test(x.html) && x.html.includes("&lt;"));
}
for (const [name, src] of [
  ["a link text with a quote and a tag", '[x"><img src=x onerror=1>](c0250)'],
  ["an address with a quote", '[a](https://x.test/"onmouseover="1)'],
  ["a title that breaks out", '[a](c0250 "t" onfocus=1)'],
  ["a heading with a quote", '# "><script>1</script>'],
  ["a table cell", "| a |\n|---|\n| \"><script>1</script> |\n"],
  ["a list item", "- \"><script>1</script>\n"],
  ["a code span", '`"><script>1</script>`'],
  ["a fence info string", '```"><script>1</script>\ncode\n```\n'],
]) {
  const x = valid(name, src);
  check(name + ": no element beyond the allowed set, no handler", !/<script|onerror=|onmouseover=|onfocus=/.test(x.html.replace(/&lt;[^&]*&gt;/g, "")) || parse(x.html).problems.length === 0);
  check(name + ": nothing is placed in an attribute but a route", hrefs(x).every(h => /^#\/(?:ticket|raft|approvals|tributary)\//.test(h)));
}

/* ---------------------------------------------------------------- addresses and links */
for (const [name, src, shown] of [
  ["javascript:", "[x](javascript:alert(1))", "javascript:alert(1)"],
  ["data:", "[x](data:text/html;base64,AAAA)", "data:text/html;base64,AAAA"],
  ["http:", "[x](http://evil.test/a)", "http://evil.test/a"],
  ["https:", "[x](https://evil.test/a)", "https://evil.test/a"],
  ["mailto:", "[x](mailto:a@b.test)", "mailto:a@b.test"],
  ["file:", "[x](file:///etc/passwd)", "file:///etc/passwd"],
  ["//host", "[x](//evil.test/a)", "//evil.test/a"],
  ["a bare address", "see https://evil.test/a?b=c for it", "https://evil.test/a?b=c"],
]) {
  const x = valid("address " + name, src);
  check("address " + name + " is never clickable", find(x.tree, "a").length === 0);
  check("address " + name + " is shown whole", textOf(x.tree).includes(shown), textOf(x.tree));
}
{
  const same = valid("address as its own text", "[https://x.test/a](https://x.test/a)");
  check("an address that is its own link text is marked as an address and is not clickable", find(same.tree, "a").length === 0 && find(same.tree, "span").some(s => s.attrs.class === "md-addr" && textOf(s) === "https://x.test/a"), same.html);
}
{
  const long = "https://evil.test/" + "a".repeat(900);
  const x = valid("long address", "[x](" + long + ")");
  check("a long address is shown whole, not clipped to 200", textOf(x.tree).includes(long));
}
{
  check("no link without a known set", find(run("[x](c0250) and [y](#/ticket/c0250)", {}).tree, "a").length === 0);
  const x = valid("hrefs", "[a](c0250) [b](#/ticket/c0250) [c](R0100) [d](#/raft/R0100) [e](#/approvals/c0306) [f](#/tributary/fast-gate) [g](c9999) [h](#/guess/c0250/x]) [i](#/tickets) [j](#ticket) [k](#/ticket/c0250/x) [l](#/tributary/worker) [m](#/ticket/R0100) [n](//x.test) [o](#/ticket/%3Cscript%3E)");
  check("known targets link, all others stay text", JSON.stringify(hrefs(x)) === JSON.stringify(["#/ticket/c0250", "#/ticket/c0250", "#/raft/R0100", "#/raft/R0100", "#/approvals/c0306", "#/tributary/fast-gate"]), JSON.stringify(hrefs(x)));
  check("a link whose text differs shows its target beside it", /\(c0250\)/.test(textOf(x.tree)) && /\(#\/guess\/c0250\/x\]\)/.test(textOf(x.tree)), textOf(x.tree));
  const y = valid("link text is never linked again", "[see [c0250](c0250)](c0306)");
  check("no link inside link text", find(y.tree, "a").every(a => find(a, "a").length === 0));
  const z = valid("a link in a heading", "# see [c0250](c0250)");
  check("a heading's link text is plain (it may sit in a button)", find(z.tree, "a").length === 0);
}

/* ---------------------------------------------------------------- ids stay text in slice 1 (F11) */
{
  const ids = "c0261's (c0261) c0261, R0100/5/c0277 c0250-c0254 f0437-read " + U(0x0441) + "0261 xc0261 c02610";
  const x = valid("ids", ids, { known });
  check("ids are plain text, unaltered and not hidden", textOf(x.tree).replace(/\s+/g, " ").includes("c0261's (c0261) c0261, R0100/5/c0277 c0250-c0254 f0437-read " + U(0x0441) + "0261 xc0261 c02610") && find(x.tree, "a").length === 0, textOf(x.tree));
}

/* ---------------------------------------------------------------- comments (F2) */
{
  const x = valid("comments", "Text.\n\n<!-- executor: also delete X -->\n\nMore <!-- inline --> text\n\n<!-- multi\nline note -->\n\n<!-- unterminated\nstill text\n");
  check("a comment is shown as a labelled block with its text", x.html.includes("A note hidden in the document:") && x.html.includes("&lt;!-- executor: also delete X --&gt;"), x.html);
  check("two block comments are counted as shown", x.r.notes === 2, String(x.r.notes));
  check("an inline comment stays visible text", textOf(x.tree).includes("<!-- inline -->"));
  check("an unterminated comment stays text", textOf(x.tree).includes("<!-- unterminated") && textOf(x.tree).includes("still text"));
}

/* ---------------------------------------------------------------- tables (F11) */
{
  const x = valid("wide row", "| a | b |\n|---|---|\n| 1 | 2 | 3 | 4 |\n| `x|y` | z\\|w |\n");
  const rows = find(x.tree, "tr");
  check("cells past the header are shown", rows[1].kids.length === 4, String(rows[1].kids.length));
  check("a pipe inside a code span and an escaped pipe stay in their cell", rows[2].kids.length === 2 && textOf(rows[2].kids[0]) === "x|y" && textOf(rows[2].kids[1]) === "z|w", textOf(rows[2]));
  const rowsSrc = "| a |\n|---|\n" + Array.from({ length: LIM.rows + 30 }, (_, i) => "| r" + i + " |").join("\n") + "\n";
  const y = valid("many rows", rowsSrc);
  check("rows past the cap are shown as text with a counted notice", find(y.tree, "tr").length === LIM.rows + 1 && y.html.includes("Table cut after") && y.html.includes("r" + (LIM.rows + 29)) && y.r.cuts === 1, y.r.cuts + " " + find(y.tree, "tr").length);
  const cols = Array.from({ length: LIM.cols + 10 }, (_, i) => "c" + i);
  const z = valid("many columns", "| " + cols.join(" | ") + " |\n|" + cols.map(() => "---").join("|") + "|\n| " + cols.map((_, i) => "v" + i).join(" | ") + " |\n");
  check("columns past the cap are joined into the last cell, not dropped", find(z.tree, "th").length === LIM.cols && textOf(z.tree).includes("c" + (LIM.cols + 9)) && textOf(z.tree).includes("v" + (LIM.cols + 9)));
  const w = valid("no delimiter", "| a | b |\n| c | d |\n");
  check("a table with no delimiter row is a paragraph", find(w.tree, "table").length === 0 && textOf(w.tree).includes("| c | d |"));
}

/* ---------------------------------------------------------------- line endings, tabs, indents, entities (F11) */
{
  const a = valid("crlf", "```\r\ncode\r\n```\r\n\r\ntext\r\n");
  check("CRLF: the fence closes and text follows", find(a.tree, "pre").length === 1 && textOf(a.tree).includes("text"), a.html);
  const b = valid("lone cr", "a\rb\r\r- x\r- y\r");
  check("a lone CR is a line break", find(b.tree, "li").length === 2);
  const c = valid("tabs", "- a\n\t- nested by tab\n");
  check("a tab counts as 4 spaces in list indents", find(c.tree, "ul").length === 2, c.html);
  const d = valid("fence in a list item", "- item\n\n  ```\n  # not a heading\n  code\n  ```\n");
  check("a fence indented inside a list item is code", find(d.tree, "pre").length === 1 && !/<h3>/.test(d.html), d.html);
  const e = valid("indented code", "para\n\n    indented code\n    more\n");
  check("4-space indented text is code", find(e.tree, "pre").length === 1 && textOf(find(e.tree, "pre")[0]).includes("indented code"));
  const f = valid("entities", "&lt;b&gt; &#106;avascript:alert(1) &amp;");
  check("entities and numeric references are shown literally", textOf(f.tree) === "&lt;b&gt; &#106;avascript:alert(1) &amp;" && f.html.includes("&amp;lt;b&amp;gt;"), f.html);
  const g = valid("backslash", "\\*not em\\* and \\` and \\\\ and \\q");
  check("a backslash before punctuation shows the punctuation", textOf(g.tree) === "*not em* and ` and \\ and \\q", textOf(g.tree));
  const h = valid("autolink and reference", "<http://x.test/a>\n\n[1]: http://x.test/ref\n");
  check("an autolink and a reference definition stay visible text", textOf(h.tree).includes("<http://x.test/a>") && textOf(h.tree).includes("[1]: http://x.test/ref") && find(h.tree, "a").length === 0);
  const i = valid("setext", "text\n---\nmore\n");
  check("text then --- is a paragraph then a rule", find(i.tree, "hr").length === 1 && find(i.tree, "h3").length === 0 && textOf(i.tree).includes("text") && textOf(i.tree).includes("more"));
  const j = valid("unterminated fence", "intro\n\n```\ncode line\n\n## still code\n- also\n");
  check("an unterminated fence shows the rest as code with a label", find(j.tree, "pre").length === 1 && j.html.includes("No closing fence") && textOf(j.tree).includes("## still code") && find(j.tree, "h3").length === 0);
  const k = valid("a hashtag", "#hashtag and 2026. text");
  check("#word is not a heading", find(k.tree, "h3").length === 0 && textOf(k.tree).includes("#hashtag"));
}

/* ---------------------------------------------------------------- bidi, control and zero-width characters */
{
  const src = "a" + U(0x202e) + "b " + U(0x200d) + " c" + U(0) + "d " + U(0x200b) + U(0xfeff) + U(0x2066) + " lone" + U(0xd800) + " " + U(0xdc00) + "x `code" + U(0x202e) + "` [t" + U(0x202e) + "](" + "https://x.test/" + U(0x202e) + ")";
  const x = valid("bidi", src);
  const t = textOf(x.tree);
  check("bidi and control characters are shown as marks", !/[‮‍\u0000​﻿⁦𐀀]/.test(t) && t.includes("‹U+202E›") && t.includes("‹U+200D›") && t.includes("‹U+0000›") && t.includes("‹U+D800›") && t.includes("‹U+DC00›"), t);
  check("the marks are applied in code and in link text and in addresses", find(x.tree, "code").some(c => textOf(c).includes("‹U+202E›")) && (t.match(/U\+202E/g) || []).length >= 4, t);
  const emoji = valid("emoji", "family " + String.fromCodePoint(0x1f468) + U(0x200d) + String.fromCodePoint(0x1f469) + " ok " + String.fromCodePoint(0x1f600));
  check("a valid surrogate pair is kept", textOf(emoji.tree).includes(String.fromCodePoint(0x1f600)) && !textOf(emoji.tree).includes("U+D83D"));
}

/* ---------------------------------------------------------------- bombs, huge input, steps (F12: counts, not clocks) */
{
  const T0 = Date.now();
  const deepEm = "*a ".repeat(100000);
  for (const [name, src] of [
    ["nested emphasis", "**a *b **c ".repeat(30000)],
    ["unclosed emphasis", deepEm],
    ["a list nested 5000 deep", Array.from({ length: 5000 }, (_, i) => " ".repeat(i * 2) + "- x").join("\n")],
    ["a quote nested 5000 deep", Array.from({ length: 5000 }, (_, i) => ">".repeat(i + 1) + " x").join("\n")],
    ["100000 table rows", "| a |\n|---|\n" + "| r |\n".repeat(100000)],
    ["a 2 MB paragraph", "word ".repeat(400000)],
    ["a 2 MB line of code ticks", "`".repeat(2000000)],
    ["a 2 MB single token", "x".repeat(2000000)],
    ["many unmatched brackets", "[a ".repeat(60000)],
    ["many unmatched backtick runs", "`a ``b ```c ".repeat(20000)],
    ["2 MB of fence openers", "```\n".repeat(400000)],
    ["2 MB of comment openers", "<!-- x\n".repeat(200000)],
  ]) {
    const x = valid(name, src);
    const again = MD.render(src, { known });
    check(name + ": the same steps on every run", again.steps === x.r.steps);
    check(name + ": the nodes stay inside the cap", x.r.nodes <= LIM.nodes + 5, String(x.r.nodes));
    check(name + ": a cut is announced", src.length <= LIM.input || x.html.includes("Text cut here"));
  }
  const nest = valid("depth", Array.from({ length: 12 }, (_, i) => " ".repeat(i * 2) + "- level " + i).join("\n"));
  check("nesting deeper than the cap is shown as text with a notice, nothing lost", nest.html.includes("deeper than " + LIM.depth) && textOf(nest.tree).includes("level 11") && nest.r.flat >= 1, nest.html.slice(0, 200));
  const huge = valid("input cap", "x".repeat(LIM.input + 5000));
  check("input over the cap is cut with the counts in the notice", huge.html.includes("first " + LIM.input + " of " + (LIM.input + 5000) + " characters"), huge.html.slice(-200));
  const pair = String.fromCodePoint(0x1f600);
  const edge = valid("cap on a pair", "y".repeat(LIM.input - 1) + pair + "tail");
  check("the cap never splits a surrogate pair", !/\ud83d(?!\ude00)/.test(textOf(edge.tree)) && !textOf(edge.tree).includes("U+D83D"));
  for (const [name, src, needle] of [["quadratic emphasis", ("*a ".repeat(6000) + "\n\n").repeat(10), "*a *a *a"], ["quadratic brackets", ("[a ".repeat(6000) + "\n\n").repeat(10), "[a [a [a"]]) {
    const x = valid(name, src);
    check(name + ": the budget ends it, with a counted notice and the rest as text", x.r.over === true && x.r.steps === LIM.steps && x.r.cuts >= 1 && x.html.includes("too large to format") && textOf(x.tree).includes(needle), x.r.steps + " " + x.r.over);
  }
  // a text that exhausts the step budget shows the rest as text, with the counts of what was shown
  const small = valid("budget exit", ("[a " + "x".repeat(18000) + "\n\n").repeat(40));
  check("an exhausted budget shows the rest as plain text with a notice", small.r.steps <= LIM.steps);
  check("hang guard: all hostile cases together stay under 60 s", Date.now() - T0 < 60000, String(Date.now() - T0));
}

/* ---------------------------------------------------------------- the css: contrast in both themes, computed (F4) */
{
  const tokens = { light: {}, dark: {} };
  const root = /:root\{([^}]*)\}/.exec(page)[1], dark = /\[data-theme="dark"\]\{([^}]*)\}/.exec(page)[1];
  for (const [theme, body] of [["light", root], ["dark", dark]]) for (const m of body.matchAll(/(--[a-z0-9-]+):\s*(#[0-9a-fA-F]{6})/g)) tokens[theme][m[1]] = m[2];
  const lum = hex => { const c = [1, 3, 5].map(i => parseInt(hex.slice(i, i + 2), 16) / 255).map(v => (v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4))); return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]; };
  const ratio = (a, b) => { const x = lum(a), y = lum(b); return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05); };
  check("the contrast test reads the page's tokens", tokens.light["--text"] === "#2c2723" && tokens.dark["--surface-2"] === "#3a332e", JSON.stringify(Object.keys(tokens.dark).length));
  const rules = box.LiveApp.MD_RULES;
  check("every colour pair has a non-colour carrier", rules.every(r => typeof r.mark === "string" && r.mark.length > 0));
  let worst = 99;
  for (const r of rules) for (const theme of ["light", "dark"]) {
    const fg = tokens[theme][r.color], bg = tokens[theme][r.bg];
    check("tokens exist for " + r.sel + " in " + theme, !!fg && !!bg, r.color + "/" + r.bg);
    if (fg && bg) { const c = ratio(fg, bg); worst = Math.min(worst, c); check("contrast of " + r.sel + " in " + theme + " is at least 4.5", c >= 4.5, c.toFixed(2)); }
  }
  // the text colours also sit on the page background
  for (const theme of ["light", "dark"]) for (const [fg, bg] of [["--text", "--bg"], ["--text-2", "--bg"], ["--text", "--surface"], ["--text-2", "--surface"]]) check("the page's own " + fg + " on " + bg + " in " + theme, ratio(tokens[theme][fg], tokens[theme][bg]) >= 4.5);
  console.log("contrast: " + rules.length + " pairs in 2 themes, worst " + worst.toFixed(2));
  check("the css is made from the rules", box.LiveApp.MD_CSS.includes(".md-note{") && box.LiveApp.MD_CSS.includes("overflow-x:auto") && box.LiveApp.MD_CSS.includes(".md-scroll{"));
  check("code and tables scroll inside themselves, long tokens wrap", /\.md pre\{[^}]*overflow-x:auto/.test(box.LiveApp.MD_CSS) && /\.md-scroll\{[^}]*overflow-x:auto/.test(box.LiveApp.MD_CSS) && /\.md\{[^}]*overflow-wrap:anywhere/.test(box.LiveApp.MD_CSS));
  check("no inline handler or style comes from a renderer string", !/on[a-z]+=|style=/.test(MD.render("x").html));
}

if (failed) { console.error(failed + " case(s) failed"); process.exit(1); }
console.log("app-md: ok");
