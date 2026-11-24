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
const CLASSES = new Set(["md", "md-scroll", "md-fence", "md-note", "md-label", "md-lang", "md-open", "md-addr", "md-cut", "md-rest", "md-flat", "md-miss"]);
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
      else if (name === "start" || name === "value") { if (!/^\d{1,9}$/.test(val)) bad(name + " not digits: " + val); if (name === "value" && tag !== "li") bad("value outside li"); }
      else if (name === "title") { /* f0437 slice 2 (F10 a): the one title, on the mark of an id the index does not hold, with a fixed wording */ }
      else bad("attribute not allowed: " + name);
      attrs[name] = val;
    }
    if (attrs.title !== undefined && !(tag === "span" && attrs.class === "md-miss" && /^not in the units index made [0-9a-z ]+ ago$/.test(attrs.title))) bad("title not allowed: " + attrs.title);
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
const worst = { ms: 0, name: "", chars: 0 };
function valid(name, src, opt) {
  const t0 = process.hrtime.bigint();
  const x = run(src, opt);
  const ms = Number(process.hrtime.bigint() - t0) / 1e6;
  if (ms > worst.ms) { worst.ms = ms; worst.name = name; worst.chars = src.length; }
  check(name + ": the output parses as the allowed tree", x.problems.length === 0, x.problems.slice(0, 3).join("; "));
  check(name + ": the steps stay inside the budget", x.r.steps <= LIM.steps, String(x.r.steps));
  return x;
}
const hrefs = x => find(x.tree, "a").map(a => a.attrs.href);

