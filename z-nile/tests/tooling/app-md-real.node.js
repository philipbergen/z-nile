"use strict";
// f0437 step 6, slice 1 (F1, F9, F12): the whole chain on real text. node app-md-real.node.js <app folder> <served.json> [--oracle]
// <served.json> is what the Go reader served for the engine's facts: the frozen copy of three real tickets in the gate
// (tests/fixtures/walk-real.served.json), or the real waiting tickets in the one-time proof (tests/chain/walk-chain.sh).
// Every ticket's idea, design parts, Acceptance criteria and Test plan go through the page's renderer, and
//  - the output must parse as the allowed tree (a strict parser), with no exception and no budget exit;
//  - the TEXT CONTENT of the output (tags removed, entities decoded) must equal the source word for word in order, modulo
//    markdown syntax (list markers, backslash escapes, the labels the renderer adds); characters are counted from the output;
//  - every fenced code block of the source must come out as a code block: byte for byte (tabs and indentation included) when
//    the fence is at the left margin, and after taking off the fence's own indent when it sits in a list item.
// With --oracle (the one-time proof) the text the page receives is also compared with the section on disk (git show origin/main).
const fs = require("fs");
const path = require("path");
const vm = require("vm");
const { execFileSync } = require("child_process");

const argv = process.argv.slice(2);
const [dir, served] = argv;
const flag = argv.includes("--oracle") ? "--oracle" : "";
const optionOf = name => { const a = argv.find(x => x.startsWith("--" + name + "=")); return a ? a.slice(name.length + 3) : ""; };
const code = fs.readFileSync(path.join(dir, "live.js"), "utf8");
const page = fs.readFileSync(path.join(dir, "index.html"), "utf8");
const esc = eval(/const esc = (s => String\(s == null[^\n]*);\n/.exec(page)[1]);
const els = {};
const box = {
  console: { error() {} }, location: { protocol: "file:", hash: "" },
  document: { body: { appendChild(e) { if (e.id) els[e.id] = e; } }, getElementById: id => els[id] || null, createElement: () => ({ dataset: {}, className: "", innerHTML: "", setAttribute() {} }), addEventListener() {} },
  addEventListener() {}, setInterval() {}, setTimeout() {},
};
vm.createContext(box); box.globalThis = box; vm.runInContext(code, box);
const R = box.LiveApp.make({ esc, mono: s => esc(s), ic: () => "", WSTATE: {}, fmtDur: () => "", ptTime: () => "", pl: (n, w) => n + " " + w + (n === 1 ? "" : "s"), now: () => 0 });
const MD = R.md;

const ALLOWED = new Set(["p", "h3", "h4", "h5", "h6", "ul", "ol", "li", "strong", "em", "code", "pre", "table", "thead", "tbody", "tr", "th", "td", "blockquote", "hr", "a", "br", "div", "span"]);
function problems(html) {
  const out = [];
  for (const m of html.matchAll(/<(\/?)([a-zA-Z0-9]+)([^>]*)>/g)) {
    if (!ALLOWED.has(m[2])) out.push("element " + m[2]);
    for (const a of m[3].matchAll(/\s([a-zA-Z-]+)=/g)) if (!["class", "href", "start", "value", "title"].includes(a[1])) out.push("attribute " + a[1]);
    for (const a of m[3].matchAll(/\stitle="([^"]*)"/g)) if (m[2] !== "span" || !/class="md-miss"/.test(m[3]) || !/^not in the units index made at [0-9: ]* PT$/.test(a[1])) out.push("title " + a[1]);
    for (const h of m[3].matchAll(/href="([^"]*)"/g)) if (!/^#\/(?:ticket|raft|approvals|tributary)\//.test(h[1])) out.push("href " + h[1]);
  }
  const stripped = html.replace(/<\/?[a-z0-9]+(?:\s[^<>]*)?>/g, "");
  if (/[<>]/.test(stripped)) out.push("a raw < or > in text");
  return out;
}
const decode = s => s.replace(/&(amp|lt|gt|quot|#39);/g, (_, e) => ({ amp: "&", lt: "<", gt: ">", quot: '"', "#39": "'" }[e]));
const decodeText = html => decode(html.replace(/<br>/g, "\n").replace(/<\/(p|li|h[3-6]|tr|pre|blockquote|div)>/g, "\n").replace(/<\/(td|th)>/g, " ").replace(/<[^>]*>/g, ""));
// for the comparison of words every tag is a boundary, as every markdown mark is in the source (`a`b: two words)
const spacedText = html => decode(html.replace(/<[^>]*>/g, " "));
const LABELS = ["A note hidden in the document:", "No closing fence: the rest of the text is shown as code."];
const WORD = /[\p{L}\p{N}_]+/gu;
const words = s => s.match(WORD) || [];
// the source without the markup that is not text: list markers outside fences (the number or bullet is not rendered as text)
function sourceWords(src) {
  const out = []; let fence = null;
  for (const line of src.replace(/\r\n?/g, "\n").split("\n")) {
    const m = /^( {0,})(`{3,}|~{3,})/.exec(line);
    if (fence) { if (m && m[2][0] === fence[0] && m[2].length >= fence.length && /^\s*$/.test(line.slice(m[0].length))) fence = null; out.push(...words(line)); continue; }
    if (m) { fence = m[2]; out.push(...words(line)); continue; }
    out.push(...words(line.replace(/^ *(?:[-*+]|\d{1,9}[.)])(?= )/, "")));
  }
  return out;
}
function fences(src) {
  const out = []; const lines = src.replace(/\r\n?/g, "\n").split("\n");
  for (let i = 0; i < lines.length; i++) {
    const m = /^( *)(`{3,}|~{3,})(.*)$/.exec(lines[i]);
    if (!m || (m[2][0] === "`" && m[3].includes("`"))) continue;
    const body = []; let j = i + 1, closed = false;
    for (; j < lines.length; j++) { const c = /^ *(`{3,}|~{3,}) *$/.exec(lines[j]); if (c && c[1][0] === m[2][0] && c[1].length >= m[2].length) { closed = true; break; } body.push(lines[j]); }
    const strip = l => (l.startsWith(m[1]) ? l.slice(m[1].length) : l.trimStart());
    out.push({ indent: m[1].length, closed, body: m[1].length ? body.map(strip).join("\n") : body.join("\n") });
    i = j;
  }
  return out;
}
// review N8: the strongest form. Every non-space character the page shows is a subsequence of the source, in order; only these
// source characters may be missing (markdown marks): * ` | # > - + \\ ~ [ ] _ :  (and the number of an ordered item, which the browser
// makes). Nothing else may be lost, and nothing may be added.
const DROP = new Set(["*", "`", "|", "#", ">", "-", "+", "\\", "~", "[", "]", "_", ":"]);
function sourceChars(src) {
  const out = []; let fence = null;
  for (let line of MD.visible(src.replace(/\r\n?/g, "\n")).split("\n")) {
    const m = /^( *)(`{3,}|~{3,})/.exec(line);
    if (fence) { if (m && m[2][0] === fence[0] && m[2].length >= fence.length && /^\s*$/.test(line.slice(m[0].length))) fence = null; }
    else if (m) fence = m[2];
    else line = line.replace(/^ *(?:[-*+]|\d{1,9}[.)])(?= )/, "");
    for (const ch of line) if (!/\s/.test(ch)) out.push(ch);
  }
  return out;
}
function subsequenceProblem(src, shown) {
  const a = sourceChars(src), b = [...shown].filter(ch => !/\s/.test(ch));
  let i = 0;
  for (let j = 0; j < b.length; j++) {
    while (i < a.length && a[i] !== b[j]) { if (!DROP.has(a[i])) return "a source character was lost near " + JSON.stringify(a.slice(Math.max(0, i - 8), i + 8).join("")) + " (page shows " + JSON.stringify(b.slice(Math.max(0, j - 8), j + 8).join("")) + ")"; i++; }
    if (i >= a.length) return "the page shows a character that is not in the source, near " + JSON.stringify(b.slice(Math.max(0, j - 8), j + 8).join(""));
    i++;
  }
  for (; i < a.length; i++) if (!DROP.has(a[i])) return "the source ends with text the page does not show: " + JSON.stringify(a.slice(i, i + 12).join(""));
  return null;
}
// the numbers of ordered items as a browser numbers them (start, then value), against the numbers the source wrote
function renderedNumbers(html) {
  const out = [];
  for (const ol of html.matchAll(/<ol(?: start="(\d+)")?>/g)) { void ol; }
  const re = /<(\/?)(ol|ul|li)((?: start="\d+")?(?: value="\d+")?)>/g; const stack = []; let m;
  while ((m = re.exec(html))) {
    if (m[2] === "ol" || m[2] === "ul") { if (m[1]) stack.pop(); else stack.push({ ordered: m[2] === "ol", n: m[3] ? +/start="(\d+)"/.exec(m[3])[1] - 1 : 0 }); }
    else if (!m[1] && stack.length && stack[stack.length - 1].ordered) { const top = stack[stack.length - 1]; const v = /value="(\d+)"/.exec(m[3]); top.n = v ? +v[1] : top.n + 1; out.push(top.n); }
  }
  return out;
}
function sourceNumbers(src) {
  const out = []; let fence = null;
  for (const line of src.replace(/\r\n?/g, "\n").split("\n")) {
    const m = /^( *)(`{3,}|~{3,})/.exec(line);
    if (fence) { if (m && m[2][0] === fence[0] && m[2].length >= fence.length && /^\s*$/.test(line.slice(m[0].length))) fence = null; continue; }
    if (m) { fence = m[2]; continue; }
    const n = /^ {0,3}(\d{1,9})[.)](?: |$)/.exec(line.replace(/^( *)/, s => s.slice(0, 3)));
    void n;
    const k = /^ *(\d{1,9})[.)] /.exec(line);
    if (k && line.length - line.trimStart().length < 40) out.push(+k[1]);
  }
  return out;
}
// every pre code block is a run of consecutive source lines with one consistent stripped prefix
function blockIsARun(srcLines, text) {
  const L = text.split("\n");
  for (let a = 0; a + L.length <= srcLines.length; a++) {
    const first = srcLines[a];
    if (L[0] !== "" && !first.endsWith(L[0])) continue;
    const p = L[0] === "" ? first.slice(0, first.length - 0) : first.slice(0, first.length - L[0].length);
    if (L[0] === "" && /\S/.test(p)) continue;
    let ok = true;
    for (let k = 0; k < L.length && ok; k++) { const s = srcLines[a + k]; ok = L[k] === "" ? !/\S/.test(s) && (s === "" || s.startsWith(p) || p.startsWith(s)) : s === p + L[k]; }
    if (ok) return true;
  }
  return false;
}
const preTexts = html => [...html.matchAll(/<pre><code>([\s\S]*?)<\/code><\/pre>/g)].map(m => decode(m[1]));

const body = JSON.parse(fs.readFileSync(served, "utf8"));
if (body.state !== "ok") { console.error("the served facts are " + body.state + ": " + body.why); process.exit(1); }
/* slice 2: with --units and --themes (the served files) the renderer gets the index, as the page gives it */
let CTX = null, RENDER_OPT;
if (optionOf("units")) {
  const units = JSON.parse(fs.readFileSync(optionOf("units"), "utf8")), themes = JSON.parse(fs.readFileSync(optionOf("themes"), "utf8"));
  if (units.state !== "ok" || themes.state !== "ok") { console.error("the served index or themes are not ok: " + units.state + " " + themes.state); process.exit(1); }
  CTX = R.links.ctx({ units: { resp: units }, approvals: { state: "ok", facts: body.facts }, themes, now: (units.facts.at + 60) * 1000 });
  RENDER_OPT = CTX.opt;
}
const LINK = { sections: 0, idMentions: 0, idLinks: 0, idMissing: 0, idPlainWhere: [], tribLinks: 0, tribPlainByRule: 0, oracleIdMentions: 0, oracleTribLinks: 0, oracleTribPlain: 0, unknownIds: {}, byState: {}, disagree: [] };
const ID_G = /(?<![\p{L}\p{N}_])([cfdR]\d{4})(?![\p{L}\p{N}_])/gu;
/* the independent oracle: no code of the page's link rules, only the stated rule as regular expressions over the source. Fenced blocks are
   taken out; a white-space-delimited token holding an @ or starting (after opening punctuation) with scheme:// or mailto:, http:, file: ... is
   no place for an id; an id bounded by anything but a letter, digit or underscore counts; inside inline code only an id the index holds counts
   (an unknown one stays plain code); a tributary name counts after the word tributary or theme (a colon or quotes allowed) or when hyphenated,
   never in code. */
function oracleOf(text, names) {
  const lines = MD.visible(text.replace(/\r\n?/g, "\n")).split("\n"), kept = []; let fence = null;
  for (const line of lines) {
    const m = /^ {0,3}(`{3,}|~{3,})/.exec(line);
    if (fence) { if (m && m[1][0] === fence[0] && m[1].length >= fence.length && /^\s*$/.test(line.slice(m[0].length))) fence = null; continue; }
    if (m) { fence = m[1]; continue; }
    kept.push(line);
  }
  const noUrl = t => t.replace(/\S+/g, tok => (/@/.test(tok) || /^[(\[<"'`*_~]*(?:[A-Za-z][A-Za-z0-9+.-]*:\/\/|(?:https?|mailto|file|ftp|sftp|ssh|git|data|javascript|tel|wss?):)/i.test(tok) ? " " : tok));
  let prose = kept.join("\n"), inCode = 0;
  prose = prose.replace(/(`+)([\s\S]*?[^`])\1(?!`)/g, (_, _t, inner) => { for (const m of noUrl(inner).matchAll(ID_G)) inCode++; return " "; });
  prose = prose.replace(/\[([^\]\n]*)\]\(([^()\n]*)\)/g, (_, label, target) => " " + (/^[cfdR]\d{4}$/.test(label.trim()) && label.trim() !== target.trim().replace(/^#\/(?:ticket|raft|approvals)\//, "") ? "" : "") + target + " "); // a bracket link: its label is no id; its target is read as one
  prose = noUrl(prose);
  const ids = [...prose.matchAll(ID_G)].map(m => m[1]);
  let trLinks = 0, trPlain = 0;
  for (const m of prose.matchAll(/(?<![\p{L}\p{N}_-])([a-z0-9][a-z0-9-]*)(?![\p{L}\p{N}_-])/gu)) {
    if (!names.has(m[1])) continue;
    const before = prose.slice(Math.max(0, m.index - 24), m.index);
    if (m[1].includes("-") || /(?:^|[^A-Za-z0-9_-])(?:tributary|theme)[ ]*:?[ ]*["']?$/i.test(before)) trLinks++; else trPlain++;
  }
  return { ids: ids.length + inCode, trLinks, trPlain };
}
const tickets = [];
for (const th of body.facts.themes) for (const r of th.rafts) for (const tk of r.tickets) tickets.push(tk);

const stat = { tickets: 0, sections: 0, charsIn: 0, charsOfRenderedText: 0, wordsIn: 0, wordsOut: 0, cuts: 0, cutWhere: [], notesShown: 0, templateCountedByEngine: 0, elements: {}, maxSteps: 0, maxStepsIn: "", over: 0, bad: [], mismatch: [], codeBlocks: { sourceFences: 0, compared: 0, byteExact: 0, exactAfterIndent: 0, notFound: [] }, pageNotices: {} };
const sectionsOf = tk => {
  const s = [["Problem", tk.idea.problem], ["Solution", tk.idea.solution]];
  for (const d of tk.design || []) s.push(["Design/" + d.heading, d.text]);
  for (const d of tk.extra || []) s.push([d.heading, d.text]);
  return s;
};
for (const tk of tickets) {
  stat.tickets++; stat.templateCountedByEngine += tk.comments || 0;
  for (const [name, text] of sectionsOf(tk)) {
    stat.sections++; stat.charsIn += text.length;
    let r;
    const t0 = process.hrtime.bigint();
    try { r = MD.render(text, RENDER_OPT); } catch (e) { stat.bad.push(tk.id + " " + name + ": exception " + JSON.stringify(e)); continue; }
    const ms = Number(process.hrtime.bigint() - t0) / 1e6;
    if (ms > (stat.slowestMs || 0)) { stat.slowestMs = Math.round(ms * 10) / 10; stat.slowestIn = tk.id + " " + name + " (" + text.length + " characters)"; }
    for (const p of problems(r.html)) stat.bad.push(tk.id + " " + name + ": " + p);
    let shown = decodeText(r.html), spaced = spacedText(r.html);
    for (const l of LABELS) { shown = shown.split(l).join(""); spaced = spaced.split(l).join(" "); }
    stat.charsOfRenderedText += shown.length;
    stat.cuts += r.cuts; if (r.cuts) stat.cutWhere.push(tk.id + " " + name);
    stat.notesShown += r.notes; if (r.over) stat.over++;
    for (const [k, v] of Object.entries(r.elements)) stat.elements[k] = (stat.elements[k] || 0) + v;
    if (r.steps > stat.maxSteps) { stat.maxSteps = r.steps; stat.maxStepsIn = tk.id + " " + name + " (" + text.length + " characters)"; }
    if (CTX) {
      LINK.sections++;
      const idLinks = [...r.html.matchAll(/<a href="#\/(?:ticket|raft|approvals)\/([A-Za-z0-9%_-]+)">/g)].map(m => decodeURIComponent(m[1]));
      const miss = [...r.html.matchAll(/<span class="md-miss"[^>]*>([^<]*)<\/span>/g)].map(m => decode(m[1]));
      const trib = [...r.html.matchAll(/<a href="#\/tributary\//g)].length;
      for (const m of r.html.matchAll(/<a href="#\/tributary\/[^"]*">([^<]*)<\/a>/g)) LINK.tribSentences = (LINK.tribSentences || []).concat(tk.id + " " + name + ": ..." + decode(r.html.slice(Math.max(0, m.index - 160), m.index).replace(/<[^>]*>/g, "")).slice(-70) + "[" + m[1] + "]" + decode(r.html.slice(m.index + m[0].length, m.index + m[0].length + 100).replace(/<[^>]*>/g, "")).slice(0, 40));
      const o = oracleOf(text, CTX.names);
      LINK.idLinks += idLinks.length; LINK.idMissing += miss.length; LINK.idMentions += idLinks.length + miss.length; LINK.tribLinks += trib;
      LINK.oracleIdMentions += o.ids; LINK.oracleTribLinks += o.trLinks; LINK.oracleTribPlain += o.trPlain; LINK.tribPlainByRule += o.trPlain;
      for (const m of miss) LINK.unknownIds[m] = (LINK.unknownIds[m] || 0) + 1;
      for (const id of idLinks) { const u = CTX.byId.get(id); const st = u ? u.state : "?"; LINK.byState[st] = (LINK.byState[st] || 0) + 1; }
      if (idLinks.length + miss.length !== o.ids || trib !== o.trLinks) LINK.disagree.push(tk.id + " " + name + ": page " + (idLinks.length + miss.length) + " ids and " + trib + " tributaries, oracle " + o.ids + " and " + o.trLinks);
    }
    // text content equals the source word for word, in order
    const a = sourceWords(text), b = words(spaced);
    stat.wordsIn += a.length; stat.wordsOut += b.length;
    if (!r.cuts) {
      let i = 0; while (i < a.length && i < b.length && a[i] === b[i]) i++;
      if (a.length !== b.length || i < a.length) stat.mismatch.push(tk.id + " " + name + ": words differ at " + i + " (source " + JSON.stringify(a.slice(Math.max(0, i - 3), i + 4).join(" ")) + " / page " + JSON.stringify(b.slice(Math.max(0, i - 3), i + 4).join(" ")) + ")");
    }
    if (!r.cuts) {
      const sp = subsequenceProblem(text, decodeText(r.html).split(LABELS[0]).join("").split(LABELS[1]).join(""));
      if (sp) stat.mismatch.push(tk.id + " " + name + ": " + sp);
      const rn = renderedNumbers(r.html), sn = sourceNumbers(text);
      stat.orderedItems = (stat.orderedItems || 0) + rn.length;
      if (JSON.stringify(rn) !== JSON.stringify(sn)) stat.mismatch.push(tk.id + " " + name + ": ordered numbers differ (page " + JSON.stringify(rn.slice(0, 8)) + " / source " + JSON.stringify(sn.slice(0, 8)) + ")");
      const srcLines = MD.visible(text.replace(/\r\n?/g, "\n")).split("\n");
      for (const pre of preTexts(r.html)) { stat.preBlocks = (stat.preBlocks || 0) + 1; if (!blockIsARun(srcLines, pre)) stat.mismatch.push(tk.id + " " + name + ": a code block is not a run of source lines (" + JSON.stringify(pre.slice(0, 40)) + ")"); }
    }
    // code blocks
    const src = fences(text), outs = preTexts(r.html);
    stat.codeBlocks.sourceFences += src.length;
    let at = 0;
    for (const f of src) {
      stat.codeBlocks.compared++;
      let found = -1;
      for (let k = at; k < outs.length; k++) if (outs[k] === f.body) { found = k; break; }
      if (found < 0) { stat.codeBlocks.notFound.push(tk.id + " " + name + " (indent " + f.indent + ", " + f.body.length + " chars)"); stat.mismatch.push(tk.id + " " + name + ": a code block is not reproduced exactly"); continue; }
      at = found + 1;
      if (f.indent === 0) stat.codeBlocks.byteExact++; else stat.codeBlocks.exactAfterIndent++;
    }
  }
  // what the page itself says about this ticket
  const A = R.approvals;
  const view = A.view({ resp: { state: "ok", facts: { version: body.facts.version, at: 1, run: "r", scope: "", themes: [{ id: "t", title: "t", purpose: "", rafts: [{ id: tk.id, title: "x", single: true, tickets: [tk] }] }] } }, err: null, idx: 0, stage: "design", msg: "", now: 1 });
  for (const [label, re] of [["older engine", /made by an older engine/], ["a section ends inside a code block", /ends at a heading inside a code block/], ["a text cut", /Text cut here|characters shown; the full text/], ["too large to format", /too large to format/], ["could not be formatted", /could not be formatted/], ["template comments not shown", /template comments? not shown/], ["a hidden note", /A note hidden in the document/]])
    if (re.test(view)) stat.pageNotices[label] = (stat.pageNotices[label] || []).concat(tk.id);
}

if (flag === "--oracle") {
  const norm = s => s.replace(/\s+/g, "");
  const git = args => execFileSync("git", args, { encoding: "utf8", maxBuffer: 64 << 20, timeout: 60000 });
  const tree = git(["ls-tree", "-r", "--name-only", "origin/main"]).split("\n");
  const fold = s => s.replace(/\s+/g, " ").trim();
  const tpl = new Set();
  for (const f of ["z-nile/templates/issue/doc.md", "z-nile/templates/raft/doc.md"]) for (const c of git(["show", "origin/main:" + f]).matchAll(/<!--[\s\S]*?-->/g)) if (!c[0].includes("{{")) tpl.add(fold(c[0]));
  let compared = 0, dropped = 0;
  for (const tk of tickets) {
    const file = tree.find(f => f.endsWith("/" + tk.id + "/" + tk.id + ".md"));
    if (!file) { stat.mismatch.push(tk.id + ": no document on origin/main"); continue; }
    const lines = git(["show", "origin/main:" + file]).replace(/\r\n?/g, "\n").split("\n");
    const section = h => { const i = lines.indexOf("## " + h); if (i < 0) return ""; let j = i + 1; while (j < lines.length && !lines[j].startsWith("## ")) j++; return lines.slice(i + 1, j).join("\n"); };
    const noTpl = s => s.replace(/<!--[\s\S]*?-->/g, c => (tpl.has(fold(c)) ? (dropped++, "") : c));
    const got = { Problem: tk.idea.problem, Solution: tk.idea.solution, "Acceptance criteria": ((tk.extra || []).find(d => d.heading === "Acceptance criteria") || { text: "" }).text, "Test plan": ((tk.extra || []).find(d => d.heading === "Test plan") || { text: "" }).text };
    got.Design = (tk.design || []).map(d => (d.heading === "Design" && d === tk.design[0] ? "" : "### " + d.heading + "\n") + d.text).join("\n");
    for (const h of ["Problem", "Solution", "Design", "Acceptance criteria", "Test plan"]) {
      compared++;
      const want = norm(noTpl(section(h))), have = norm(got[h]);
      if (want !== have) stat.mismatch.push(tk.id + " " + h + ": disk " + want.length + " non-space characters, page " + have.length);
    }
  }
  stat.oracle = { sectionsCompared: compared, templateCommentsDroppedByOracle: dropped, templateCommentsCountedByEngine: stat.templateCountedByEngine };
  if (dropped !== stat.templateCountedByEngine) stat.mismatch.push("template comments: the oracle dropped " + dropped + ", the engine counted " + stat.templateCountedByEngine);
}

if (CTX) {
  const byStateOfIndex = {}; for (const u of CTX.facts.units) byStateOfIndex[u.state] = (byStateOfIndex[u.state] || 0) + 1;
  stat.index = { units: CTX.facts.units.length, byState: byStateOfIndex, bytesOnDisk: +optionOf("units-bytes") || null, withdrawnCut: CTX.facts.withdrawn_cut, dropped: CTX.facts.dropped };
  const bytes = t => Buffer.byteLength(t, "utf8");
  const parts = { whole: 0, clipped: 0, omitted: 0, empty: 0 };
  for (const u of CTX.units) if (u.state === "backlog" || u.state === "active") for (const d of [{ text: u.problem, size: u.problem_size }, { text: u.solution, size: u.solution_size }].concat(u.design)) { if (d.size === 0 && d.text === "") parts.empty++; else if (d.text === "") parts.omitted++; else if (bytes(d.text) === d.size) parts.whole++; else parts.clipped++; }
  stat.index.previewParts = parts;
  const c0261 = CTX.byId.get("c0261");
  stat.c0261 = c0261 ? { state: c0261.state, when: c0261.when, subject: c0261.subject } : null;
  stat.links = Object.assign({}, LINK, { unknownIds: Object.keys(LINK.unknownIds).sort(), unknownIdMentions: Object.values(LINK.unknownIds).reduce((a, b) => a + b, 0) });
  for (const d of LINK.disagree) stat.mismatch.push("link oracle: " + d);
  const expect = optionOf("expect");
  if (expect) {
    const want = JSON.parse(fs.readFileSync(expect, "utf8"));
    const got = { idMentions: LINK.idMentions, idLinks: LINK.idLinks, idMissing: LINK.idMissing, tribLinks: LINK.tribLinks, tribPlainByRule: LINK.tribPlainByRule, unknownIds: Object.keys(LINK.unknownIds).sort(), c0261: stat.c0261 };
    for (const k of Object.keys(want)) if (JSON.stringify(want[k]) !== JSON.stringify(got[k])) stat.mismatch.push("frozen count " + k + ": expected " + JSON.stringify(want[k]) + ", got " + JSON.stringify(got[k]));
    stat.frozen = got;
  }
}
console.log(JSON.stringify(stat, null, 1));
if (stat.bad.length || stat.mismatch.length || stat.over) { console.error("FAIL: " + stat.bad.length + " rendering problems, " + stat.mismatch.length + " mismatches, " + stat.over + " budget exits"); for (const m of stat.mismatch.slice(0, 10)) console.error("  " + m); process.exit(1); }
console.log("app-md-real: ok");
