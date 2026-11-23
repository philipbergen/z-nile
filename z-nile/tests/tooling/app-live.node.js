"use strict";
// f0437: runs z-nile/app/live.js against a stub page. Called by app-cli.spec.luau: node app-live.node.js <z-nile/app folder>.
// Exits 0 when every case holds; prints the failing case and exits 1 otherwise.
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

// a sandbox that looks enough like the mockup's page
function sandbox(protocol, drop) {
  const els = {}, calls = { fetch: [], es: [], intervals: 0 };
  const box = {
    location: { protocol },
    console: { error() {} },
    st: { view: "workers", route: {} }, sim: { sel: "x" }, NAV: [["workers", "robot", "Workers"], ["approvals", "inbox", "Approvals"]],
    WSTATE: { working: ["c-ok", "spark", "Working"], idle: ["c-trib", "moon", "Idle"], lost: ["c-risky", "alert", "Lost"] },
    esc: eval(escLine[1]), mono: s => '<span class="mono">' + box.esc(s) + "</span>", ic: n => '<svg class="' + n + '"/>',
    fmtDur: ms => Math.floor(ms / 1000) + " s", ptTime: ms => "00:00:00", pl: (n, w) => n + " " + w + (n === 1 ? "" : "s"),
    $: () => ({ scrollTop: 0, innerHTML: "" }), $$: () => [], withFocus: f => f(), ensurePage() {}, renderDetail() {}, updateLive() {},
    queue: () => ({}), queueHtml: () => '<aside><h2 id="qph">Queue</h2></aside>',
    renderWorkers() { box.simulated = true; }, renderView() { box.viewSimulated = true; }, liveText: () => ["sim", "0"],
    fetch(u) { calls.fetch.push(u); return new Promise(() => {}); },
    EventSource: function (u) { calls.es.push(u); this.readyState = 1; },
    setInterval() { calls.intervals++; }, setTimeout() {}, addEventListener() {},
    document: {
      body: { appendChild(e) { if (e.id) els[e.id] = e; } },
      getElementById: id => els[id] || null,
      createElement: () => ({ dataset: {}, className: "", innerHTML: "", setAttribute() {} }),
      addEventListener() {},
    },
  };
  for (const d of drop || []) delete box[d];
  vm.createContext(box);
  box.globalThis = box;
  vm.runInContext(code, box);
  return { box, calls, els };
}

const HOSTILE = '"><img src=x onerror=1>';
const state = {
  seq: 3, now: 1, claims: [{ unit: HOSTILE, activity: HOSTILE, worker: HOSTILE, since: 5 }],
  workers: [
    { id: "claude-1", cli: "claude", state: "working", mode: "session", started: 1, heard: 2, can: ["code/heavy"], holds: { unit: "c0001", activity: "code", step: HOSTILE, since: 3 } },
    { id: HOSTILE, cli: HOSTILE, state: "idle", mode: HOSTILE, started: 1, heard: 2, can: [HOSTILE], holds: null },
    { id: "lost-1", cli: "grok", state: "lost", mode: "run", started: 1, heard: 2, can: [], holds: { unit: HOSTILE, activity: "code", step: HOSTILE, since: 3 } },
  ],
};