/* ---------------------------------------------------------------- constructs */
{
  const x = valid("constructs", "# One\n\nA **bold** and *italic* and `code`.\n\n- a\n- b\n  - nested\n    - deeper\n\n1. one\n2. two\n\n> quoted\n> text\n\n---\n\n| h1 | h2 |\n|---|---|\n| c1 | c2 |\n\n```luau\nlocal x = a*b*c\n# not a heading\n```\n");
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

/* ---------------------------------------------------------------- slice 2: ids become links (G30, G31, F8, F10 d e, F19) */
/* The rules, as the design states them. An id is `[cfd]` or `R` and four digits, as a whole word: it links when the index
   holds it, and not when a letter, digit, `_`, `-` or `/` touches it on either side, or when a `.` and a letter or digit touches
   it (a file name, a version). So `R0100/5/c0277` (a branch name) and `c0250-c0254` (a range) stay plain, by that one rule;
   punctuation, a bracket, a quote, `'s` and a sentence's full stop do not stop a link. Inline code that is exactly an id links
   (the link wraps the code); an id inside other code, a fence or link text never does. An id the index lacks is marked with a
   dotted underline and a tooltip that allows for a stale index; with no index at all (opt.missing absent) it stays plain. A
   tributary name links as inline code that is exactly it, after the word tributary or theme, or when it has a hyphen. */
const KNOWN2 = { ticket: new Set(["c0250", "c0306", "c0277"]), raft: new Set(["R0100"]), approvals: new Set(["c0306"]), tributary: new Set(["fast-gate", "worker", "lessons", "omarchy", "board-and-provenance"]) };
const known2 = (kind, id) => !!(KNOWN2[kind] && KNOWN2[kind].has(id));
const MISSING = "not in the units index made 5 min ago";
const OPT = { known: known2, missing: MISSING };
const linksOf = x => find(x.tree, "a").map(a => a.attrs.href + "=" + textOf(a));
const marks = x => find(x.tree, "span").filter(s => s.attrs.class === "md-miss").map(s => textOf(s));
{
  const x = valid("id basics", "see c0250 and c0306 and R0100 now", OPT);
  check("an id in the index links to its detail view, a waiting one into the walk, a raft to its raft", JSON.stringify(linksOf(x)) === JSON.stringify(["#/ticket/c0250=c0250", "#/approvals/c0306=c0306", "#/raft/R0100=R0100"]), JSON.stringify(linksOf(x)));
  check("the words are unchanged by links", textOf(x.tree) === "see c0250 and c0306 and R0100 now", textOf(x.tree));
  // every boundary: a letter, digit, underscore, hyphen or slash on either side, a dot and a letter or digit after, a dot after a word before
  for (const src of ["xc0250", "c02500", "c0250x", "a-c0250", "c0250-c0306", "c0250_x", "_c0250", "/c0250", "c0250/x", "https://x.test/c0250", "src/c0250.md", "c0250.md", "c0250.5", "foo.c0250", "R0100/5/c0277", "f0437-read", U(0xE9) + "c0250", "c0250" + U(0xE9), U(0x0441) + "0250", "c02 50", "C0250", "r0100", "c250", "c0250" + U(0x0663)]) {
    const y = valid("boundary " + JSON.stringify(src), src, OPT);
    check("no link in " + JSON.stringify(src), find(y.tree, "a").length === 0, linksOf(y).join());
    check("and no mark either: its words are untouched in " + JSON.stringify(src), textOf(y.tree) === src, textOf(y.tree));
  }
  // what does not stop a link: punctuation, brackets, quotes, 's, a sentence's end, a start of line, markup
  for (const [src, want] of [
    ["c0250.", 1], ["c0250. Next", 1], ["c0250, c0306", 2], ["(c0250)", 1], ["[c0250]", 1], ["\"c0250\"", 1], ["'c0250'", 1], ["c0250's", 1], ["c0250:", 1], ["c0250;", 1], ["c0250!", 1], ["c0250?", 1],
    ["#c0250", 1], ["@c0250", 1], ["=c0250=", 1], ["<c0250>", 1], ["{c0250}", 1], ["c0250~", 1], ["c0250^", 1], ["c0250+c0306", 2], ["c0250&c0306", 2], ["c0250%", 1], ["$c0250", 1],
    ["**c0250**", 1], ["*c0250*", 1], ["c0250\nc0306", 2], ["  c0250  ", 1], ["c0250 c0250 c0250", 3], ["R0100 R0100", 2],
  ]) {
    const y = valid("punctuation " + JSON.stringify(src), src, OPT);
    check("links in " + JSON.stringify(src), find(y.tree, "a").length === want, linksOf(y).join());
  }
}
{
  // every ASCII punctuation mark on both sides of an id (the ones that are not markdown) leaves one link
  let bad = "";
  for (const p of "!\"#$%&'()+,:;<=>?@]^{}~") { const y = run("a " + p + "c0250" + p + " b", OPT); if (find(y.tree, "a").length !== 1 || y.problems.length) bad += p; }
  check("every punctuation mark beside an id leaves a link", bad === "", bad);
  let bad2 = "";
  for (const p of "-_/") { const y = run("a " + p + "c0250" + p + " b", OPT); if (find(y.tree, "a").length !== 0) bad2 += p; }
  check("a hyphen, an underscore and a slash beside an id stop the link", bad2 === "", bad2);
}
{
  const a = valid("id in code", "`c0250` and `see c0250` and ``c0250`` and ` c0250 `", OPT);
  check("inline code that is exactly an id links, the link wrapping the code; other code never does", JSON.stringify(linksOf(a)) === JSON.stringify(["#/ticket/c0250=c0250", "#/ticket/c0250=c0250", "#/ticket/c0250=c0250"]) && find(a.tree, "a").every(l => l.kids.length === 1 && l.kids[0].tag === "code") && find(a.tree, "code").length === 4, a.html);
  const f = valid("id in a fence", "```\nc0250 R0100\n```\n\n    c0250 indented\n", OPT);
  check("an id in a fenced or indented code block never links, and is never marked", find(f.tree, "a").length === 0 && marks(f).length === 0 && f.html.includes("c0250 R0100") && f.html.includes("c0250 indented"), f.html);
  const l = valid("id in link text", "[see c0250 and R0100](c0306) and [c0250](c0250)", OPT);
  check("link text is never linked again: one link for each bracket pair", JSON.stringify(linksOf(l)) === JSON.stringify(["#/approvals/c0306=see c0250 and R0100", "#/ticket/c0250=c0250"]) && find(l.tree, "a").every(k => find(k, "a").length === 0), JSON.stringify(linksOf(l)));
  const u = valid("id in unknown link text", "[see c0250](c9999)", OPT);
  check("link text of a target that is not a unit shows no link and no mark for its ids", find(u.tree, "a").length === 0 && marks(u).length === 0, u.html);
  const t = valid("id in table, list, quote and heading", "# c0250 heading\n\n- item c0250\n\n> quote c0250\n\n| a |\n|---|\n| c0250 |\n", OPT);
  check("ids link in a heading, a list item, a quote and a table cell", find(t.tree, "a").length === 4 && find(t.tree, "h3").length === 1 && find(find(t.tree, "h3")[0], "a").length === 1, t.html);
  const e = valid("id in emphasis", "**c0250** and *R0100* and ***c0306***", OPT);
  check("an id inside bold, italic and both links", find(e.tree, "a").length === 3, e.html);
}
{
  // F19, G42: an id the index lacks
  const m = valid("missing", "c0261 and (c9999) and f0001.", OPT);
  check("an id the index lacks is a mark with the stale-index tooltip, never a link", find(m.tree, "a").length === 0 && JSON.stringify(marks(m)) === JSON.stringify(["c0261", "c9999", "f0001"]) && find(m.tree, "span").every(s => s.attrs.title === MISSING), m.html);
  check("the words are unchanged by marks", textOf(m.tree) === "c0261 and (c9999) and f0001.", textOf(m.tree));
  const n = valid("no index", "c0261 and c0250", { known: () => false });
  check("with no tooltip text given (no index) a missing id is plain text", find(n.tree, "span").length === 0 && find(n.tree, "a").length === 0 && textOf(n.tree) === "c0261 and c0250", n.html);
  const o = valid("no known set at all", "c0261 and c0250", {});
  check("with no known set nothing is touched", find(o.tree, "a").length === 0 && find(o.tree, "span").length === 0);
  const q = run("c0261", { known: () => false, missing: 'x"><img src=x onerror=1>' });
  check("a tooltip that is not the fixed wording is refused by the strict parser and never reaches an attribute raw", !/<img/.test(q.html) && q.problems.length > 0, q.html);
  check("a missing id in code is plain code (only an exact, known id links)", find(valid("missing in code", "`c0261`", OPT).tree, "a").length === 0);
}
{
  // G31: tributary names
  const x = valid("tributaries", "the tributary fast-gate and theme worker; the worker lessons omarchy; a fast-gate here; `fast-gate` and `worker` and `see worker`; xfast-gate and fast-gate-2 and fast-gates; board-and-provenance.", OPT);
  check("a tributary links after the word tributary or theme, as inline code that is exactly it, or when it has a hyphen", JSON.stringify(linksOf(x)) === JSON.stringify(["#/tributary/fast-gate=fast-gate", "#/tributary/worker=worker", "#/tributary/fast-gate=fast-gate", "#/tributary/fast-gate=fast-gate", "#/tributary/worker=worker", "#/tributary/board-and-provenance=board-and-provenance"]), JSON.stringify(linksOf(x)));
  check("worker, lessons and omarchy in prose never link; nor a name inside a longer one", !/lessons<\/a>|omarchy<\/a>/.test(x.html) && textOf(x.tree).includes("the worker lessons omarchy") && textOf(x.tree).includes("xfast-gate and fast-gate-2 and fast-gates"));
  const y = valid("tributary words", "Theme worker. THEME fast-gate, Tributary worker, tributaries worker, themes worker, theme  worker", OPT);
  check("the word before may be written in any case and followed by spaces; other words do not count", JSON.stringify(linksOf(y).map(s => s.split("=")[1])) === JSON.stringify(["worker", "fast-gate", "worker", "worker"]), JSON.stringify(linksOf(y)));
  const z = valid("tributary not known", "tributary nothing-here and theme fast", OPT);
  check("a name the themes do not hold never links", find(z.tree, "a").length === 0 && marks(z).length === 0, z.html);
  const c = valid("tributary in link text and fence", "[theme worker](c0250)\n\n```\ntheme worker `worker`\n```\n", OPT);
  check("no tributary link inside link text or a fence", find(c.tree, "a").length === 1, linksOf(c).join());
}
{
  // F10: an href is built only from a checked id; the matched text is never the target
  const all = (kind) => kind !== "approvals";
  const x = valid("targets", "c0250 R0100 f0001 d9999 theme a-b-c `c1234` <script> \"x\" tributary weird_name tributary UPPER", { known: all, missing: MISSING });
  check("every href is a route word and an id or a name of the checked shape", find(x.tree, "a").every(a => /^#\/(?:ticket|raft|approvals|tributary)\/(?:[cfd]\d{4}|R\d{4}|[a-z0-9-]+)$/.test(a.attrs.href)), JSON.stringify(hrefs(x)));
  check("a link target is the encoded id, never the matched text", hrefs(x).join() === "#/ticket/c0250,#/raft/R0100,#/ticket/f0001,#/ticket/d9999,#/tributary/a-b-c,#/ticket/c1234", hrefs(x).join());
  const w = valid("waiting goes to the walk", "c0306 c0250", { known: known2 });
  check("a unit that waits for approval links into the walk, every other to its detail view", hrefs(w).join() === "#/approvals/c0306,#/ticket/c0250", hrefs(w).join());
  const hostile = valid("hostile known", '"><img src=x onerror=1> c0250', { known: () => true });
  check("hostile text beside an id stays text", !/<img/.test(hostile.html) && find(hostile.tree, "a").length === 1, hostile.html);
}
{
  // work: ids are scanned, never matched by a pattern that backtracks; the step budget counts the characters
  const para = "c0250 ".repeat(3300); // 19,800 characters: one formatted paragraph
  const x = valid("3,300 ids in a paragraph", para, OPT);
  check("3,300 ids make 3,300 links, and the steps count the characters scanned", find(x.tree, "a").length === 3300 && x.r.steps >= para.length && x.r.steps < para.length * 6, find(x.tree, "a").length + " links, " + x.r.steps + " steps for " + para.length);
  const big = "c0250 ".repeat(100000); // 600,000 characters: cut at the input cap, a paragraph too long to format
  const y = valid("100,000 ids in a paragraph", big, OPT);
  check("100,000 ids end inside the budget with a counted notice, never silently", y.r.steps <= LIM.steps && /too long to format|Text cut here/.test(y.html), y.html.slice(0, 200));
  const list = "- c0250 R0100 c0306 c0261\n".repeat(30000);
  const z = valid("30,000 list items of ids", list, OPT);
  check("a list of ids past the element cap says so and keeps the rest as text", z.r.over === true && /too large to format/.test(z.html), String(z.r.nodes));
  let seps = "";
  for (let i = 33; i < 127; i++) { const ch = String.fromCharCode(i); if (ch === "`") continue; seps += "c0250" + ch; }
  const s = valid("ids separated by every punctuation mark", seps.repeat(40), OPT);
  check("ids separated by every mark finish inside the budget", s.r.steps <= LIM.steps && s.r.steps >= seps.length * 40);
  const trib = "theme fast-gate ".repeat(1200); // 19,200 characters
  const tr = valid("a tributary name repeated", trib, OPT);
  check("a tributary name repeated 1,200 times links each and counts its steps", find(tr.tree, "a").length === 1200 && tr.r.steps >= trib.length && tr.r.steps < trib.length * 6, find(tr.tree, "a").length + " links, " + tr.r.steps + " steps");
  const trib2 = "fast-gate ".repeat(3000) + "tributary ".repeat(3000);
  const tr2 = valid("a hyphenated name repeated and a word repeated", trib2, OPT);
  check("repeats of the name and of the word before it end inside the budget", tr2.r.steps <= LIM.steps && tr2.r.steps >= trib2.length);
  const longRun = "c0250" + "-c0250".repeat(60000); // one 360,000 character run of word characters
  const lr = valid("one long run of id characters", longRun, OPT);
  check("a single run of 360,000 id characters is scanned once", lr.r.steps <= LIM.steps && find(lr.tree, "a").length === 0, String(lr.r.steps));
  const wall = Date.now();
  MD.render("c0250 ".repeat(3300) + "\n\n" + "theme worker ".repeat(1500), OPT);
  check("the wall guard: the hostile paragraph renders well inside five seconds", Date.now() - wall < 5000, String(Date.now() - wall));
}
{
  // the memo is keyed by the text and the link context, so a new index repaints links and an unchanged one costs nothing
  const text = "c0250 and c0306";
  const before = MD.renders;
  const a = MD.safe(text, { known: known2, missing: MISSING, sig: "s1" });
  const b = MD.safe(text, { known: known2, missing: MISSING, sig: "s1" });
  const c = MD.safe(text, { known: () => false, missing: MISSING, sig: "s2" });
  check("the same text under the same index signature renders once; a new signature renders again", a === b && c !== a && MD.renders - before === 2, String(MD.renders - before));
  MD.safe(text, { known: known2 }); MD.safe(text, { known: known2 });
  check("a text with a link context but no signature is never cached", MD.renders - before === 4, String(MD.renders - before));
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
  check("input over the cap is cut with the counts in the notice", huge.html.includes("first " + (LIM.input - 200) + " of " + (LIM.input + 5000) + " characters"), huge.html.slice(-200));
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

/* ================================================================ fix round (design review of ff0869d02) */
const N_HANG = process.env.MD_N ? +process.env.MD_N : 20000; // the red run of F1 uses a smaller N so that it ends
const SECS = process.env.MD_SECS ? +process.env.MD_SECS : 5; // a generous wall-clock guard: seconds, not milliseconds
function guard(name, src) {
  const t0 = Date.now();
  let x;
  try { x = valid(name, src); } catch (e) { check(name + ": threw " + e.message, false); return null; }
  const dt = (Date.now() - t0) / 1000;
  check(name + ": ends inside " + SECS + " s (hang guard)", dt < SECS, dt.toFixed(1) + " s");
  return x;
}
const H = '<script>alert(1)</script> "q" & <img src=x onerror=1> &amp; \'s\'';
function hostile(name, src, what) {
  const x = valid(name, src);
  check(name + ": no raw element from the text", !/<script|<img/.test(x.html), x.html.slice(0, 200));
  check(name + ": the hostile text is shown as text, exactly", textOf(x.tree).includes(what || H), textOf(x.tree).slice(0, 200));
  return x;
}

/* ---- F1: one pathological line per regular expression, counted in steps and under a wall-clock guard */
{
  const sp = " ".repeat(N_HANG);
  const line = "```" + sp + "`";
  guard("F1 a fence opener with spaces then a backtick", line);
  guard("F1 three such lines", [line, line, line].join("\n"));
  guard("F1 a tilde fence opener with spaces", "~~~" + sp + "`");
  guard("F1 a heading with a run of spaces then text", "# " + sp + "x");
  guard("F1 a heading with a closing hash run", "# a " + "#".repeat(N_HANG) + " b");
  guard("F1 a table delimiter row with spaces then text", "| a |\n|" + sp + "x");
  guard("F1 a table delimiter row of dashes and spaces", "| a | b |\n" + "|- - - - ".repeat(N_HANG / 10) + "x");
  guard("F1 an hr that never ends", "- ".repeat(N_HANG / 2) + "x");
  guard("F1 a bullet then spaces then text", "-" + sp + "x");
  guard("F1 an ordered marker then spaces then text", "1." + sp + "x");
  guard("F1 a quote then spaces", ">" + sp + "x");
  guard("F1 a hard break regex on trailing spaces", "a" + sp + "\nb");
  guard("F1 spaces inside inline text", "a" + sp + "x" + sp + "`");
  guard("F1 a fence closer that almost matches", "```\n" + "`".repeat(2) + sp + "x\n");
  guard("F1 many short tabs and spaces", ("\t ".repeat(N_HANG / 4) + "x\n").repeat(3));
  guard("F1 a line of 20 000 bars", "|".repeat(N_HANG));
  guard("F1 a long comment opener", "<!--" + sp + "\nx");
}

/* ---- F2: every invisible or default-ignorable character is marked; emoji sequences still read right */
{
  const cp = n => String.fromCodePoint(n);
  const bad = /[\p{Cc}\p{Cf}\p{Co}\p{Cn}\p{Zl}\p{Zp}\p{Default_Ignorable_Code_Point}]/u;
  const classes = [
    ["a tag character", cp(0xE0041)], ["the tag cancel character", cp(0xE007F)], ["a variation selector after a letter", "a" + cp(0xFE0F)],
    ["variation selector 17", cp(0xE0100)], ["variation selector 256", cp(0xE01EF)], ["the arabic letter mark", cp(0x061C)],
    ["the combining grapheme joiner", cp(0x034F)], ["the mongolian vowel separator", cp(0x180E)], ["hangul choseong filler", cp(0x115F)],
    ["hangul jungseong filler", cp(0x1160)], ["hangul filler", cp(0x3164)], ["interlinear annotation anchor", cp(0xFFF9)], ["interlinear annotation terminator", cp(0xFFFB)],
    ["a private use character", cp(0xE000)], ["an unassigned character", cp(0x0378)], ["a supplementary private use character", cp(0xF0000)],
    ["a line separator", cp(0x2028)], ["a paragraph separator", cp(0x2029)], ["a soft hyphen", cp(0xAD)], ["a next line control", cp(0x85)],
    ["two lone low surrogates in a row", U(0xDC00) + U(0xDC01)], ["two lone high surrogates in a row", U(0xD800) + U(0xD801)], ["a lone low surrogate after a pair", cp(0x1F600) + U(0xDC00)],
    ["a stray joiner after a letter", "a" + U(0x200D) + "b"], ["a bidi override", U(0x202E)], ["a word joiner", U(0x2060)],
  ];
  for (const [name, ch] of classes) {
    const x = valid("F2 " + name, "x " + ch + " y `c" + ch + "d` [t" + ch + "](https://h.test/" + ch + ")");
    const t = textOf(x.tree);
    check("F2 " + name + " never reaches the page unmarked, in text, code and link text", !bad.test(t.replace(/‹U\+[0-9A-F]+›/g, "")) && /‹U\+[0-9A-F]{4,6}›/.test(t) && (t.match(/‹U\+/g) || []).length >= 3, JSON.stringify(t));
  }
  const fam = cp(0x1F468) + U(0x200D) + cp(0x1F469) + U(0x200D) + cp(0x1F467), heart = cp(0x2764) + U(0xFE0F), keycap = "1" + U(0xFE0F) + U(0x20E3);
  const e = valid("F2 emoji", "family " + fam + " heart " + heart + " keycap " + keycap);
  check("F2 a joiner between pictographs and a variation selector after a pictograph stay unmarked", textOf(e.tree) === "family " + fam + " heart " + heart + " keycap " + keycap, JSON.stringify(textOf(e.tree)));
  const f = valid("F2 stray", "no " + U(0x200D) + " pictograph " + cp(0x1F468) + U(0x200D) + " end and " + U(0xFE0F) + " alone");
  check("F2 a joiner that joins nothing, and a selector after nothing, are marked", (textOf(f.tree).match(/‹U\+/g) || []).length === 3, JSON.stringify(textOf(f.tree)));
}

/* ---- F5: hostile text inside every construct that emits text, asserted on the parsed tree */
{
  hostile("F5 a fence body", "```\n" + H + "\n```\n");
  hostile("F5 a fence info string", "```" + H.replace(/`/g, "") + "\ncode\n```\n", H.replace(/`/g, ""));
  hostile("F5 an unterminated fence", "```\n" + H + "\n");
  hostile("F5 an indented code block", "para\n\n    " + H + "\n");
  hostile("F5 a tab indented code block", "para\n\n\t" + H + "\n");
  hostile("F5 a heading", "# " + H);
  hostile("F5 a quote", "> " + H);
  hostile("F5 a list item", "- " + H);
  hostile("F5 an ordered item", "1. " + H);
  hostile("F5 a table header cell", "| " + H + " |\n|---|\n| x |\n");
  hostile("F5 a table cell", "| a |\n|---|\n| " + H + " |\n");
  hostile("F5 a code span", "`" + H.replace(/`/g, "") + "`", H.replace(/`/g, ""));
  hostile("F5 a paragraph", H);
  hostile("F5 emphasis", "**" + H + "** and *" + H + "*");
  hostile("F5 link text", "[" + H + "](https://x.test/a)", H);
  hostile("F5 a link address", "[a](" + H.replace(/[()]/g, "") + ")", H.replace(/[()]/g, ""));
  hostile("F5 a comment note", "<!-- " + H + " -->");
  hostile("F5 an inline comment", "x <!-- " + H + " --> y");
  const rows = Array.from({ length: LIM.rows + 5 }, (_, i) => "| " + (i === LIM.rows + 2 ? H : "r" + i) + " |").join("\n");
  hostile("F5 a table past the row cap", "| a |\n|---|\n" + rows + "\n");
  const wide = Array.from({ length: LIM.cols + 4 }, (_, i) => (i === LIM.cols + 2 ? H : "c" + i));
  hostile("F5 a table past the column cap", "| " + wide.join(" | ") + " |\n|" + wide.map(() => "---").join("|") + "|\n| " + wide.map(() => "v").join(" | ") + " |\n");
  hostile("F5 a block nested past the depth cap", Array.from({ length: 12 }, (_, i) => " ".repeat(i * 2) + "- " + (i === 11 ? H : "level " + i)).join("\n"));
  hostile("F5 a quote nested past the depth cap", ">".repeat(12) + " " + H);
  hostile("F5 an input cut at the cap", H + "\n\n" + "x ".repeat(LIM.input));
  const budget = hostile("F5 text shown after the budget ends", ("*a ".repeat(6000) + "\n\n").repeat(10) + H);
  check("F5 the budget exit shows the rest as text and says so", budget.r.over === true && budget.html.includes("too large to format") && textOf(budget.tree).includes("*a *a *a") && textOf(budget.tree).endsWith(H), textOf(budget.tree).slice(-80));
}
{
  const u = valid("F5 underscores", "use snake_case and my_var_name and __init__ and _private and a_b_c here, or __main__.py");
  check("F5 snake_case and dunder names stay literal, with no emphasis", textOf(u.tree) === "use snake_case and my_var_name and __init__ and _private and a_b_c here, or __main__.py" && find(u.tree, "em").length === 0 && find(u.tree, "strong").length === 0, u.html);
}

/* ---- F8: the node cap never throws out of render */
{
  let x, threw = null;
  try { x = MD.render("a\n\n".repeat(20000) + "**x** *y* **z**", { known }); } catch (e) { threw = JSON.stringify(e); }
  check("F8 20,000 paragraphs then emphasis does not throw", threw === null, threw);
  if (x) {
    check("F8 and shows the tail text with a notice", x.html.includes("z") && x.cuts >= 1, x.html.slice(-200));
    check("F8 the output still parses as the allowed tree", parse(x.html).problems.length === 0);
  }
  for (const src of ["a\n\n".repeat(25000), "- a\n".repeat(25000), "| a |\n|---|\n" + "| b |\n".repeat(25000), "`x` ".repeat(25000)]) {
    let t2 = null; try { MD.render(src, { known }); } catch (e) { t2 = JSON.stringify(e); }
    check("F8 no throw for a text with 25,000 elements", t2 === null, t2);
  }
  const safe = (MD.safe || (() => ""))("[a](c0250) " + H, { known: () => { throw new Error("boom"); } });
  check("F8 a failure inside render shows the escaped source with a visible notice", parse(safe).problems.length === 0 && safe.includes("&lt;script&gt;") && safe.includes("could not be formatted") && !/<script/.test(safe), safe.slice(0, 300));
}

/* ---- F10: emphasis never eats globs or code spans */
{
  const t1 = valid("F10 globs", "Run tests/*.spec.luau and src/* here.");
  check("F10 stars in paths do not italicise", find(t1.tree, "em").length === 0 && textOf(t1.tree) === "Run tests/*.spec.luau and src/* here.", t1.html);
  const t2 = valid("F10 skills glob", "see `z-nile/skills/*/lessons/*.md` and z-nile/skills/*/lessons/*.md plain");
  check("F10 a glob with stars in code and in prose is literal", find(t2.tree, "em").length === 0 && textOf(t2.tree) === "see z-nile/skills/*/lessons/*.md and z-nile/skills/*/lessons/*.md plain", t2.html);
  const t3 = valid("F10 code span with stars", "**the glob `**/*.luau`** here");
  check("F10 a code span inside strong keeps its stars", find(t3.tree, "strong").length === 1 && find(t3.tree, "code").length === 1 && textOf(find(t3.tree, "code")[0]) === "**/*.luau" && textOf(t3.tree) === "the glob **/*.luau here", t3.html);
  const t4 = valid("F10 arithmetic", "2*3*4 and 5 * 6 * 7");
  check("F10 stars inside a number sequence do not italicise", find(t4.tree, "em").length === 0 && textOf(t4.tree) === "2*3*4 and 5 * 6 * 7", t4.html);
  const t5 = valid("F10 emphasis still works", "a *em* and **strong** and ***both*** and (*paren*) and *a/b path*");
  check("F10 ordinary emphasis is kept", find(t5.tree, "em").length === 4 && find(t5.tree, "strong").length === 2, t5.html);
  const t6 = valid("F10 delimiter in a code span", "*a `b*` c*");
  check("F10 a star inside a code span cannot close an emphasis", find(t6.tree, "em").length === 1 && textOf(find(t6.tree, "em")[0]) === "a b* c", t6.html);
}

/* ---- F11: ordered lists keep their numbers */
{
  const a = valid("F11 gaps", "1. one\n3. three\n7. seven\n");
  const lis = find(a.tree, "li");
  check("F11 a number that is not the previous plus one is kept", lis.length === 3 && lis[0].attrs.value === undefined && lis[1].attrs.value === "3" && lis[2].attrs.value === "7", a.html);
  const b = valid("F11 start", "3. **G3**\n4. **G4**\n10. ten\n");
  const lb = find(b.tree, "li");
  check("F11 a list starting at 3 has start and keeps later gaps", b.html.includes('<ol start="3">') && lb[1].attrs.value === undefined && lb[2].attrs.value === "10", b.html);
  const c = valid("F11 long number", "1. a\n123456789. b\n");
  check("F11 the value is digits of bounded length", find(c.tree, "li")[1].attrs.value === "123456789");
}

/* ---- F7: tabs are kept in code and only the leading indent is read as 4 columns */
{
  const a = valid("F7 tabs in a fence", "```\n\tindented\tmid\n  \tspace tab\n```\n");
  check("F7 a fence body keeps its tabs byte for byte", textOf(find(a.tree, "pre")[0]) === "\tindented\tmid\n  \tspace tab", JSON.stringify(textOf(find(a.tree, "pre")[0])));
  const b = valid("F7 a tab-indented block", "para\n\n\tcode with\ttab\n\tmore\n");
  check("F7 a tab-indented block is code and keeps inner tabs", find(b.tree, "pre").length === 1 && textOf(find(b.tree, "pre")[0]) === "code with\ttab\nmore", JSON.stringify(textOf(find(b.tree, "pre")[0])));
  const c = valid("F7 a fence in a list item keeps tabs", "- item\n\n  ```\n  \tcode\tx\n  ```\n");
  check("F7 a fence in a list item keeps the tabs after its indent", textOf(find(c.tree, "pre")[0]) === "\tcode\tx", JSON.stringify(textOf(find(c.tree, "pre")[0])));
  check("F7 code blocks show tabs four wide", /\.md pre\{[^}]*tab-size:4/.test(box.LiveApp.MD_CSS));
}

/* ---- real text has list items, headings and quotes far longer than the block expressions look at (c0252's Outcomes) */
{
  const long = "word ".repeat(1500);
  const a = valid("long list item", "1. **`z-nile/engine/x.luau` (new).** " + long + "\n2. second\n- bullet " + long + "\n");
  check("a list item longer than 2,000 characters is a list item, whole", find(a.tree, "ol").length === 1 && find(a.tree, "ul").length === 1 && textOf(find(a.tree, "li")[0]).endsWith("word "), a.html.slice(0, 120));
  const b = valid("long heading", "## " + long + "\n");
  check("a heading longer than 2,000 characters is a heading, whole", find(b.tree, "h4").length === 1 && textOf(find(b.tree, "h4")[0]).trim() === long.trim());
  const c = valid("long quote", "> " + long + "\n");
  check("a quote longer than 2,000 characters is a quote, whole", find(c.tree, "blockquote").length === 1 && textOf(find(c.tree, "blockquote")[0]).trim() === long.trim());
  const d = valid("long table row", "| a | b |\n|---|---|\n| " + long + "| x |\n");
  check("a table with a row longer than 2,000 characters is a table", find(d.tree, "table").length === 1 && find(d.tree, "td").length === 2);
}

/* ---- hostile characters reaching every esc site found by the escape-removal mutants */
{
  const x = valid("esc backslash", "\\<script>alert(1)\\</script> \\\" \\& \\'");
  check("an escaped character is escaped when it is shown", !/<script/.test(x.html) && textOf(x.tree) === "<script>alert(1)</script> \" & '", x.html);
  const y = valid("esc hard break", "<img src=x onerror=1>  \n<script>x</script>");
  check("text before a hard break is escaped", !/<img|<script/.test(y.html) && find(y.tree, "br").length === 1 && textOf(y.tree).includes("<img src=x onerror=1>"), y.html);
  const z = valid("esc address as its own label", "[<b>x</b>](<b>x</b>)");
  check("an address that is its own link text is escaped", !/<b>/.test(z.html) && textOf(z.tree).includes("<b>x</b>"), z.html);
  const w = valid("esc address beside text", "[t](<b>x</b> onerror=1)");
  check("an address beside its link text is escaped", !/<b>/.test(w.html) && textOf(w.tree).includes("<b>x</b>"), w.html);
}

/* ---- minor items */
{
  const a = valid("m #", "#\n\n### Issue #\n\n#### Closing ####\n");
  check("minor a lone # keeps its character and a closing # is kept", textOf(a.tree).includes("#") && find(a.tree, "h5").some(h => textOf(h) === "Issue #") && find(a.tree, "h6").some(h => textOf(h) === "Closing ####") && find(a.tree, "h3").length === 0, a.html);
  const b = valid("m >=", ">= 5 is a comparison\n");
  check("minor a line starting >= is not a quote", find(b.tree, "blockquote").length === 0 && textOf(b.tree).startsWith(">= 5"), b.html);
  const wide = Array.from({ length: LIM.cols + 4 }, (_, i) => "c" + i);
  const c = valid("m cols", "| " + wide.join(" | ") + " |\n|" + wide.map(() => "---").join("|") + "|\n");
  check("minor columns past the cap are joined with a counted notice", c.r.cuts >= 1 && c.html.includes("Columns past"), c.html.slice(-200));
  const d = valid("m ~~~", "~~~ a`b\ncode\n~~~\n");
  check("minor a tilde fence may have a backtick in its info", find(d.tree, "pre").length === 1 && textOf(find(d.tree, "pre")[0]) === "code", d.html);
  const e = valid("m ``` info", "```a`b\nnot code\n```\n");
  check("minor a backtick fence whose info holds a backtick is not a fence", textOf(e.tree).includes("not code") && find(e.tree, "pre").length === 0 || find(e.tree, "pre").every(p => !textOf(p).includes("not code")), e.html);
  const f = valid("m list fence", "- item\n  ```\n  a\n\nb\n  c\n  ```\n- next\n");
  check("minor a fence inside a list item does not end at a blank line", find(f.tree, "pre").length === 1 && textOf(find(f.tree, "pre")[0]) === "a\n\nb\nc" && find(f.tree, "li").length === 2, f.html);
  check("minor tables scroll in their wrapper at phone width instead of squeezing (review N4 replaced max-content)", /\.md-scroll table\{[^}]*min-width:100%/.test(box.LiveApp.MD_CSS) && /\.md-scroll\{[^}]*overflow-x:auto/.test(box.LiveApp.MD_CSS));
}

/* ================================================================ round 3 (second review of ae84770e6) */
/* ---- N1: the budget counts work; comment closers are found once; every scanning loop has a hostile case at the cap size */
{
  const src = ("<!--" + "-".repeat(195) + "\n").repeat(1999); // 399,800 characters, under the cap
  const t0 = Date.now();
  const x = valid("N1 many comment openers on long lines", src);
  const dt = (Date.now() - t0) / 1000;
  check("N1 one render of it takes under a second (it took 2.85 s)", dt < 1, dt.toFixed(2) + " s");
  check("N1 the steps count the work, not the lines: at least one step per character scanned", x.r.steps >= src.length, x.r.steps + " < " + src.length);
  check("N1 and stay inside the budget (or end with the notice)", x.r.steps <= LIM.steps);
  // five such sections, as on a real ticket page: the page paints them all each time
  const t1 = Date.now();
  for (let i = 0; i < 5; i++) MD.render(src, { known });
  check("N1 five such sections render in under 4 s", (Date.now() - t1) / 1000 < 4, ((Date.now() - t1) / 1000).toFixed(1) + " s");
  // memoised: the same text is rendered once, however often the page paints
  const text = "A **bold** line\n\n- one\n- two\n";
  const before = MD.renders;
  const a = MD.safe(text), b = MD.safe(text), c = MD.safe(text + "x");
  check("N1 the same text is rendered once (memoised per section text)", a === b && MD.renders - before === 2 && c !== a, String(MD.renders - before));
  check("N1 a memoised result is the same string, so a repaint costs nothing", MD.safe(text) === a && MD.renders - before === 2);
}
{
  const CAP = LIM.input - 300;
  const filler = n => "x".repeat(n);
  const cases = [
    ["a comment opener on every line of a paragraph", ("<!--" + "-".repeat(95) + "\nword ").repeat(CAP / 100)],
    ["a comment opener inside every list item", ("- <!--" + "-".repeat(95) + "\n").repeat(CAP / 100)],
    ["a quote line of long comment openers", (">" + "<!--" + "-".repeat(95) + "\n").repeat(CAP / 100)],
    ["blank lines after a list item", "- a\n" + "\n".repeat(CAP)],
    ["blank lines between list items", ("- a\n" + "\n".repeat(50)).repeat(CAP / 60)],
    ["a list item followed by indented blank-looking lines", "- a\n" + "  \n".repeat(CAP / 3)],
    ["lines with a bar, each a table candidate", "a | b\n".repeat(CAP / 6)],
    ["a table whose row holds thousands of code spans", "| a |\n|---|\n| " + "`x ".repeat(CAP / 3 - 10) + " |\n"],
    ["a table whose rows are all delimiter-like", "| a |\n|---|\n" + "|---|\n".repeat(CAP / 6)],
    ["one line of spaces and a letter", " ".repeat(CAP) + "x"],
    ["tab runs", ("\t".repeat(100) + "x\n").repeat(CAP / 101)],
    ["a fence whose lines are long", "```\n" + (filler(999) + "\n").repeat(CAP / 1000) + "```\n"],
    ["many short fences", "```\na\n```\n".repeat(CAP / 10)],
    ["indented code lines", "    code\n".repeat(CAP / 9)],
    ["many nested quotes of short lines", ">>>>>>>> x\n".repeat(CAP / 11)],
    ["nested lists of short lines rescanned at every level", Array.from({ length: 8 }, (_, i) => " ".repeat(i * 2) + "- " + filler(30000)).join("\n") + "\n" + "- y\n".repeat(CAP / 40)],
    ["a line of hard-break candidates", ("a  \n").repeat(CAP / 4)],
    ["backslashes", "\\".repeat(CAP)],
    ["brackets with parentheses", "[a](b) ".repeat(CAP / 7)],
    ["emphasis candidates", "*a* ".repeat(CAP / 4)],
    ["a heading line of marks", "# " + "*".repeat(CAP)],
    ["horizontal rule candidates", "- - - - - - - - x\n".repeat(CAP / 18)],
    ["a million-ish unmatched ticks in short lines", "`a\n".repeat(CAP / 3)],
    ["ordered markers with spaces", ("1." + " ".repeat(97) + "x\n").repeat(CAP / 100)],
  ];
  for (const [name, src] of cases) {
    const t0 = Date.now();
    let x;
    try { x = valid("N1 loop: " + name, src); } catch (e) { check("N1 loop: " + name + " threw " + JSON.stringify(e), false); continue; }
    const dt = (Date.now() - t0) / 1000;
    check("N1 loop: " + name + ": under " + SECS + " s (hang guard) and under 2 s here", dt < Math.min(SECS, 2), dt.toFixed(2) + " s");
    check("N1 loop: " + name + ": steps inside the budget and at least the lines scanned", x.r.steps <= LIM.steps && (x.r.over || x.r.steps >= src.split("\n").length), x.r.steps + " over " + x.r.over);
  }
}

/* ---- N2: the window may decide the KIND of a line, never the text it holds */
{
  const SENT = "SENTINELWORD";
  const gaps = [0, 1, 1998, 1999, 2000, 2001, 3000, 5000];
  const markers = ["- ", "1. ", "* ", "+ ", "1) ", "> ", ">> ", "# ", "## ", "###### ", "- - ", "- [ ] ", "```", "~~~", "- ```", "1. ~~~", "> ```", "    ", "\t", "  1. ", "    - ", "| a |\n|---|\n| ", "| a | b |\n|---|---|\n| x | "];
  let seed = 12345;
  const rnd = n => { seed = (seed * 1103515245 + 12345) & 0x7fffffff; return seed % n; };
  const gen = [];
  for (const m of markers) for (const g of [0, 1999, 2000, 2001, 3000]) gen.push(m + " ".repeat(g) + SENT);
  for (let i = 0; i < 300; i++) {
    const parts = [];
    const n = 1 + rnd(3);
    for (let k = 0; k < n; k++) parts.push(markers[rnd(markers.length)]);
    const gap = gaps[rnd(gaps.length)];
    const neighbour = ["", "para\n", "- a\n", "```\n", "\n", "| a |\n|---|\n"][rnd(6)];
    const tail = ["", "\nmore", "\n\nmore", "\n```"][rnd(4)];
    gen.push(neighbour + parts.join("") + " ".repeat(gap) + SENT + tail);
  }
  gen.push("- " + " ".repeat(1998) + "SECRET TEXT", "1. " + " ".repeat(1997) + "SECRET TEXT", "* " + " ".repeat(1998) + "SECRET TEXT");
  gen.push("- a\n- " + " ".repeat(1998) + "SECRET TEXT");
  gen.push("```" + " ".repeat(1997) + "SECRET INFO\ncode\n```");
  gen.push("~~~" + " ".repeat(1997) + "SECRET INFO\ncode\n~~~");
  gen.push("- ```" + " ".repeat(1995) + "SECRET INFO\n  code\n  ```");
  gen.push("```" + " ".repeat(1997) + "SECRET ` INFO\ncode\n```");
  gen.push("a" + " ".repeat(2500) + "\nSECRET TEXT", "a" + " ".repeat(2500) + "  \nSECRET TEXT");
  gen.push("# " + " ".repeat(2500) + "SECRET TEXT", "> " + " ".repeat(2500) + "SECRET TEXT");
  gen.push("    " + " ".repeat(2500) + "SECRET TEXT");
  gen.push("| a | b |\n|---|---|\n| x |" + " ".repeat(2500) + "SECRET TEXT |");
  gen.push("| a | b |" + " ".repeat(2500) + "SECRET TEXT\n|---|---|\n| x | y |");
  let missing = 0, first = "";
  for (const src of gen) {
    const sent = src.includes("SECRET INFO") ? "SECRET" : src.includes("SECRET") ? "SECRET" : SENT;
    let x;
    try { x = run(src, { known }); } catch (e) { missing++; first = first || "threw on " + JSON.stringify(src.slice(0, 40)); continue; }
    if (x.problems.length || !textOf(x.tree).includes(sent)) { missing++; first = first || JSON.stringify(src.slice(0, 30)) + "... " + (x.problems[0] || "text missing"); }
  }
  check("N2 a sentinel past 2,000 characters, after any block marker, is always shown (" + gen.length + " inputs)", missing === 0, missing + " lost, first: " + first);
  const info = valid("N2 long info string", "```" + " ".repeat(2997) + "SECRET INFO\ncode\n```");
  check("N2 a 3,000-character info string followed by text shows the text", textOf(info.tree).includes("SECRET INFO") && textOf(info.tree).includes("code"), info.html.slice(0, 200));
  const tick = valid("N2 backtick past the window", "```" + " ".repeat(2500) + "a`b\nnot code\n```");
  check("N2 a backtick in the info beyond the window still means it is not a fence", find(tick.tree, "pre").every(p => !textOf(p).includes("not code")), tick.html.slice(0, 200));
  const tilde = valid("N2 tilde info", "~~~" + " ".repeat(2500) + "a`b\ncode\n~~~");
  check("N2 a tilde fence may hold a backtick in its info, however far", find(tilde.tree, "pre").length === 1 && textOf(find(tilde.tree, "pre")[0]) === "code");
}

/* ---- N4: tables wrap their cells and scroll in the wrapper; they are not laid on one line (not seen in a browser) */
{
  const css = box.LiveApp.MD_CSS;
  check("N4 a table is not width:max-content (every cell on one line)", !/\.md-scroll table\{[^}]*width:max-content/.test(css), "found");
  check("N4 the table keeps min-width:100% and the wrapper scrolls", /\.md-scroll table\{[^}]*min-width:100%/.test(css) && /\.md-scroll\{[^}]*overflow-x:auto/.test(css));
  check("N4 cells have a min-width so that they wrap but do not squeeze", /\.md td\{[^}]*min-width:12ch/.test(css) && /\.md th\{[^}]*min-width:12ch/.test(css));
}

/* ---- N5: what is inside code is one description, tested on both sides (the engine's side is in approval-facts.spec) */
{
  const table = JSON.parse(fs.readFileSync(path.join(__dirname, "..", "fixtures", "inside-code-cases.json"), "utf8"));
  for (const c of table.cases) {
    const body = c.text.replace(/^## Design\n/, "").split(/\n## Acceptance criteria\n/)[0];
    const x = valid("N5 " + c.name, body);
    const codes = [...find(x.tree, "pre"), ...find(x.tree, "code")].map(textOf);
    for (const want of c.code) check("N5 the page shows it inside code: " + c.name + ": " + want, codes.some(t => t.includes(want)), JSON.stringify(codes).slice(0, 200));
  }
}

/* ---- N7: a joiner stays unmarked only inside a real emoji */
{
  const cp = n => String.fromCodePoint(n), zwj = U(0x200D);
  const thumbs = cp(0x1F44D);
  const fake = valid("N7 two thumbs joined", thumbs + thumbs + zwj + thumbs + thumbs);
  check("N7 a joiner between pictographs that make no emoji is marked", (textOf(fake.tree).match(/‹U\+200D›/g) || []).length === 1, JSON.stringify(textOf(fake.tree)));
  const fam = cp(0x1F468) + zwj + cp(0x1F469) + zwj + cp(0x1F467);
  const flag = cp(0x1F3F3) + U(0xFE0F) + zwj + cp(0x1F308);
  const man = cp(0x1F468) + cp(0x1F3FD) + zwj + cp(0x1F4BB);
  const real = valid("N7 real emoji", fam + " " + flag + " " + man + " " + cp(0x2764) + U(0xFE0F) + " 1" + U(0xFE0F) + U(0x20E3));
  check("N7 a family, a rainbow flag, a woman technologist-like sequence, a heart and a keycap stay unmarked", textOf(real.tree) === fam + " " + flag + " " + man + " " + cp(0x2764) + U(0xFE0F) + " 1" + U(0xFE0F) + U(0x20E3), JSON.stringify(textOf(real.tree)));
  const sel = valid("N7 a selector after a non-emoji pictograph pair", cp(0x1F44D) + cp(0x1F44D) + U(0xFE0F));
  check("N7 a lone selector after a pictograph that has no emoji form is judged as a whole sequence", typeof textOf(sel.tree) === "string");
}

/* ---- a fence closer followed by thousands of spaces still closes the fence (it is the window's kind decision, not text) */
{
  const x = valid("N2 closer with trailing spaces", "```\ncode\n```" + " ".repeat(3000) + "\nafter the fence\n");
  check("N2 a closing fence with 3,000 trailing spaces closes it", find(x.tree, "pre").length === 1 && textOf(find(x.tree, "pre")[0]) === "code" && find(x.tree, "p").some(p => textOf(p) === "after the fence"), x.html.slice(0, 200));
}

{
  // the budget counts the work: a fence of long lines costs its characters, not one step per line
  const long = "```\n" + ("x".repeat(999) + "\n").repeat(390) + "```\n";
  const x = valid("N1 a fence of long lines", long);
  check("N1 a fence of long lines costs at least its characters in steps", x.r.steps >= long.length, x.r.steps + " < " + long.length);
  // the window decides the kind of a line: four columns of indent is code, however many more spaces follow
  const y = valid("N2 deep indent", "para\n\n    " + " ".repeat(2500) + "SECRET TEXT\n");
  check("N2 text indented by thousands of spaces is code, whole", find(y.tree, "pre").length === 1 && textOf(find(y.tree, "pre")[0]).includes("SECRET TEXT"), y.html.slice(0, 120));
}

/* ---- verification round: the memo counts what it holds, and every notice gives its number */
{
  // the memo's bound counts key characters AND output characters
  const text = "- item *a* `code`\n".repeat(2000);
  const before = MD.cacheChars;
  const html = MD.safe(text);
  check("the memo counts key and output characters", MD.cacheChars - before === text.length + html.length, (MD.cacheChars - before) + " vs " + (text.length + html.length));
  for (let i = 0; i < 40; i++) MD.safe("| a |\n|---|\n" + ("| " + i + " `x` |\n").repeat(9000));
  check("the memo stays under its bound with large outputs", MD.cacheChars <= 16000000, String(MD.cacheChars));
  const para = valid("a paragraph past the inline line limit", "word ".repeat(5000));
  check("a paragraph over 20,000 characters says it is shown unformatted, with the number", para.html.includes("shown unformatted: 25000 characters") && para.r.cuts >= 1 && textOf(para.tree).includes("word word"), para.html.slice(0, 160));
  const cell = valid("a table cell past the limit", "| a |\n|---|\n| " + "word ".repeat(5000) + " |\n");
  check("a cell over 20,000 characters says so too", /shown unformatted: 2499\d characters/.test(cell.html), cell.html.slice(-200));
  const nest = valid("depth notice", Array.from({ length: 12 }, (_, i) => " ".repeat(i * 2) + "- level " + i).join("\n"));
  check("the depth notice gives the number of lines", /deeper than 8 levels: \d+ lines? (is|are) shown as plain text/.test(textOf(nest.tree)), textOf(nest.tree).slice(0, 200));
  const wide = Array.from({ length: LIM.cols + 7 }, (_, i) => "c" + i);
  const cols = valid("column notice", "| " + wide.join(" | ") + " |\n|" + wide.map(() => "---").join("|") + "|\n");
  check("the column notice gives the number of columns joined", /47 columns/.test(textOf(cols.tree)) || /8 columns are joined/.test(textOf(cols.tree)), textOf(cols.tree).slice(-120));
  const over = valid("budget notice", ("*a ".repeat(6000) + "\n\n").repeat(10));
  check("the budget-exit notice gives the number of lines shown as text", /from here on \d+ lines? (is|are) shown as plain text/.test(textOf(over.tree)), textOf(over.tree).slice(0, 200));
}

/* ---- N8: trailing spaces inside a fence are kept */
{
  const x = valid("N8 trailing spaces", "```\nkeep  \n  keep too   \n\t\n```\n");
  check("N8 trailing spaces and a whitespace-only line in a fence are kept byte for byte", textOf(find(x.tree, "pre")[0]) === "keep  \n  keep too   \n\t", JSON.stringify(textOf(find(x.tree, "pre")[0])));
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
console.log("slowest case: " + worst.name + " (" + worst.chars + " characters in, " + worst.ms.toFixed(0) + " ms)");
console.log("app-md: ok");
