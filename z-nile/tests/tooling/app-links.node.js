"use strict";
// f0437 step 6, slice 2: ids that link, the detail view and the page's routing and fetching, run against a stub page. Called by
// app-links.spec.luau: node app-links.node.js <z-nile/app folder>. Every string of the units index is untrusted text: it is shown
// only through tx() or the renderer. Exits 0 when every case holds.
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
const flush = async () => { for (let i = 0; i < 12; i++) await new Promise(r => setImmediate(r)); };

/* ------------------------------------------------------------------ a page that can be driven: fetch answers, hash, history, events */
function rig(opts) {
  opts = opts || {};
  const els = {}, calls = { fetch: [], sets: 0 }, handlers = {}, docHandlers = {};
  const routes = Object.assign({}, opts.routes || {});
  const elOf = sel => {
    if (!els[sel]) {
      let html = "";
      els[sel] = { scrollTop: 0, dataset: {}, className: "", get innerHTML() { return html; }, set innerHTML(v) { html = v; if (sel === "#pg-body") calls.sets++; }, setAttribute() {}, getAttribute() { return null; } };
    }
    return els[sel];
  };
  const box = {
    location: { protocol: "http:", hash: opts.hash || "" },
    history: { replaced: [], replaceState(_s, _t, url) { this.replaced.push(url); box.location.hash = url; } },
    console: { error() {} },
    st: { view: "workers", route: {}, sel: null }, sim: { sel: "x" },
    NAV: [["approvals", "inbox", "Approvals"], ["workers", "robot", "Workers"], ["tickets", "layers", "Tickets"]],
    WSTATE: { working: ["c-ok", "spark", "Working"], idle: ["c-trib", "moon", "Idle"], lost: ["c-risky", "alert", "Lost"] },
    esc: eval(escLine[1]), mono: s => '<span class="mono">' + box.esc(s) + "</span>", ic: n => '<svg class="' + n + '"/>',
    fmtDur: ms => Math.floor(ms / 60000) + " min", ptTime: () => "00:00:00", pl: (n, w) => n + " " + w + (n === 1 ? "" : "s"),
    $: sel => elOf(sel), $$: () => [], withFocus: f => f(), ensurePage(kind) { elOf("#view").dataset.page = kind; }, renderDetail() {}, updateLive() {},
    queue: () => ({}), queueHtml: () => '<aside><h2 id="qph">Queue</h2></aside>',
    renderWorkers() {}, liveText: () => ["sim", "0"],
    renderView() { box.viewSimulated = (box.viewSimulated || 0) + 1; },
    parseRoute() {
      const parts = String(box.location.hash || "").replace(/^#\/?/, "").split("/").filter(Boolean).map(s => { try { return decodeURIComponent(s); } catch (e) { return s; } });
      const a = parts[0] || "approvals";
      if (a === "approvals") return { view: "approvals", kind: null, id: parts[1] || null };
      if (a === "workers" || a === "stats") return { view: a, kind: null, id: null };
      const V = { ticket: "tickets", raft: "tickets", tributary: "tickets", guess: "tickets", worker: "workers" };
      if (V[a] && parts[1]) return { view: V[a], kind: a, id: parts[1], x: parts[2] || null };
      return { view: "approvals", kind: null, id: null };
    },
    // the mockup's own applyRoute: it empties the view, renders, then resets the scroll to the top
    applyRoute() { const r = box.parseRoute(); box.st.route = r; box.st.view = r.view; elOf("#view").innerHTML = ""; box.renderView(); elOf("#view").scrollTop = 0; box.routed = (box.routed || 0) + 1; },
    fetch(u, init) {
      calls.fetch.push({ url: u, headers: (init && init.headers) || {} });
      const h = routes[u];
      if (!h) return Promise.reject(new Error("no route " + u));
      const r = typeof h === "function" ? h(init) : h;
      if (r instanceof Error) return Promise.reject(r);
      const body = typeof r.body === "string" ? r.body : JSON.stringify(r.body);
      const status = r.status || 200;
      return Promise.resolve({ ok: status >= 200 && status < 300, status, headers: { get: n => (String(n).toLowerCase() === "etag" ? (r.etag || null) : null) }, text: () => Promise.resolve(body), json: () => Promise.resolve(JSON.parse(body)) });
    },
    EventSource: function (u) { calls.es = u; box.es = this; this.readyState = 1; },
    setInterval() {}, setTimeout(f) { f(); },
    addEventListener(type, fn) { (handlers[type] = handlers[type] || []).push(fn); },
    document: {
      body: { appendChild(e) { if (e.id) els["#" + e.id] = e; } },
      getElementById: id => els["#" + id] || null,
      createElement: () => ({ dataset: {}, className: "", innerHTML: "", setAttribute() {} }),
      addEventListener(type, fn) { (docHandlers[type] = docHandlers[type] || []).push(fn); },
    },
  };
  box.addEventListener("hashchange", () => box.applyRoute()); // the mockup registered it first
  vm.createContext(box);
  box.globalThis = box;
  vm.runInContext(code, box);
  const view = elOf("#view");
  return {
    box, calls, view, body: elOf("#pg-body"), routes, handlers,
    fire(type, e) { for (const f of docHandlers[type] || []) f(e || {}); },
    hash(h) { box.location.hash = h; for (const f of handlers.hashchange || []) f({}); },
    event() { box.es.onmessage({}); },
    html: () => elOf("#pg-body").innerHTML,
    badge: () => (elOf("#srcbadge").innerHTML || ""),
  };
}

/* ------------------------------------------------------------------ the data */
const HOSTILE = '"><img src=x onerror=1>';
const unitRow = (o) => Object.assign({ kind: "ticket", title: "", project: "p", state: "backlog", tributary: "alpha", themes: ["alpha"], raft: "", members: [], depends_on: [] }, o);
const UNITS = { version: 1, at: 1000, commit: "abc1234", sig: "sig-one", dropped: 0, withdrawn_cut: 0, units: [
  unitRow({ id: "c0001", title: "Open one", raft: "R0010", depends_on: ["c0003"], problem: "The problem sees c0003 and c0261 and c0777.", solution: "The solution is R0010.", design: [{ heading: "Part A", text: "Design text with c0002 inside." }], clipped: true }),
  unitRow({ id: "c0002", title: "Active member", state: "active", raft: "R0010", problem: "P2", solution: "S2", design: [] }),
  unitRow({ id: "c0003", title: "Done one", state: "done", tributary: "earlier-work", themes: ["earlier-work"] }),
  unitRow({ id: "c0004", title: "Closed one", state: "closed", tributary: "unsorted", themes: ["unsorted"] }),
  unitRow({ id: "R0010", kind: "raft", title: "The raft", members: ["c0001", "c0002"], problem: "Raft problem", solution: "Raft solution", design: [] }),
  unitRow({ id: "R0011", kind: "raft", title: "Retired raft", state: "retired", tributary: "unsorted", themes: ["unsorted"] }),
  unitRow({ id: "c0261", title: "", project: "", state: "withdrawn", tributary: "", themes: [], when: "2026-11-02", subject: "tracker: withdraw c0261 (met by #299)", fate: "withdrawn" }),
] };
const tk = (id, extra) => Object.assign({ id, title: "Title " + id, why: "no approval (1 guesses)", place: "origin/main", idea: { problem: "P " + id, solution: "S " + id }, design: [{ heading: "Slim design", text: "D " + id }], extra: [], comments: 0, guesses: [], reviews: [], hash: "0123456789abcdef0123456789abcdef", cost: null, links: {} }, extra || {});
const APPROVALS = { version: 2, at: 5, run: "20261122T010203Z-a1b2", scope: "", themes: [
  { id: "alpha", title: "Alpha", purpose: "first", rafts: [{ id: "R0010", title: "The raft", single: false, themes: ["alpha"], tickets: [tk("c0001", { idea: { problem: "see c0003 and c0261 and c0002 and c0777", solution: "x" } }), tk("c0002")] }] },
  { id: "beta", title: "Beta", purpose: "", rafts: [{ id: "c0009", title: "Alone", single: true, themes: ["beta"], tickets: [tk("c0009")] }] }] };
const THEMES = { version: 1, at: 900, live: true, commit: "abc1234", approvalsScope: "", themes: [
  { id: "alpha", project: "p", title: "Alpha", purpose: "The first body.", counts: { done: 1, flight: 0, approval: 2, owner: 0, open: 1 }, workers: [], units: [] },
  { id: "worker", project: "p", title: "worker", purpose: "Workers.", counts: { done: 0, flight: 0, approval: 0, owner: 0, open: 0 }, workers: [], units: [] },
  { id: "beta", project: "p", title: "Beta", purpose: "", counts: { done: 0, flight: 0, approval: 1, owner: 0, open: 0 }, workers: [], units: [] }] };
const STATE = { seq: 1, now: 5, workers: [], claims: [] };
const ok = (facts) => ({ state: "ok", facts });
const serve = (r, o) => {
  o = o || {};
  r.routes["/api/state"] = { body: STATE };
  const tagged = (body, tag) => init => (init && init.headers && init.headers["If-None-Match"] === tag ? { status: 304, body: "" } : { body, etag: tag });
  r.routes["/api/themes"] = tagged(ok(THEMES), '"t1"');
  r.routes["/api/approvals"] = o.approvals ? { body: o.approvals } : tagged(ok(APPROVALS), '"a1"');
  if (o.units !== null) r.routes["/api/units"] = o.units || (init => (init && init.headers && init.headers["If-None-Match"] === '"e1"' ? { status: 304, body: "" } : { body: ok(UNITS), etag: '"e1"' }));
};
const txtOf = h => h.replace(/<[^>]*>/g, "");
/* no <a> or <button> anywhere inside an <a> or a <button> (a browser re-parents a link in a link and a link in a button is nested interactive content) */
function interactive(html) {
  const out = [], stack = [];
  for (const m of html.matchAll(/<(\/?)(a|button)\b[^>]*>/g)) {
    if (m[1]) { const i = stack.lastIndexOf(m[2]); if (i >= 0) stack.length = i; continue; }
    if (stack.length) out.push("<" + m[2] + "> inside <" + stack[stack.length - 1] + ">");
    stack.push(m[2]);
  }
  return out;
}
const tagsOf = html => [...html.matchAll(/<a href="([^"]*)"[^>]*>/g)].map(m => m[1]);
const hasLink = (html, href) => html.includes('<a href="' + href + '"');

(async () => {
  const f0 = rig();
  const R = f0.box.LiveApp.make({ esc: f0.box.esc, mono: f0.box.mono, ic: f0.box.ic, WSTATE: f0.box.WSTATE, fmtDur: f0.box.fmtDur, ptTime: f0.box.ptTime, pl: f0.box.pl, now: () => 1300 * 1000 });
  const A = R.approvals, D = R.detail;
  check("the detail view is part of the pure renderers", !!D && typeof D.view === "function" && typeof R.links === "object");

  /* ---------- the Approvals view: ids in ticket text and in the page's own places become links */
  {
    const units = { resp: ok(UNITS) };
    const v = A.view({ resp: ok(APPROVALS), err: null, idx: 0, stage: "design", msg: "", themes: { state: "ok", facts: THEMES }, units, now: 1300 * 1000 });
    check("walk: an id in the idea is a link to its detail view", hasLink(v, "#/ticket/c0003"), v.slice(0, 200));
    check("walk: an id of a unit that waits links into the walk", hasLink(v, "#/approvals/c0002"));
    check("walk: an id the index holds only as a withdrawn stub links to the stub", hasLink(v, "#/ticket/c0261"));
    check("walk: an id the index lacks is marked, never a link, with a tooltip that allows for a stale index", v.includes('<span class="md-miss" title="not in the units index made at 00:00:00 PT">c0777</span>'), v.slice(0, 200));
    check("walk: the raft's id in the breadcrumb links to the raft", hasLink(v, "#/raft/R0010"));
    check("walk: the ticket's own id in its heading is not a link to itself", /<h2><span class="mono">c0001<\/span> Title c0001<\/h2>/.test(v) && !/<h2><a/.test(v), v.slice(v.indexOf("<h2>"), v.indexOf("<h2>") + 120));
    check("walk: no interactive element sits inside another (a link in a link, in a button)", interactive(v).length === 0, interactive(v).join("; "));
    check("the interactive check itself refuses a link inside a button and a link in a link", interactive('<button><span><a href="#/x">y</a></span></button>').length === 1 && interactive('<a href="#/a"><b><a href="#/b">y</a></b></a>').length === 1 && interactive('<button><button>x</button></button>').length === 1 && interactive('<p><a href="#/a">y</a> <button>z</button></p>').length === 0);
    check("walk: every href is an app route", tagsOf(v).every(h => /^#\/(?:ticket|raft|approvals|tributary)\/[A-Za-z0-9%_-]+$/.test(h)), tagsOf(v).join());
    const text = v.replace(/<[^>]*>/g, "");
    const plain = A.view({ resp: ok(APPROVALS), err: null, idx: 0, stage: "design", msg: "", themes: { state: "ok", facts: THEMES }, units: null, now: 1300 * 1000 }).replace(/<[^>]*>/g, "");
    check("walk: links change no word of the page", text === plain.replace(/Ids are plain text until the units index has loaded[^.]*\./, ""), text.length + " vs " + plain.length);
  }

  /* ---------- an index that is not there: plain text, and one line says why (absent, unreadable, old daemon, failed, loading) */
  {
    const base = { resp: ok(APPROVALS), err: null, idx: 0, stage: "design", msg: "", themes: { state: "ok", facts: THEMES }, now: 1300 * 1000 };
    const words = (units) => A.view(Object.assign({}, base, { units }));
    const old = words({ old: true });
    check("old daemon: the page says it is older and how to restart", old.includes("this daemon is older than the page: restart it with ./zn app"), old.slice(0, 100));
    check("old daemon: ids are plain text", tagsOf(old).filter(h => !h.startsWith("#/tributary")).length === 0 && !old.includes("md-miss"));
    const absent = words({ resp: { state: "absent", why: "No units index has been written yet. Run ./zn board." } });
    check("absent: says no index and what to run", absent.includes("No units index has been written yet") && absent.includes("Ids are plain text"), "");
    const unread = words({ resp: { state: "unreadable", why: "the units index is not valid JSON; run ./zn board to write it again" } });
    check("unreadable: says why", unread.includes("not valid JSON") && unread.includes("Ids are plain text"));
    const fail = words({ err: "HTTP 500" });
    check("failed: says it could not be fetched", fail.includes("could not be fetched") && fail.includes("HTTP 500"));
    const loading = words({});
    check("loading: says ids become links when the index has loaded", loading.includes("until the units index has loaded"));
    check("none of them blanks the view: the ticket is still there", [old, absent, unread, fail, loading].every(h => h.includes("Title c0001") && h.includes("see c0003")));
    const hostile = words({ resp: { state: "unreadable", why: HOSTILE } });
    check("the reason is escaped", !hostile.includes("<img") && hostile.includes("&lt;img"));
  }

  /* ---------- the detail view */
  {
    const units = { resp: ok(UNITS) };
    const view = (kind, id, o) => D.view(Object.assign({ kind, id, units, approvals: ok(APPROVALS), themes: { state: "ok", facts: THEMES }, state: STATE, now: 1300 * 1000 }, o || {}));
    const t1 = view("ticket", "c0002");
    check("detail: a waiting ticket links into the walk at its place", hasLink(t1, "#/approvals/c0002") && /waits for your approval/i.test(t1), t1.slice(0, 300));
    const t0 = view("ticket", "c0001");
    check("detail: title, id and state in plain words", t0.includes("Open one") && t0.includes("c0001") && /in the backlog/.test(t0), "");
    check("detail: its raft, tributary and dependency are links", hasLink(t0, "#/raft/R0010") && hasLink(t0, "#/tributary/alpha") && hasLink(t0, "#/ticket/c0003"), tagsOf(t0).join());
    check("detail: the idea and the design preview are rendered by the renderer, with their ids linked", t0.includes('class="md"') && hasLink(t0, "#/ticket/c0003") && t0.includes("Part A") && hasLink(t0, "#/approvals/c0002"));
    check("detail: a clipped text says so and that the full text is in the ticket file", /clipped|first/i.test(t0) && t0.includes("the full text is in the ticket file"), "");
    check("detail: each source says its age (the index, the approval facts, the theme facts)", /units index made [^;]*ago/.test(txtOf(t0)) && /approval facts/.test(t0) && /theme facts/.test(t0), "");
    check("detail: it is a real view, never labelled simulated", !/simulated/i.test(t0));
    check("detail: no link leads to a view that is only a mockup", tagsOf(t0).every(h => !/^#\/(?:tickets|rafts|stats|guess|worker|queue)/.test(h)) && !/#\/tickets/.test(t0));
    const done = view("ticket", "c0003");
    check("detail: a done unit shows its title and place only, no text", done.includes("Done one") && /done/.test(done) && !done.includes('class="md"'), "");
    const closed = view("ticket", "c0004");
    check("detail: a closed unit says closed and carries no text", /closed/.test(closed) && !closed.includes('class="md"'));
    const retired = view("raft", "R0011");
    check("detail: a retired raft says retired", /retired/.test(retired));
    const raft = view("raft", "R0010");
    check("detail: a raft lists its members in order as links with their state", raft.indexOf("c0001") < raft.indexOf("c0002") && hasLink(raft, "#/approvals/c0001") && hasLink(raft, "#/approvals/c0002") && /in the backlog/.test(raft) && /in code/.test(raft), raft.slice(0, 400));
    const stub = view("ticket", "c0261");
    check("detail: a withdrawn id shows the stub: withdrawn, the date, the commit's subject", /withdrawn/.test(stub) && stub.includes("2026-11-02") && stub.includes("tracker: withdraw c0261 (met by #299)"), stub.slice(0, 300));
    check("detail: a withdrawn stub does not pretend there is a ticket", /no ticket file/i.test(stub) && !stub.includes('class="md"'));
    const none = view("ticket", "c0999");
    check("detail: an unknown id says there is no such unit in the tracker now, with the index's age, and a way home", /No unit c0999 in the tracker/.test(none) && /units index made [^;]*ago/.test(txtOf(none)) && hasLink(none, "#/themes"), none.slice(0, 300));
    const wrong = view("raft", "c0001");
    check("detail: a ticket asked for as a raft says what it is and links it", /c0001 is a ticket/.test(wrong) && hasLink(wrong, "#/approvals/c0001"), wrong.slice(0, 200));
    const trib = view("tributary", "alpha");
    check("detail: a tributary shows its row from the theme facts and its units as links", trib.includes("The first body.") && hasLink(trib, "#/approvals/c0001") && hasLink(trib, "#/raft/R0010") && !hasLink(trib, "#/ticket/c0003"), trib.slice(0, 300));
    const notrib = view("tributary", "nothing");
    check("detail: an unknown tributary says so", /No tributary nothing/.test(notrib));
    const off = view("ticket", "c0001", { units: { old: true } });
    check("detail: with no index it says why and never blanks", off.includes("this daemon is older than the page: restart it with ./zn app") && off.includes("c0001"));
    const hostile = { resp: ok(Object.assign({}, UNITS, { units: [unitRow({ id: "c0001", title: HOSTILE, project: HOSTILE, tributary: HOSTILE, themes: [HOSTILE], raft: "R0010", depends_on: [HOSTILE, "c0003"], problem: HOSTILE, solution: HOSTILE, design: [{ heading: HOSTILE, text: HOSTILE }] }), unitRow({ id: "R0010", kind: "raft", title: HOSTILE, members: [HOSTILE, "c0001"] }), unitRow({ id: "c0261", state: "withdrawn", when: HOSTILE, subject: HOSTILE }), unitRow({ id: "c0003", title: HOSTILE, state: "done" })] })) };
    const h1 = view("ticket", "c0001", { units: hostile }), h2 = view("raft", "R0010", { units: hostile }), h3 = view("ticket", "c0261", { units: hostile }), h4 = view("tributary", HOSTILE, { units: hostile });
    check("detail: hostile strings of the index are escaped in every view", [h1, h2, h3, h4].every(h => !/<img/.test(h) && h.includes("&lt;img")), [h1, h2, h3, h4].map(h => h.indexOf("<img")).join());
    check("detail: a hostile name never reaches an href", [h1, h2, h3, h4].every(h => tagsOf(h).every(x => /^#\/(?:(?:ticket|raft|approvals|tributary)\/[A-Za-z0-9%_-]+|themes|approvals)$/.test(x))), tagsOf(h1).join());
    check("detail: a tributary name that the themes do not hold is text, never a link", [h1, h4].every(h => !h.includes("#/tributary/%22")), tagsOf(h1).join());
    check("detail: invisible characters are marked", /‹U\+202E›/.test(view("ticket", "c0001", { units: { resp: ok(Object.assign({}, UNITS, { units: [unitRow({ id: "c0001", title: "a" + String.fromCharCode(0x202E) + "b" })] })) } })));
  }

  /* ---------- hostile text at every other site of the detail view and the notes (each was tried unescaped by a mutant) */
  {
    const clean = h => !/<img/.test(h) && h.includes("&lt;img");
    const D2 = (kind, id, o) => D.view(Object.assign({ kind, id, units: { resp: ok(UNITS) }, approvals: ok(APPROVALS), themes: { state: "ok", facts: THEMES }, state: STATE, now: 1300 * 1000 }, o || {}));
    const withUnits = list => ({ resp: ok(Object.assign({}, UNITS, { units: list })) });
    const kindMix = D2("ticket", HOSTILE, { units: withUnits([unitRow({ id: HOSTILE, kind: HOSTILE, title: HOSTILE, state: HOSTILE })]) });
    check("hostile id, kind and state of a unit are escaped, and the kind mismatch says so", clean(kindMix) && /is a /.test(kindMix), kindMix.slice(0, 300));
    const doneHostile = D2("ticket", "c0003", { units: withUnits([unitRow({ id: "c0003", state: HOSTILE, title: "t" })]) });
    check("a hostile state word is escaped for a unit that is not open", clean(doneHostile));
    const stub = D2("ticket", HOSTILE, { units: withUnits([unitRow({ id: HOSTILE, state: "withdrawn", when: HOSTILE, subject: HOSTILE })]) });
    check("a withdrawn stub with a hostile id, day and subject is escaped", clean(stub));
    const off = D2("ticket", HOSTILE, { units: { old: true } });
    check("with no index a hostile route id is escaped", clean(off) && !tagsOf(off).some(h => h.includes("img")));
    const commit = D2("ticket", "c0001", { units: { resp: ok(Object.assign({}, UNITS, { commit: HOSTILE })) } });
    check("a hostile commit is escaped", clean(commit));
    const claims = D2("ticket", "c0001", { state: { claims: [{ unit: "c0001", worker: HOSTILE, activity: HOSTILE }] } });
    check("a hostile worker and activity of a claim are escaped", clean(claims) && /Held now by/.test(claims));
    const themes = Object.assign({}, THEMES, { themes: [Object.assign({}, THEMES.themes[0], { purpose: HOSTILE, title: HOSTILE })].concat(THEMES.themes.slice(1)) });
    const trib = D2("tributary", "alpha", { themes: { state: "ok", facts: themes } });
    check("a hostile purpose of a theme is escaped", clean(trib));
    const noTrib = D2("tributary", HOSTILE);
    check("an unknown hostile tributary name is escaped in both places it is said", clean(noTrib) && !tagsOf(noTrib).some(h => h.includes("img")), noTrib.slice(0, 200));
    const unknownTrib = D2("ticket", "c0001", { units: withUnits([unitRow({ id: "c0001", title: "T", tributary: "nonesuch", themes: ["nonesuch", HOSTILE], state: "backlog" })]) });
    check("a tributary the theme facts do not hold is text, never a link", !hasLink(unknownTrib, "#/tributary/nonesuch") && unknownTrib.includes("nonesuch") && clean(unknownTrib));
    // the lookups of a response are built once, not at every paint
    const a1 = R.links.ctx({ units: { resp: ok(UNITS) }, approvals: ok(APPROVALS), themes: { state: "ok", facts: THEMES }, now: 5 }), a2 = R.links.ctx({ units: { resp: ok(UNITS) }, approvals: ok(APPROVALS), themes: { state: "ok", facts: THEMES }, now: 6 });
    const shared = { resp: ok(UNITS) };
    const b1 = R.links.ctx({ units: shared, now: 5 }), b2 = R.links.ctx({ units: shared, now: 6 });
    check("the index's lookups are built once per response", b1.byId === b2.byId && a1.byId !== undefined && a2.byId !== undefined);
  }

  /* ---------- fetching: first need, conditional, never everything again */
  {
    const r = rig({ hash: "#/approvals" });
    serve(r);
    check("start: only the live state is fetched, at the start", r.calls.fetch.map(c => c.url).join() === "/api/state", r.calls.fetch.map(c => c.url).join());
    await flush(); // the first state answer arrives while the Workers view is on
    r.box.applyRoute();
    await flush();
    const urls = r.calls.fetch.map(c => c.url);
    check("showing the Approvals view fetches the themes, the approvals and the units, once each", urls.filter(u => u === "/api/themes").length === 1 && urls.filter(u => u === "/api/approvals").length === 1 && urls.filter(u => u === "/api/units").length === 1, urls.join());
    check("the first units request is unconditional", !r.calls.fetch.find(c => c.url === "/api/units").headers["If-None-Match"]);
    const html1 = r.html();
    check("the walk shows the ticket with its ids linked once the index came", hasLink(html1, "#/ticket/c0003"), html1.slice(0, 200));
    const sets = r.calls.sets;
    const n = r.calls.fetch.length;
    r.event(); await flush();
    const again = r.calls.fetch.slice(n);
    check("F15: an event asks for the approvals and the themes with the tag it holds, and gets 304", again.filter(c => c.url === "/api/approvals" || c.url === "/api/themes").every(c => c.headers["If-None-Match"] === (c.url === "/api/themes" ? '"t1"' : '"a1"')) && again.filter(c => c.url !== "/api/state").length === 3, JSON.stringify(again));
    const unitsAgain = again.filter(c => c.url === "/api/units");
    check("an event asks for the units again, with the tag it holds, and gets 304", unitsAgain.length === 1 && unitsAgain[0].headers["If-None-Match"] === '"e1"', JSON.stringify(unitsAgain));
    check("an event whose facts are the same repaints nothing", r.calls.sets === sets, r.calls.sets + " vs " + sets);
    check("the index is still used after a 304", hasLink(r.html(), "#/ticket/c0003"));
    // the reader's place survives an event that changes the approvals
    r.view.scrollTop = 777;
    r.routes["/api/approvals"] = { body: ok(Object.assign({}, APPROVALS, { at: 6 })) };
    r.event(); await flush();
    check("an event that changes the facts repaints, and the scroll position stays", r.calls.sets === sets + 1 && r.view.scrollTop === 777, r.calls.sets + " / " + r.view.scrollTop);
    // a new index (a new tag) is a repaint with the new links
    r.routes["/api/units"] = { body: ok(Object.assign({}, UNITS, { sig: "sig-two", units: UNITS.units.filter(u => u.id !== "c0003") })), etag: '"e2"' };
    r.event(); await flush();
    check("a changed index repaints, and a unit that left the index is plain again", !hasLink(r.html(), "#/ticket/c0003") && /md-miss/.test(r.html()), "");
    check("the Workers view never fetches the units", (() => { const w = rig({ hash: "#/workers" }); serve(w); w.box.applyRoute(); return !w.calls.fetch.some(c => c.url === "/api/units"); })());
  }

  /* ---------- the old daemon, an absent file, a failure */
  {
    const r = rig({ hash: "#/approvals" });
    serve(r, { units: { status: 404, body: "404 page not found" } });
    r.box.applyRoute(); await flush();
    check("a 404 from the units route says the daemon is older, in place", r.html().includes("this daemon is older than the page: restart it with ./zn app"), r.html().slice(0, 100));
    check("and the walk is still shown", r.html().includes("Title c0001"));
    const n = r.calls.fetch.filter(c => c.url === "/api/units").length;
    r.event(); await flush();
    check("an old daemon is not asked again on every event", r.calls.fetch.filter(c => c.url === "/api/units").length === n, "");
    const a = rig({ hash: "#/approvals" });
    serve(a, { units: { body: { state: "absent", why: "No units index has been written yet. Run ./zn board.", facts: null } } });
    a.box.applyRoute(); await flush();
    check("an absent file is told apart from an old daemon", a.html().includes("No units index has been written yet") && !a.html().includes("older than the page"));
    const e = rig({ hash: "#/approvals" });
    serve(e, { units: new Error("network down") });
    e.box.applyRoute(); await flush();
    check("a network failure says the index could not be fetched", e.html().includes("could not be fetched") && e.html().includes("Title c0001"));
  }

  /* ---------- routing: the walk's place in the address, Back, the filter, scroll */
  {
    const r = rig({ hash: "#/approvals" });
    serve(r);
    r.box.applyRoute(); await flush();
    check("the walk puts its ticket in the address without making a history entry", r.box.history.replaced.length >= 1 && r.box.location.hash === "#/approvals/c0001", r.box.history.replaced.join() + " " + r.box.location.hash);
    // step to the next ticket
    const click = (attr, val) => r.fire("click", { target: { closest: sel => (sel === "[data-ap]" && attr === "ap" ? { dataset: { ap: val } } : null) } });
    click("ap", "next");
    check("stepping keeps the address on the current ticket (replaceState, no new entry)", r.box.location.hash === "#/approvals/c0002" && r.html().includes("Title c0002"), r.box.location.hash);
    r.view.scrollTop = 777; r.fire("scroll", { target: r.view });
    // an id link to a detail view, then Back
    r.hash("#/ticket/c0003");
    check("a detail route shows the detail view", r.html().includes("Done one") && r.box.st.view === "tickets", r.html().slice(0, 100));
    check("the detail view's badge says live, not simulated", /Ticket[^<]*: live/.test(r.badge()) && !/simulated/.test(r.badge()), r.badge());
    r.hash("#/approvals/c0002");
    check("Back returns to the same ticket in the walk", r.html().includes("Title c0002") && r.box.location.hash === "#/approvals/c0002");
    check("and to the same scroll position", r.view.scrollTop === 777, String(r.view.scrollTop));
    // a route id outside the theme filter clears it and says so
    r.fire("click", { target: { closest: sel => (sel === "[data-theme-go]" ? { dataset: { themeGo: "beta", themeProject: "p" } } : null) } });
    check("the filter shows only its theme", r.html().includes("showing theme: beta") && !r.html().includes("Title c0002"), "");
    r.hash("#/approvals/c0002");
    check("a route id outside the theme filter clears it and says so", r.html().includes("Title c0002") && /c0002 is not in theme beta/.test(r.html()) && !r.html().includes("showing theme: beta"), r.html().slice(0, 300));
    r.hash("#/approvals/c0777");
    check("a route id that no longer waits says so, never silently the first ticket", /No ticket c0777 waits for your approval/.test(r.html()), r.html().slice(0, 300));
    r.hash("#/approvals/c0003");
    check("a unit that does not wait but is in the index links to its detail view from that line", /c0003 no longer waits/.test(r.html()) && hasLink(r.html(), "#/ticket/c0003"), "");
    check("a note is cleared by stepping", (() => { r.hash("#/approvals/c0777"); const had = /No ticket c0777 waits/.test(r.html()); r.fire("click", { target: { closest: sel => (sel === "[data-ap]" ? { dataset: { ap: "next" } } : null) } }); return had && !/waits for your approval/.test(r.html()); })());
    r.hash("#/approvals/%3Cimg%20src%3Dx%20onerror%3D1%3E");
    check("a hostile route id is escaped in the note", !r.html().includes("<img") && r.html().includes("&lt;img"));
    r.fire("click", { target: { closest: sel => (sel === "[data-theme-go]" ? { dataset: { themeGo: HOSTILE, themeProject: "" } } : null) } });
    {
      const odd = JSON.parse(JSON.stringify(APPROVALS));
      odd.themes[1].rafts[0].tickets[0].id = HOSTILE;
      r.routes["/api/approvals"] = { body: ok(odd) };
      r.event(); await flush();
      r.fire("click", { target: { closest: sel => (sel === "[data-theme-go]" ? { dataset: { themeGo: "alpha", themeProject: "" } } : null) } });
      r.hash("#/approvals/" + encodeURIComponent(HOSTILE));
      check("a hostile ticket id of the facts is escaped in the cleared note", !r.html().includes("<img") && /is not in theme alpha/.test(r.html()) && r.html().includes("&lt;img"), r.html().slice(0, 200));
      r.routes["/api/approvals"] = { body: ok(APPROVALS) };
      r.event(); await flush();
    }
    r.fire("click", { target: { closest: sel => (sel === "[data-theme-go]" ? { dataset: { themeGo: HOSTILE, themeProject: "" } } : null) } });
    r.hash("#/approvals/c0001");
    check("a hostile theme name is escaped in the cleared note", !r.html().includes("<img") && /is not in theme/.test(r.html()) && r.html().includes("&lt;img"));
    r.hash("#/approvals/..%2F..");
    check("a hostile route id is shown as text, never as a link", !r.html().includes("<img") && tagsOf(r.html()).every(h => !h.includes("..")), "");
    // the browser never gets a route it did not build
    r.hash("#/ticket/%3Cimg%20src%3Dx%3E");
    check("a hostile detail route says no such unit and escapes it", !r.html().includes("<img") && /No unit/.test(r.html()), r.html().slice(0, 200));
    check("no click handler or request records anything", !/method\s*:|XMLHttpRequest|sendBeacon/.test(code));
  }

  /* ---------- review round 2 */
  {
    const route = /^#\/(?:(?:ticket|raft|approvals)\/(?:[cfd]\d{4}|R\d{4})|tributary\/[a-z0-9][a-z0-9-]{0,63}|themes|approvals)$/;
    const EV = 'javascript:alert(1)//"><x>';
    const hostileUnits = { version: 1, at: 1000, sig: "h", dropped: 0, withdrawn_cut: 0, units: [
      unitRow({ id: EV, title: "t", tributary: EV, themes: [EV], raft: EV, depends_on: [EV], members: [EV] }),
      unitRow({ id: "R0010", kind: "raft", title: "r", tributary: EV, themes: [EV, "alpha"], members: [EV, "c0001"], depends_on: [EV], raft: EV }),
      unitRow({ id: "c0001", title: "one", tributary: EV, themes: [EV], raft: "R0010", depends_on: [EV, "R0010"], problem: "see " + EV + " and R0010", solution: "", design: [] }),
      unitRow({ id: EV, kind: "raft", title: "dup", state: "backlog" }),
    ] };
    const hostileApprovals = ok({ version: 2, at: 5, run: "20261122T010203Z-a1b2", scope: "", themes: [{ id: EV, title: EV, purpose: "", rafts: [{ id: EV, title: EV, single: false, themes: [EV], tickets: [tk(EV), tk("c0001")] }] }] });
    const hostileThemes = { state: "ok", facts: { version: 1, at: 900, live: true, commit: "", approvalsScope: "", themes: [{ id: EV, project: "p", title: EV, purpose: EV, counts: { done: 0, flight: 0, approval: 0, owner: 0, open: 0 }, workers: [], units: [{ id: EV, title: EV, stage: "code", phase: "flight", holder: "", ids: [EV] }] }] } };
    const un = { resp: ok(hostileUnits) };
    const views = [
      A.view({ resp: hostileApprovals, err: null, idx: 0, stage: "design", msg: "", themes: hostileThemes, units: un, now: 1300000 }),
      A.view({ resp: hostileApprovals, err: null, idx: 1, stage: "design", msg: "", themes: hostileThemes, units: un, now: 1300000 }),
    ];
    for (const [kind, id] of [["ticket", EV], ["ticket", "c0001"], ["raft", "R0010"], ["raft", EV], ["tributary", EV], ["tributary", "alpha"]]) views.push(D.view({ kind, id, units: un, approvals: hostileApprovals, themes: hostileThemes, state: STATE, now: 1300000 }));
    const bad = views.flatMap(v => tagsOf(v)).filter(h => !route.test(h));
    check("F1: every href of every view is a route shape although the hostile ids ARE in the index, the approval facts and the theme facts", bad.length === 0, bad.slice(0, 3).join(" | "));
    check("F1: and the hostile text is escaped in all of them", views.every(v => !/<x>/.test(v) && !/<img/.test(v)));
    check("F1: no interactive element sits inside another in any of them", views.every(v => interactive(v).length === 0));
    const runView = A.view({ resp: ok({ version: 2, at: 5, run: HOSTILE, scope: "", themes: APPROVALS.themes }), err: null, idx: 0, stage: "design", msg: "", themes: null, units: null, now: 1 });
    check("the run of the approval facts is escaped wherever it is shown", !runView.includes("<img") && runView.includes("&lt;img"), runView.slice(0, 100));
    const scope = A.view({ resp: ok({ version: 2, at: 5, run: "r", scope: HOSTILE, themes: [] }), err: null, idx: 0, stage: "design", msg: "", themes: null, units: null, now: 1 });
    check("F1: a hostile scope of the approval facts is escaped", !scope.includes("<img") && scope.includes("&lt;img"), scope.slice(0, 200));
  }
  /* F3: ages are live spans and no age sits in a tooltip */
  {
    const un = { resp: ok(UNITS) };
    const at = now => D.view({ kind: "ticket", id: "c0001", units: un, approvals: ok(APPROVALS), themes: { state: "ok", facts: THEMES }, state: STATE, now });
    const v1 = at(1300 * 1000), v2 = at(14000 * 1000);
    check("F3: the age of each source is a span the page's own tick updates", /<span data-lheard="1000">/.test(v1) && /<span data-lheard="5">/.test(v1) && /<span data-lheard="900">/.test(v1), v1.slice(v1.indexOf("Sources"), v1.indexOf("Sources") + 400));
    check("F3: its text moves with the clock the view is given", txtOf(v1).includes("made 5 min ago") && txtOf(v2).includes("made 216 min ago"), txtOf(v2).slice(txtOf(v2).indexOf("Sources"), txtOf(v2).indexOf("Sources") + 120));
    const w = (now) => A.view({ resp: ok(APPROVALS), err: null, idx: 0, stage: "design", msg: "", themes: { state: "ok", facts: THEMES }, units: un, now });
    const tip = h => (h.match(/title="[^"]*"/g) || []).join("|");
    check("F3: a tooltip holds no age: the same text at any time", tip(w(1300 * 1000)) === tip(w(99999 * 1000)) && /made at [0-9:]+ PT/.test(tip(w(1300 * 1000))), tip(w(1300 * 1000)));
  }
  /* F4: what was left out is said */
  {
    const mk = (dropped, cut) => ({ resp: ok(Object.assign({}, UNITS, { dropped, withdrawn_cut: cut })) });
    const walk = u => A.view({ resp: ok(APPROVALS), err: null, idx: 0, stage: "design", msg: "", themes: { state: "ok", facts: THEMES }, units: u, now: 1300000 });
    const det = u => D.view({ kind: "ticket", id: "c0001", units: u, approvals: ok(APPROVALS), themes: { state: "ok", facts: THEMES }, state: STATE, now: 1300000 });
    for (const [name, f] of [["walk", walk], ["detail", det]]) {
      const v = txtOf(f(mk(3, 7)));
      check("F4: " + name + " says 3 units were not understood and left out", v.includes("3 units of the index were not understood and are left out"), v.slice(0, 200));
      check("F4: " + name + " says 7 more withdrawn ids are not listed", v.includes("7 more withdrawn ids are not listed"));
      const z = txtOf(f(mk(0, 0)));
      check("F4: " + name + " says neither when both are 0", !/not understood|not listed/.test(z));
    }
  }
  /* F5: sizes, omitted parts, empty parts */
  {
    const u = unitRow({ id: "c0001", title: "T", problem: "p".repeat(500), solution: "short", problem_size: 900, solution_size: 5, clipped: true, design: [{ heading: "A", text: "a".repeat(100), size: 100 }, { heading: "B", text: "b".repeat(50), size: 200 }, { heading: "C", text: "", size: 300 }, { heading: "D", text: "", size: 0 }, { heading: "E", text: "", size: 40 }] });
    const v = txtOf(D.view({ kind: "ticket", id: "c0001", units: { resp: ok(Object.assign({}, UNITS, { units: [u] })) }, approvals: null, themes: null, state: STATE, now: 1300000 }));
    check("F5: a clipped part says first N of M bytes", v.includes("first 500 of 900 bytes") && v.includes("first 50 of 200 bytes"), v.slice(0, 600));
    check("F5: a whole part says nothing about a clip", !/first 100 of 100|first 5 of 5/.test(v));
    check("F5: omitted parts are counted with their bytes", v.includes("2 more parts not shown (340 bytes)"), v.slice(-400));
    check("F5: an empty part says empty, and nothing says 500 characters of each part", /D\s*empty/.test(v) && !v.includes("500 characters of each part") && !v.includes("not shown here"), v.slice(0, 700));
  }
  /* F9 and F11: what became of a removed id; an id that never waited */
  {
    const stubs = [unitRow({ id: "c0261", state: "withdrawn", when: "2026-11-02", subject: "tracker: withdraw c0261", fate: "withdrawn" }), unitRow({ id: "c0090", state: "withdrawn", when: "2026-10-05", subject: "tracker: compact ids (#64)", fate: "renumbered", to: "c0001" }), unitRow({ id: "c0460", state: "withdrawn", when: "2026-09-01", subject: "fold c0460", fate: "removed" })];
    const un = { resp: ok(Object.assign({}, UNITS, { units: UNITS.units.filter(x => x.state !== "withdrawn").concat(stubs) })) };
    const sv = id => D.view({ kind: "ticket", id, units: un, approvals: ok(APPROVALS), themes: null, state: STATE, now: 1300000 });
    check("F9: only a subject that says so is called withdrawn", /Withdrawn on 2026-11-02/.test(txtOf(sv("c0261"))) && !/Withdrawn/.test(txtOf(sv("c0460"))) && /Removed on 2026-09-01/.test(txtOf(sv("c0460"))));
    check("F9: a renumbered id says where it went, with a link", /Renumbered to c0001/.test(txtOf(sv("c0090"))) && hasLink(sv("c0090"), "#/approvals/c0001"), txtOf(sv("c0090")).slice(0, 200));
  }
  /* F12: a hostile index never throws; a prototype word is no state; duplicates are first-wins and counted */
  {
    let threw = 0, runs = 0, first = "";
    const junk = [null, 5, true, {}, [], "constructor", "__proto__", { a: 1 }, [null], [{}]];
    const unitKeys = ["id", "kind", "title", "project", "state", "tributary", "themes", "raft", "members", "depends_on", "problem", "solution", "design", "clipped", "when", "subject", "fate", "to", "problem_size", "solution_size"];
    const factKeys = ["at", "commit", "sig", "dropped", "withdrawn_cut", "units"];
    const tryView = facts => { runs++; try { A.view({ resp: ok(APPROVALS), err: null, idx: 0, stage: "design", msg: "", themes: { state: "ok", facts: THEMES }, units: { resp: { state: "ok", facts } }, now: 1300000 }); for (const [k, i] of [["ticket", "c0001"], ["raft", "R0010"], ["ticket", "c0261"], ["tributary", "alpha"]]) D.view({ kind: k, id: i, units: { resp: { state: "ok", facts } }, approvals: ok(APPROVALS), themes: { state: "ok", facts: THEMES }, state: STATE, now: 1300000 }); } catch (e) { threw++; first = first || String(e && e.stack || e).slice(0, 200); } };
    for (const k of unitKeys) for (const j of junk) for (const idx of [0, 4, 6]) { const f = JSON.parse(JSON.stringify(UNITS)); f.units[idx][k] = j; tryView(f); }
    for (const k of factKeys) for (const j of junk) { const f = JSON.parse(JSON.stringify(UNITS)); f[k] = j; tryView(f); }
    tryView({ units: [null, 5, "x", [], {}] });
    check("F12: " + runs + " type-confused indexes never throw", threw === 0, threw + " threw: " + first);
    const proto = D.view({ kind: "ticket", id: "c0001", units: { resp: ok(Object.assign({}, UNITS, { units: [unitRow({ id: "c0001", title: "t", state: "constructor", problem: "SECRET-PREVIEW", solution: "", design: [] })] })) }, approvals: null, themes: null, state: STATE, now: 1300000 });
    check("F12: a state named like an object property is not open and has no words of its own", !proto.includes("SECRET-PREVIEW") && !/function|\[native/.test(proto), proto.slice(0, 300));
    const dup = { resp: ok(Object.assign({}, UNITS, { units: UNITS.units.concat([unitRow({ id: "c0001", title: "SECOND" })]) })) };
    const dv = D.view({ kind: "ticket", id: "c0001", units: dup, approvals: null, themes: null, state: STATE, now: 1300000 });
    check("F12: a duplicate id: the first wins and one is counted", dv.includes("Open one") && !dv.includes("SECOND") && txtOf(dv).includes("1 units of the index were not understood and are left out"), txtOf(dv).slice(0, 200));
    const two = D.view({ kind: "tributary", id: "alpha", units: { resp: ok(Object.assign({}, UNITS, { units: [unitRow({ id: "c0001", title: "InP", project: "p" }), unitRow({ id: "c0002", title: "InQ", project: "q" })] })) }, approvals: null, themes: { state: "ok", facts: { version: 1, at: 1, themes: [{ id: "alpha", project: "p", title: "alpha", purpose: "P", counts: {}, workers: [], units: [] }, { id: "alpha", project: "q", title: "alpha", purpose: "Q", counts: {}, workers: [], units: [] }] } }, state: STATE, now: 1300000 });
    check("F12: a tributary is keyed by project and name: each project's row lists its own units", /project p/.test(txtOf(two)) && /project q/.test(txtOf(two)) && two.indexOf("InP") < two.indexOf("project q") && two.indexOf("InQ") > two.indexOf("project q"), txtOf(two).slice(0, 300));
  }

  /* ---------- a big index: 5,000 units */
  {
    const many = { version: 1, at: 1, sig: "big", dropped: 0, withdrawn_cut: 0, units: Array.from({ length: 5000 }, (_, i) => unitRow({ id: "c" + String(i + 1).padStart(4, "0"), title: "Unit " + i, problem: "p", solution: "s", design: [] })) };
    const t0 = Date.now();
    const v = D.view({ kind: "tributary", id: "alpha", units: { resp: ok(many) }, approvals: ok(APPROVALS), themes: { state: "ok", facts: THEMES }, state: STATE, now: 5000 });
    check("an index of 5,000 units: the tributary view lists the first 200 of 5,000, counted", /first 200 of 5,000/.test(v) && (v.match(/<li>/g) || []).length <= 210, (v.match(/first [^<]*/) || [""])[0]);
    const x = A.view({ resp: ok(APPROVALS), err: null, idx: 0, stage: "design", msg: "", themes: { state: "ok", facts: THEMES }, units: { resp: ok(many) }, now: 5000 });
    check("an index of 5,000 units links ids and finishes quickly", hasLink(x, "#/approvals/c0002") || hasLink(x, "#/ticket/c0003"), "");
    const raftBig = { version: 1, at: 1, sig: "b2", dropped: 0, withdrawn_cut: 0, units: [unitRow({ id: "R0010", kind: "raft", title: "Big", members: many.units.map(u => u.id) })].concat(many.units) };
    const rv = D.view({ kind: "raft", id: "R0010", units: { resp: ok(raftBig) }, approvals: ok(APPROVALS), themes: { state: "ok", facts: THEMES }, state: STATE, now: 5000 });
    check("a raft of 5,000 members lists the first 200 of 5,000, counted", /first 200 of 5,000/.test(rv) && (rv.match(/<li>/g) || []).length <= 210);
    check("the wall guard: 5,000 units render inside five seconds", Date.now() - t0 < 5000, String(Date.now() - t0));
  }

  process.exit(failed ? 1 : 0);
})().catch(e => { console.error("app-links crashed: " + (e && e.stack || e)); process.exit(1); });
