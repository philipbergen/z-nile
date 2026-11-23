"use strict";
/* f0437 data layer of the app page (served by the live daemon at /live.js, loaded by one <script src> in index.html).
   Over http the Workers view shows the daemon's real workers and claims (/api/state), redrawn when /api/events says
   something changed. Every other view keeps the simulation and says so in the badge. Opened from file:// nothing is fetched
   and every view says "simulated". If the mockup's global functions this layer replaces are missing, it says so in the badge
   and leaves the simulation alone.

   make(env) holds the pure renderers (state in, HTML out; every daemon string goes through env.esc). install(g) wires
   them into the page's globals. tests/tooling/app-live.node.js runs both against a stub document. */
(function (root) {
  /* ------------------------------------------------------------------ pure renderers */
  function make(env) {
    const { esc, mono, ic, WSTATE, fmtDur, ptTime, pl } = env;
    const since = sec => fmtDur(env.now() - sec * 1000);
    const pt = sec => ptTime(sec * 1000) + " PT";
    const num = n => (Number.isFinite(+n) ? +n : 0);

    const caps = w => (w.can && w.can.length
      ? w.can.map(c => '<span class="chip c-alias" title="' + esc("can deliver " + c) + '">' + esc(c) + "</span>").join("")
      : '<span class="chip c-none">no capabilities declared</span>');
    function now(w) {
      const h = w.holds;
      /* the daemon calls a worker whose process lives but who said nothing for a while "lost": nobody is lost while its process lives */
      if (w.state === "lost") {
        const q = pt(num(w.lost_since || w.heard));
        return h ? '<p class="now"><strong>Working, quiet since ' + q + ".</strong> Still holds " + mono(h.unit) + " (" + esc(h.activity) + ") since " + pt(num(h.since)) + ". Its claim frees itself after 30 minutes of silence; to free it now:  <code>./zn live release --worker " + esc(w.id) + "</code>.</p>"
          : '<p class="now"><strong>Quiet since ' + q + ".</strong> It holds nothing.</p>";
      }
      if (h) {
        return '<p class="now"><strong>Working</strong> on ' + esc(h.activity) + " for " + mono(h.unit) + (h.step ? " (" + esc(h.step) + ")" : "") + '</p><p class="elapsed">' + ic("clock") +
          '<span data-lsince="' + num(h.since) + '">' + since(num(h.since)) + "</span> so far, since " + pt(num(h.since)) + '</p><div class="bar" aria-hidden="true"><i></i></div>';
      }
      return '<p class="now"><strong>Idle</strong> and ready for work it can deliver.</p><p class="elapsed">' + ic("moon") + 'registered <span data-lsince="' + num(w.started) + '">' + since(num(w.started)) + "</span> ago, at " + pt(num(w.started)) + "</p>";
    }
    function card(w) {
      const S = WSTATE[w.state === "lost" && w.holds ? "working" : w.state] || WSTATE.idle;
      return '<li><article class="wcard s-' + esc(w.state) + '" aria-label="' + esc(w.id + ", " + S[2]) + '"><div class="wc-h"><div class="wc-id"><span class="cliav" aria-hidden="true">' + esc(String(w.cli).slice(0, 2).toUpperCase()) +
        '</span><div><h3>' + esc(w.id) + '</h3><p class="wc-cli">' + esc(w.cli + " CLI, " + w.mode + (w.account ? ", account " + w.account : "") + (w.stop ? ", asked to stop" : "")) + '</p></div></div><span class="chip ' + S[0] + '">' + ic(S[1]) + S[2] + "</span></div>" +
        now(w) + '<dl class="wmeta"><div><dt>Last heard</dt><dd><span data-lheard="' + num(w.heard) + '">' + since(num(w.heard)) + " ago</span></dd></div></dl>" +
        '<div class="caps" role="group" aria-label="What it can deliver">' + caps(w) + "</div></article></li>";
    }
    const empty = () => '<div class="lv-empty"><h2>No workers are registered.</h2><p class="muted">A worker registers when it starts. To add one by hand: <code>./zn live register --cli claude --pid &lt;pid&gt;</code>. This page updates by itself when one does.</p></div>';
    function claims(cs) {
      return '<section class="lv-claims" aria-labelledby="lvc"><h2 id="lvc">Claims <span class="count">' + cs.length + "</span></h2>" + (cs.length
        ? '<ul class="steps">' + cs.map(c => "<li><span>" + mono(c.unit) + " " + esc(c.activity) + " held by " + mono(c.worker) + '</span><span class="muted">since ' + pt(num(c.since)) + ", " + '<span data-lsince="' + num(c.since) + '">' + since(num(c.since)) + "</span></span></li>").join("") + "</ul>"
        : '<p class="muted">Nothing is claimed.</p>') + "</section>";
    }
    /* claims that expired (the worker was silent) or whose worker ended: kept as history, marked expired, with the time */
    function expired(ls) {
      ls = ls || [];
      return ls.length ? '<section class="lv-claims" aria-labelledby="lve"><h2 id="lve">Expired claims <span class="count">' + ls.length + "</span></h2>" +
        '<ul class="steps">' + ls.map(l => "<li><span><strong>Expired</strong> " + mono(l.unit) + " " + esc(l.activity) + " lost by " + mono(l.worker) + '</span><span class="muted">at ' + pt(num(l.at)) + ", " + (l.holder ? "now held by " + esc(l.holder) : "free now") + ", " + (l.told ? "worker told" : "worker not told yet") + "</span></li>").join("") + "</ul></section>" : "";
    }
    function header(state) {
      const ws = state ? state.workers : [];
      const n = s => ws.filter(w => w.state === s).length;
      const sub = state ? pl(n("working"), "worker") + " working, " + n("idle") + " idle, " + n("lost") + " lost. Every row is the live daemon's own record of registrations, claims and heartbeats." : "Waiting for the live daemon…";
      return '<div class="pg-t"><h1>Workers</h1><p class="muted">' + esc(sub) + '</p></div><div class="simbar"><span class="sim-state live"><span class="live-dot" aria-hidden="true"></span>Live</span></div>';
    }
    const UNREACHABLE = "Cannot reach the live daemon. It stopped or restarted: run ./zn app for its new address.";
    /* the part of the Workers view that is real: the cards and the claims (the queue panel beside it is still simulated) */
    function body(state, err) {
      return (err ? '<p class="lv-err" role="alert">' + esc(UNREACHABLE) + " Showing the last state it sent.</p>" : "") +
        '<section aria-label="Workers">' + (!state ? '<p class="muted">Loading…</p>' : state.workers.length ? '<ul class="wgrid">' + state.workers.map(card).join("") + "</ul>" : empty()) +
        (state ? claims(state.claims) + expired(state.losses) : "") + "</section>";
    }
    /* the badge: live (real data) or simulated, per view */
    function badge(a) {
      const name = a.name + (a.kind === "queue" ? " queue entry" : "");
      if (!a.on || !a.isWorkers || a.kind === "queue") return { cls: "", dot: false, text: name + ": simulated" };
      if (a.err) return { cls: "warn", dot: false, text: name + ": live, cannot reach the daemon (run ./zn app)" };
      if (!a.stream) return { cls: "warn", dot: false, text: name + ": live, " + (a.why || "reconnecting") };
      return { cls: "live", dot: true, text: name + ": live" };
    }
    return { card, claims, expired, header, body, badge, empty, UNREACHABLE };
  }

  /* ------------------------------------------------------------------ wiring into the page */
  const CSS = "#srcbadge{position:fixed;right:14px;bottom:14px;z-index:60;display:inline-flex;align-items:center;gap:7px;border-radius:999px;padding:5px 13px;font-size:13px;font-weight:700;border:1px solid var(--line);background:var(--surface);color:var(--text-2);box-shadow:var(--shadow);pointer-events:none}" +
    "#srcbadge.live{color:var(--ok);background:var(--ok-bg);border-color:var(--ok)}#srcbadge.warn{color:var(--back);background:var(--back-bg);border-color:var(--back)}" +
    ".srcbadge{display:inline-block;border-radius:999px;padding:1px 9px;font-size:12px;font-weight:700;border:1px solid var(--line);color:var(--text-2);vertical-align:middle}.srcbadge.sim{background:var(--surface-2)}" +
    ".lv-empty{border:1px dashed var(--line-ui);border-radius:16px;padding:18px 20px;background:var(--surface)}.lv-empty code{font-family:var(--mono);background:var(--surface-2);border-radius:6px;padding:2px 6px}" +
    ".lv-claims{margin-top:22px}.lv-err{border:1px solid var(--back);background:var(--back-bg);color:var(--back);border-radius:12px;padding:10px 14px;margin-bottom:12px;font-weight:600}";

  function install(g) {
    const doc = g.document;
    const LIVE = { on: !!g.location && (g.location.protocol === "http:" || g.location.protocol === "https:"), state: null, err: null, stream: false, why: "", busy: false, again: false };
    g.LIVE = LIVE;
    function badgeEl() {
      let b = doc.getElementById("srcbadge");
      if (!b) {
        b = doc.createElement("div"); b.id = "srcbadge"; b.setAttribute("role", "status"); doc.body.appendChild(b);
        const css = doc.createElement("style"); css.textContent = CSS; doc.body.appendChild(css);
      }
      return b;
    }
    function paint(b, cls, html) {
      if (b.className !== cls) b.className = cls;
      if (b.dataset.h !== html) { b.dataset.h = html; b.innerHTML = html; }
    }
    /* what this layer needs from the page; the first two are replaced, so they must be writable global functions */
    const present = {
      renderWorkers: typeof renderWorkers, liveText: typeof liveText, renderDetail: typeof renderDetail, ensurePage: typeof ensurePage,
      withFocus: typeof withFocus, queueHtml: typeof queueHtml, queue: typeof queue, updateLive: typeof updateLive, esc: typeof esc, mono: typeof mono,
      ic: typeof ic, pl: typeof pl, fmtDur: typeof fmtDur, ptTime: typeof ptTime, "$": typeof $, "$$": typeof $$,
      NAV: typeof NAV, st: typeof st, sim: typeof sim, WSTATE: typeof WSTATE
    };
    const missing = Object.keys(present).filter(k => present[k] === "undefined");
    for (const k of ["renderWorkers", "liveText"]) {
      const d = Object.getOwnPropertyDescriptor(g, k);
      if (present[k] !== "undefined" && !(d && d.writable)) missing.push(k + " (not a replaceable global function)");
    }
    if (missing.length) {
      const text = "Live layer not started: this page lacks " + missing.join(", ") + ". Every view is simulated.";
      paint(badgeEl(), "warn", String(text).replace(/&/g, "&amp;").replace(/</g, "&lt;"));
      if (g.console) g.console.error(text);
      return { missing };
    }
    const R = make({ esc, mono, ic, WSTATE, fmtDur, ptTime, pl, now: () => Date.now() });
    const label = v => { const n = NAV.find(x => x[0] === v); return n ? n[2] : v; };

    function updateBadge() {
      const route = st.route || {};
      const b = R.badge({ on: LIVE.on, isWorkers: st.view === "workers", kind: route.kind, name: label(st.view), err: LIVE.err, stream: LIVE.stream, why: LIVE.why });
      paint(badgeEl(), b.cls, (b.dot ? '<span class="live-dot" aria-hidden="true"></span>' : "") + esc(b.text));
    }
    const origRenderWorkers = g.renderWorkers, origLiveText = g.liveText;
    function renderLiveWorkers() {
      ensurePage("workers");
      sim.sel = null; // the worker drawer is the simulation's: it never opens over the real list
      const v = $("#view"), sc = v.scrollTop;
      withFocus(() => {
        $("#pg-h").innerHTML = R.header(LIVE.state);
        const q = queueHtml(queue()).replace('<h2 id="qph">', '<h2 id="qph"><span class="srcbadge sim">simulated</span> ');
        $("#pg-body").innerHTML = '<div class="wlayout">' + R.body(LIVE.state, LIVE.err) + q + "</div>";
        renderDetail();
      });
      v.scrollTop = sc;
    }
    g.renderWorkers = function () { if (LIVE.on) renderLiveWorkers(); else origRenderWorkers(); updateBadge(); };
    g.liveText = function () {
      if (!LIVE.on || !LIVE.state) return origLiveText();
      const n = LIVE.state.workers.filter(w => w.state === "working").length;
      return [pl(n, "worker") + " working", String(n)];
    };

    function refresh() {
      if (LIVE.busy) { LIVE.again = true; return; }
      LIVE.busy = true;
      g.fetch("/api/state", { cache: "no-store" }).then(r => (r.ok ? r.json() : Promise.reject(new Error("HTTP " + r.status)))).then(s => {
        LIVE.state = s; LIVE.err = null;
      }).catch(e => { LIVE.err = e && e.message ? e.message : String(e); }).then(() => {
        LIVE.busy = false;
        if (st.view === "workers") g.renderWorkers();
        updateLive(); updateBadge();
        if (LIVE.again) { LIVE.again = false; refresh(); }
      });
    }
    /* EventSource does not retry after an answer that is not 200 (the daemon caps the streams at 16 and answers 503), so a
       closed stream is reopened here, with a growing pause, and the badge says why */
    let delay = 1000;
    function subscribe() {
      const es = new g.EventSource("/api/events");
      es.onopen = () => { LIVE.stream = true; LIVE.why = ""; delay = 1000; updateBadge(); };
      es.onmessage = () => refresh();
      es.onerror = () => {
        LIVE.stream = false;
        if (es.readyState === 2) {
          es.close();
          LIVE.why = "the event stream was refused or closed (too many tabs, or the daemon restarted: run ./zn app); trying again in " + Math.round(delay / 1000) + " s";
          g.setTimeout(subscribe, delay);
          delay = Math.min(delay * 2, 30000);
        } else LIVE.why = "reconnecting";
        updateBadge();
      };
    }
    function tick() {
      $$("[data-lsince]").forEach(el => { const t = fmtDur(Date.now() - (+el.dataset.lsince) * 1000); if (el.textContent !== t) el.textContent = t; });
      $$("[data-lheard]").forEach(el => { const t = fmtDur(Date.now() - (+el.dataset.lheard) * 1000) + " ago"; if (el.textContent !== t) el.textContent = t; });
      updateBadge();
    }
    g.setInterval(tick, 1000);
    g.addEventListener("hashchange", () => g.setTimeout(updateBadge, 0));
    doc.addEventListener("click", () => g.setTimeout(updateBadge, 0));
    if (LIVE.on) {
      g.setInterval(refresh, 15000); // keeps "last heard" fresh: beats are not events
      subscribe();
      refresh();
    }
    updateBadge();
    return { missing: [] };
  }

  root.LiveApp = { make, install };
  root.LiveApp.result = install(root);
})(globalThis);