// over http: a real worker renders, hostile strings only escaped, the fetch and the stream start
{
  const { box, calls, els } = sandbox("http:");
  check("http: state is fetched", calls.fetch.length === 1 && calls.fetch[0] === "/api/state", JSON.stringify(calls.fetch));
  check("http: the event stream is opened", calls.es.length === 1 && calls.es[0] === "/api/events");
  box.renderWorkers();
  check("http: renderWorkers is replaced by the live one", box.simulated !== true);
  const R = box.LiveApp.make({ esc: box.esc, mono: box.mono, ic: box.ic, WSTATE: box.WSTATE, fmtDur: box.fmtDur, ptTime: box.ptTime, pl: box.pl, now: () => 10000 });
  const html = R.header(state) + R.body(state, null);
  check("a real worker renders", html.includes("claude-1") && html.includes("c0001") && html.includes("code/heavy") && html.includes("Working"));
  check("hostile strings never become markup", !html.includes("<img"));
  check("hostile strings appear escaped", html.includes("&quot;&gt;&lt;img src=x onerror=1&gt;"));
  const working = R.card(state.workers[0]), lostOne = R.card(state.workers[2]);
  check("a working worker's step is escaped", working.includes("(&quot;&gt;&lt;img") && !working.includes("<img"), working.slice(0, 400));
  check("a lost worker's unit and step are escaped", !lostOne.includes("<img"));
  // f0420: the account label is free text from the environment: shown on the card, and only ever as escaped text
  const labelled = Object.assign({}, state.workers[1], { account: '"><img src=x onerror=2>' });
  const labelHtml = R.card(labelled);
  check("the account label is escaped on the card", labelHtml.includes("&quot;&gt;&lt;img src=x onerror=2&gt;") && !labelHtml.includes("<img"), labelHtml.slice(0, 500));
  check("a worker with no label shows none", !R.card(Object.assign({}, state.workers[1], { account: undefined })).includes("account"));
  check("a good label is shown as the account", R.card(Object.assign({}, state.workers[1], { account: "work-2" })).includes("account work-2"));
  // f0420: a worker the daemon calls lost that holds a claim has a live process: it is shown working and quiet, never lost
  const quietHtml = R.card(Object.assign({}, state.workers[2], { state: "lost", lost_since: 9000 }));
  check("a quiet worker that holds a claim is not shown as lost", quietHtml.includes("quiet since") && !quietHtml.includes("Lost"), quietHtml.slice(0, 500));
  check("no workers says so and names the command", R.body({ workers: [], claims: [] }, null).includes("No workers are registered") && R.body({ workers: [], claims: [] }, null).includes("./zn live register"));
  check("an unreachable daemon names ./zn app", R.body(state, "x").includes("./zn app"));
  const bd = a => R.badge(Object.assign({ on: true, isWorkers: true, kind: undefined, name: "Workers", err: null, stream: true }, a));
  check("badge: workers is live", bd({}).text === "Workers: live" && bd({}).cls === "live");
  check("badge: another view is simulated", bd({ isWorkers: false, name: "Approvals" }).text === "Approvals: simulated");
  check("badge: the queue entry route is simulated", bd({ kind: "queue" }).text.endsWith("simulated"));
  check("badge: reconnecting says why", bd({ stream: false, why: "too many tabs" }).text.includes("too many tabs"));
  check("badge: unreachable names ./zn app", bd({ err: "HTTP 500" }).text.includes("./zn app"));
  check("the badge element exists and says live or reconnecting", /Workers: live/.test(els.srcbadge.innerHTML));
}

// from file: nothing is fetched, nothing is subscribed, every view says simulated
{
  const { box, calls, els } = sandbox("file:");
  check("file: no fetch", calls.fetch.length === 0);
  check("file: no event stream", calls.es.length === 0);
  check("file: badge says simulated", /Workers: simulated/.test(els.srcbadge.innerHTML), els.srcbadge.innerHTML);
  box.renderWorkers();
  check("file: the simulated renderer still runs", box.simulated === true);
}

// the mockup's function names are missing: the layer says so visibly and starts nothing
for (const gone of ["renderWorkers", "queueHtml", "NAV"]) {
  const { calls, els, box } = sandbox("http:", [gone]);
  const t = els.srcbadge && els.srcbadge.innerHTML;
  check("missing " + gone + " is reported in the badge", !!t && t.includes(gone) && t.includes("simulated"), String(t));
  check("missing " + gone + ": nothing is fetched", calls.fetch.length === 0 && calls.es.length === 0);
  check("missing " + gone + ": the result lists it", box.LiveApp.result.missing.some(m => m.startsWith(gone)));
}


