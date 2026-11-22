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
    renderWorkers() { box.simulated = true; }, liveText: () => ["sim", "0"],
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

process.exit(failed ? 1 : 0);
