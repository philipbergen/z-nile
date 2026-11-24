"use strict";
// f0437 step 6, slice 1 (F1, F12): the whole chain on real data. node app-md-real.node.js <app folder> <served.json> [--oracle]
// <served.json> is what the Go reader served for the engine's facts. Every ticket's idea, design parts, Acceptance criteria and
// Test plan go through the page's renderer; the output must parse as the allowed tree, with no exception. With --oracle (the
// one-time proof, run on the real tracker) the text the page receives for each contract section is also compared with the
// section as it is on disk (git show origin/main), ignoring only white space and the template comments the engine counts.
const fs = require("fs");
const path = require("path");
const vm = require("vm");
const { execFileSync } = require("child_process");

const [dir, served, flag] = process.argv.slice(2);
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
const R = box.LiveApp.make({ esc, mono: esc, ic: () => "", WSTATE: {}, fmtDur: () => "", ptTime: () => "", pl: (n, w) => n + " " + w, now: () => 0 });
const MD = R.md;

const ALLOWED = new Set(["p", "h3", "h4", "h5", "h6", "ul", "ol", "li", "strong", "em", "code", "pre", "table", "thead", "tbody", "tr", "th", "td", "blockquote", "hr", "a", "br", "div", "span"]);
function problems(html) {
  const out = [];
  for (const m of html.matchAll(/<(\/?)([a-zA-Z0-9]+)([^>]*)>/g)) {
    if (!ALLOWED.has(m[2])) out.push("element " + m[2]);
    for (const a of m[3].matchAll(/\s([a-zA-Z-]+)=/g)) if (!["class", "href", "start"].includes(a[1])) out.push("attribute " + a[1]);
    for (const h of m[3].matchAll(/href="([^"]*)"/g)) if (!/^#\/(?:ticket|raft|approvals|tributary)\//.test(h[1])) out.push("href " + h[1]);
  }
  // a raw < in text: after removing the allowed tags, none may remain
  const stripped = html.replace(/<\/?[a-z0-9]+(?:\s[^<>]*)?>/g, "");
  if (/[<>]/.test(stripped)) out.push("a raw < or > in text");
  return out;
}

const body = JSON.parse(fs.readFileSync(served, "utf8"));
if (body.state !== "ok") { console.error("the served facts are " + body.state + ": " + body.why); process.exit(1); }
const tickets = [];
for (const th of body.facts.themes) for (const r of th.rafts) for (const tk of r.tickets) tickets.push(tk);

const stat = { tickets: 0, charsIn: 0, charsShown: 0, cuts: 0, cutWhere: [], notesShown: 0, templateCounted: 0, elements: {}, maxSteps: 0, maxStepsIn: "", over: 0, bad: [], mismatch: [], parts: 0 };
const sectionsOf = tk => {
  const s = [["Problem", tk.idea.problem], ["Solution", tk.idea.solution]];
  for (const d of tk.design || []) s.push(["Design/" + d.heading, d.text]);
  for (const d of tk.extra || []) s.push([d.heading, d.text]);
  return s;
};
for (const tk of tickets) {
  stat.tickets++; stat.templateCounted += tk.comments || 0;
  for (const [name, text] of sectionsOf(tk)) {
    stat.parts++; stat.charsIn += text.length;
    let r;
    try { r = MD.render(text); } catch (e) { stat.bad.push(tk.id + " " + name + ": exception " + e.message); continue; }
    stat.charsShown += text.length;
    for (const p of problems(r.html)) stat.bad.push(tk.id + " " + name + ": " + p);
    stat.cuts += r.cuts; if (r.cuts) stat.cutWhere.push(tk.id + " " + name);
    stat.notesShown += r.notes; if (r.over) stat.over++;
    for (const [k, v] of Object.entries(r.elements)) stat.elements[k] = (stat.elements[k] || 0) + v;
    if (r.steps > stat.maxSteps) { stat.maxSteps = r.steps; stat.maxStepsIn = tk.id + " " + name + " (" + text.length + " characters)"; }
    if (/first \d+ of \d+ characters shown; the full text is in the ticket file/.test(text)) { stat.cuts++; stat.cutWhere.push(tk.id + " " + name + " (hard cap)"); }
  }
}

if (flag === "--oracle") {
  const norm = s => s.replace(/\s+/g, "");
  const git = args => execFileSync("git", args, { encoding: "utf8", maxBuffer: 64 << 20, timeout: 60000 });
  const tree = git(["ls-tree", "-r", "--name-only", "origin/main"]).split("\n");
  const fold = s => s.replace(/\s+/g, " ").trim();
  const tpl = [];
  for (const f of ["z-nile/templates/issue/doc.md", "z-nile/templates/raft/doc.md"]) for (const c of git(["show", "origin/main:" + f]).matchAll(/<!--[\s\S]*?-->/g)) tpl.push(fold(c[0]));
  const isTpl = c => tpl.some(t => (t.includes("{{") ? new RegExp("^" + t.replace(/[.*+?^${}()|[\]\\]/g, "\\$&").replace(/\\\{\\\{\w+\\\}\\\}/g, ".*?") + "$").test(fold(c)) : t === fold(c)));
  let compared = 0, dropped = 0;
  for (const tk of tickets) {
    const file = tree.find(f => f.endsWith("/" + tk.id + "/" + tk.id + ".md"));
    if (!file) { stat.mismatch.push(tk.id + ": no document on origin/main"); continue; }
    const doc = git(["show", "origin/main:" + file]).replace(/\r\n?/g, "\n");
    const lines = doc.split("\n");
    const section = h => { const i = lines.indexOf("## " + h); if (i < 0) return ""; let j = i + 1; while (j < lines.length && !lines[j].startsWith("## ")) j++; return lines.slice(i + 1, j).join("\n"); };
    const noTpl = s => s.replace(/<!--[\s\S]*?-->/g, c => (isTpl(c) ? (dropped++, "") : c));
    const got = { Problem: tk.idea.problem, Solution: tk.idea.solution, "Acceptance criteria": ((tk.extra || []).find(d => d.heading === "Acceptance criteria") || { text: "" }).text, "Test plan": ((tk.extra || []).find(d => d.heading === "Test plan") || { text: "" }).text };
    got.Design = (tk.design || []).map(d => (d.heading === "Design" && d === tk.design[0] ? "" : "### " + d.heading + "\n") + d.text).join("\n");
    for (const h of ["Problem", "Solution", "Design", "Acceptance criteria", "Test plan"]) {
      compared++;
      const want = norm(noTpl(section(h))), have = norm(got[h]);
      if (want !== have) stat.mismatch.push(tk.id + " " + h + ": disk " + want.length + " non-space characters, page " + have.length);
    }
    if (dropped !== undefined) { /* counted below per ticket */ }
  }
  stat.oracle = { sectionsCompared: compared, templateCommentsDroppedByOracle: dropped, templateCommentsCountedByEngine: stat.templateCounted };
  if (dropped !== stat.templateCounted) stat.mismatch.push("template comments: the oracle dropped " + dropped + ", the engine counted " + stat.templateCounted);
}

console.log(JSON.stringify(stat, null, 1));
if (stat.bad.length || stat.mismatch.length || stat.over) { console.error("FAIL: " + stat.bad.length + " rendering problems, " + stat.mismatch.length + " mismatches, " + stat.over + " budget exits"); process.exit(1); }
console.log("app-md-real: ok");