const esc2 = eval(escLine[1]);
// f0437 step 4: the Approvals view. One ticket at a time in the order the facts give; Approve and Send back only show the
// command the person runs in their own terminal (the page never records anything: it has no POST and no form)
{
  const { box, calls } = sandbox("http:");
  const R = box.LiveApp.make({ esc: box.esc, mono: box.mono, ic: box.ic, WSTATE: box.WSTATE, fmtDur: box.fmtDur, ptTime: box.ptTime, pl: box.pl, now: () => 10000 });
  const A = R.approvals;
  const tk = (id, extra) => Object.assign({
    id, title: "Title " + id, why: "no approval (1 guesses)", place: "origin/main",
    idea: { problem: "P " + id, solution: "S " + id }, design: [{ heading: "Slim design", text: "D " + id }],
    guesses: [{ id: "G1", step: "design", when: "2026-11-20", open: "which way", chose: "the first", why: "simpler" }],
    reviews: [{ name: "design-review-001", verdict: "pass" }], hash: "0123456789abcdef0123456789abcdef", cost: { tokens: 1200, minutes: 14 }, links: { pr: "https://example.test/pr/1", branch: "x-branch" },
  }, extra || {});
  const facts = {
    version: 1, at: 5, run: "20261122T010203Z-a1b2", scope: "", themes: [
      { id: "alpha", title: "Alpha", purpose: "first", rafts: [{ id: "R0001", title: "Raft one", single: false, tickets: [tk("c0001"), tk("c0002")] }, { id: "R0002", title: "Raft two", single: false, tickets: [tk("c0003")] }] },
      { id: "beta", title: "Beta", purpose: "", rafts: [{ id: "c0009", title: "Alone", single: true, tickets: [tk("c0009")] }] },
    ],
  };
  const ok = { state: "ok", facts };
  const flat = A.flat(facts);
  check("approvals: flat order is theme, raft, ticket", flat.map(x => x.ticket.id).join(",") === "c0001,c0002,c0003,c0009", flat.map(x => x.ticket.id).join(","));
  check("approvals: positions", A.position(flat[1]) === "theme 1 of 2, raft 1 of 2, ticket 2 of 2", A.position(flat[1]));
  check("approvals: positions across a theme", A.position(flat[3]) === "theme 2 of 2, raft 1 of 1, ticket 1 of 1", A.position(flat[3]));
  const page = A.view({ resp: ok, err: null, idx: 1, stage: "design", msg: "" });
  for (const need of ["c0002", "P c0002", "S c0002", "Slim design", "D c0002", "G1", "which way", "the first", "simpler", "design-review-001", "pass", "example.test/pr/1", "x-branch", "theme 1 of 2"])
    check("approvals: the page shows " + need, page.includes(need), page.slice(0, 300));
  check("approvals: the outline lists every ticket", ["c0001", "c0002", "c0003", "c0009"].every(id => page.includes('data-ap-go="' + ["c0001", "c0002", "c0003", "c0009"].indexOf(id) + '"')));
  check("approvals: previous and next exist", page.includes('data-ap="prev"') && page.includes('data-ap="next"'));
  check("approvals: the first ticket has no previous", A.view({ resp: ok, err: null, idx: 0, stage: "design", msg: "" }).includes('data-ap="prev" disabled'));
  const RUN = "20261122T010203Z-a1b2";
  check("approvals: approve is the ruling form bound to the run", A.approveCmd(RUN, "c0002") === "./zn approve --ruling " + RUN + " c0002 approve" && page.includes('data-copy="./zn approve --ruling ' + RUN + ' c0002 approve"'), page.slice(-1500));
  check("approvals: approve then applies the run in the person's terminal", page.includes("./zn approve --apply " + RUN));
  const BARE = /\.\/zn approve (?:--check )?[fdc]\d{4}(?![\w])/;
  const everyView = [page, A.view({ resp: ok, err: null, idx: 0, stage: "code", msg: "x" }), A.view({ resp: ok, err: null, idx: 3, stage: "idea", msg: "" })];
  check("approvals: a bare ./zn approve <id> is never produced", everyView.every(h => !BARE.test(h)) && A.approveCmd("not a run", "c0001") === null && A.approveCmd(RUN, "c0001; rm") === null, everyView.map(h => (BARE.exec(h) || [""])[0]).join("|"));
  check("approvals: the contract hash is shown short", page.includes("contract 0123456789ab") && !page.includes("0123456789abcdef0123456789abcdef"), page.slice(0, 200));
  check("approvals: what you approve is what the terminal shows", page.includes("what you approve is what the terminal shows"));
  check("approvals: a scoped queue says what it shows", A.view({ resp: { state: "ok", facts: Object.assign({}, facts, { scope: "R0002" }) }, err: null, idx: 0 }).includes("showing: R0002 only"));
  check("approvals: the unscoped view has no scope line", !page.includes("showing:"));
  const scopedEmpty = A.view({ resp: { state: "ok", facts: { version: 1, at: 1, run: "", scope: "c0006", themes: [] } }, err: null, idx: 0 });
  check("approvals: an empty scoped queue names its scope", scopedEmpty.includes("Nothing waits in c0006") && !scopedEmpty.includes("Nothing waits for your approval"), scopedEmpty.slice(0, 400));
  check("approvals: an uppercase run id is accepted like validRun", A.sendBackCmd("20261122T010203Z-A1B2", "c0001", "code", "x") !== null);
  const cred = A.view({ resp: { state: "ok", facts: { version: 1, at: 1, run: RUN, scope: "", themes: [{ id: "a", title: "A", purpose: "", rafts: [{ id: "c0001", title: "t", single: true, tickets: [tk("c0001", { links: { pr: "https://user:secret@example.test/pr/1", branch: "b" } })] }] }] } }, err: null, idx: 0 });
  check("approvals: a PR url with credentials is shown without them and never linked", !cred.includes("secret") && !cred.includes("user:") && cred.includes("example.test/pr/1") && !/href="https?:\/\/[^"]*example/.test(cred), cred.slice(-1200));
  check("approvals: approve says it records nothing here", /nothing is recorded/i.test(page));
  check("approvals: no form, no talk button", !page.includes("<form") && !/zn talk/.test(page) && !/data-talk/.test(page));
  const hasMsg = A.view({ resp: ok, err: null, idx: 0, stage: "code", msg: "it's \"wrong\"" });
  check("approvals: send back builds the ruling command with the quoted message", hasMsg.includes(esc2("./zn approve --ruling 20261122T010203Z-a1b2 c0001 change --stage code --note 'it'\\''s \"wrong\"'")), hasMsg.slice(-900));
  check("approvals: send back with no message copies nothing", A.sendBackCmd("20261122T010203Z-a1b2", "c0001", "code", "  ") === null);
  check("approvals: send back with a bad stage copies nothing", A.sendBackCmd("20261122T010203Z-a1b2", "c0001", "deploy", "x") === null);
  check("approvals: a bad run id gives no command", A.sendBackCmd("../x", "c0001", "code", "x") === null && A.approveCmd("c0001; rm -rf /") === null);
  check("approvals: a send back says to apply as the person", A.view({ resp: ok, err: null, idx: 0, stage: "code", msg: "x" }).includes("./zn approve --apply 20261122T010203Z-a1b2"));
  const hostile = { state: "ok", facts: { version: 1, at: 1, run: "20261122T010203Z-a1b2", themes: [{ id: HOSTILE, title: HOSTILE, purpose: HOSTILE, rafts: [{ id: HOSTILE, title: HOSTILE, single: false, tickets: [tk("c0001", { title: HOSTILE, why: HOSTILE, idea: { problem: HOSTILE, solution: HOSTILE }, design: [{ heading: HOSTILE, text: HOSTILE }], guesses: [{ id: HOSTILE, step: HOSTILE, when: HOSTILE, open: HOSTILE, chose: HOSTILE, why: HOSTILE }], reviews: [{ name: HOSTILE, verdict: HOSTILE }], links: { pr: HOSTILE, branch: HOSTILE } })] }] }] } };
  const hp = A.view({ resp: hostile, err: null, idx: 0, stage: "idea", msg: HOSTILE });
  check("approvals: hostile strings never become markup", !hp.includes("<img") && hp.includes("&lt;img"), hp.slice(0, 300));
  check("approvals: a link that is not http(s) is text, never an href", !/href="[^"]*onerror/.test(hp) && !/href="(?!https?:)/.test(hp));
  const empty = A.view({ resp: { state: "ok", facts: { version: 1, at: 1, run: "r", themes: [] } }, err: null, idx: 0 });
  check("approvals: nothing waiting says so", empty.includes("Nothing waits for your approval"));
  const absent = A.view({ resp: { state: "absent", facts: null, why: "run ./zn approve --queue" }, err: null, idx: 0 });
  check("approvals: absent facts name the command", absent.includes("./zn approve --queue") && !absent.includes("Nothing waits"));
  check("approvals: unreadable facts say why", A.view({ resp: { state: "unreadable", facts: null, why: "bad version 9" }, err: null, idx: 0 }).includes("bad version 9"));
  check("approvals: an unreachable daemon names ./zn app", A.view({ resp: null, err: "HTTP 500", idx: 0 }).includes("./zn app"));
  check("approvals: not loaded yet says loading", A.view({ resp: null, err: null, idx: 0 }).includes("Loading"));
  check("approvals: old facts show their age", A.view({ resp: ok, err: null, idx: 0, stage: "idea", msg: "" }).includes("facts read"));
  check("approvals: an out-of-range index is clamped", A.view({ resp: ok, err: null, idx: 99, stage: "idea", msg: "" }).includes("c0009"));
  const key = (k, extra) => A.keyAction(Object.assign({ key: k, target: { tagName: "BODY" } }, extra || {}));
  check("approvals: keys", key("ArrowRight") === "next" && key("j") === "next" && key("ArrowLeft") === "prev" && key("k") === "prev" && key("x") === null);
  check("approvals: keys are ignored while typing or with a modifier", key("j", { target: { tagName: "TEXTAREA" } }) === null && key("j", { target: { tagName: "SELECT" } }) === null && key("j", { metaKey: true }) === null && key("j", { ctrlKey: true }) === null);
  // the page never sends anything that changes state
  const src = fs.readFileSync(path.join(dir, "live.js"), "utf8");
  check("live.js has no request method but GET", !/method\s*:/.test(src) && !/XMLHttpRequest|sendBeacon|\.submit\(/.test(src));
  check("the Approvals view is not fetched before it is shown", calls.fetch.every(u => u === "/api/state"), JSON.stringify(calls.fetch));
  box.st.view = "approvals";
  box.renderView();
  check("renderView is replaced and fetches /api/approvals once shown", box.viewSimulated !== true && calls.fetch.includes("/api/approvals"), JSON.stringify(calls.fetch));
}

process.exit(failed ? 1 : 0);
