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
        return h ? '<p class="now"><strong>Working, quiet since ' + q + ".</strong> Still holds " + mono(h.unit) + " (" + esc(h.activity) + ") since " + pt(num(h.since)) + ". Nobody else can take it; if it is gone, free it with <code>./zn live release --worker " + esc(w.id) + "</code>.</p>"
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
        (state ? claims(state.claims) : "") + "</section>";
    }
    /* the badge: live (real data) or simulated, per view */
    function badge(a) {
      const name = a.name + (a.kind === "queue" ? " queue entry" : "");
      if (a.on && a.isThemes && !a.kind) return a.err ? { cls: "warn", dot: false, text: name + ": live, cannot reach the daemon (run ./zn app)" } : { cls: "live", dot: true, text: name + ": live" };
      if (a.on && a.isApprovals && !a.kind) return a.err ? { cls: "warn", dot: false, text: name + ": live, cannot reach the daemon (run ./zn app)" } : { cls: "live", dot: true, text: name + ": live" };
      if (!a.on || !a.isWorkers || a.kind === "queue") return { cls: "", dot: false, text: name + ": simulated" };
      if (a.err) return { cls: "warn", dot: false, text: name + ": live, cannot reach the daemon (run ./zn app)" };
      if (!a.stream) return { cls: "warn", dot: false, text: name + ": live, " + (a.why || "reconnecting") };
      return { cls: "live", dot: true, text: name + ": live" };
    }

    /* ---------------- f0437 step 5: the themes overview (the home view) and the "what is coming" strip. Both only show facts
       the engine wrote (themes.json, at the board refresh); the commands are shown for the person's own terminal and
       this page records nothing. */
    /* the shape of a tributary name (tributaries.nameOk: lowercase words joined by single hyphens), checked before a name goes into a command */
    const NAME_RE = /^(?:[a-z]|[a-z][a-z0-9-]*[a-z0-9])$/;
    const workCmd = name => (typeof name === "string" && NAME_RE.test(name) && name.indexOf("--") < 0 ? "./zn work " + name : null);
    const reviewCmd = () => "./zn approve --queue";
    const COUNTS = [["done", "done", "bar-done"], ["flight", "in flight", "bar-flight"], ["approval", "waiting for your approval", "bar-approval"], ["owner", "waiting on you for something else", "bar-owner"], ["open", "not started", "bar-open"]];
    const WHEN = "The facts are made again whenever the board is rebuilt (./zn sync, which every landing runs, or ./zn board).";
    function themeAge(f, a) {
      return '<p class="muted th-age">facts made ' + pt(num(f.at)) + " (" + fmtDur((a.now == null ? env.now() : a.now) - num(f.at) * 1000) + " ago)" + (f.commit ? ", read at commit " + mono(f.commit) : "") + ". " + esc(WHEN) + "</p>";
    }
    /* who holds a unit of this theme now, from the live claims (/api/state) joined to the unit ids the facts list; nil when the live state is not known */
    function liveHolders(th, state) {
      if (!state || !Array.isArray(state.claims)) return null;
      const ids = new Set();
      (th.units || []).forEach(u => (u.ids || [u.id]).forEach(i => ids.add(i)));
      const cli = {};
      (state.workers || []).forEach(w => { cli[w.id] = w.cli; });
      const out = [];
      state.claims.forEach(c => {
        if (ids.has(c.unit) || (c.raft && ids.has(c.raft))) { const l = (cli[c.worker] || "worker") + " " + c.worker; if (out.indexOf(l) < 0) out.push(l); }
      });
      return out.sort();
    }
    function bar(c) {
      const total = COUNTS.reduce((n, k) => n + num(c[k[0]]), 0);
      const label = COUNTS.map(k => num(c[k[0]]) + " " + k[1]).join(", ");
      if (!total) return '<div class="th-bar" role="img" aria-label="no units"><i class="bar-none" style="width:100%"></i></div>';
      return '<div class="th-bar" role="img" aria-label="' + esc(label) + '">' + COUNTS.filter(k => num(c[k[0]]) > 0).map(k => '<i class="' + k[2] + '" style="width:' + Math.round(1000 * num(c[k[0]]) / total) / 10 + '%"></i>').join("") + "</div>";
    }
    function themeRow(th, f, multi, a) {
      const c = th.counts || {}, known = f.approvalsAt != null;
      const wc = workCmd(th.id), ws = th.workers || [];
      const words = COUNTS.map(k => (k[0] === "approval" && !known ? '<li><span class="sw bar-approval" aria-hidden="true"></span>waiting for your approval: not known yet</li>'
        : '<li><span class="sw ' + k[2] + '" aria-hidden="true"></span>' + num(c[k[0]]) + " " + esc(k[1]) + "</li>")).join("");
      const ago = fmtDur((a && a.now != null ? a.now : env.now()) - num(f.at) * 1000) + " ago";
      const nowHold = liveHolders(th, a && a.state);
      const chips = l => l.map(w => '<span class="chip c-trib">' + esc(w) + "</span>").join(" ");
      const who = nowHold
        ? (nowHold.length ? chips(nowHold) : '<span class="muted">no worker holds a unit listed here now</span>') + ' <span class="muted">(live; only units the facts list are joined)</span>'
        : !f.live ? '<span class="muted">who holds what is unknown: the live layer did not answer when these facts were made, ' + esc(ago) + "</span>"
        : (ws.length ? chips(ws) : '<span class="muted">no worker holds a unit here</span>') + ' <span class="muted">(when these facts were made, ' + esc(ago) + ")</span>";
      return '<li><article class="th-row" aria-label="' + esc("Theme " + th.title) + '"><div class="th-h"><h2><button class="th-go" data-theme-go="' + esc(th.id) + '" data-theme-project="' + esc(th.project || "") + '" data-k="th-' + esc(th.id) + '">' + esc(th.title) + "</button></h2>" + (multi ? '<span class="chip c-trib" title="the project that defines this theme">' + esc(th.project) + "</span>" : "") +
        '<span class="muted th-p">' + esc(th.purpose) + "</span></div>" + bar(c) + '<ul class="th-counts">' + words + '</ul><p class="muted th-asof">These counts are as they were when these facts were made, ' + esc(ago) + ".</p>" +
        '<p class="th-who"><strong>' + (nowHold ? "Workers here now" : "Workers when the facts were made") + ':</strong> ' + who + "</p>" +
        '<div class="th-cmds"><div><h3>Work this theme</h3>' + (wc ? cmdBox(wc, "tw-" + th.id) : '<p class="muted">No command: this name is not a theme name.</p>') + "</div>" +
        "<div><h3>Review what waits</h3>" + cmdBox(reviewCmd(), "tr-" + th.id) + '<p class="muted">Then open the theme above to see its approvals.</p></div></div></article></li>';
    }
    function themesView(a) {
      const head = '<div class="pg-t"><h1>Themes</h1><p class="muted">Where everything stands, one theme at a time. Pick a theme to go through what waits for you in it.</p></div>';
      const err = a.err ? '<p class="lv-err" role="alert">' + esc(UNREACHABLE) + " Showing the last facts it sent.</p>" : "";
      const r = a.resp;
      if (!r) return head + (a.err ? err : '<p class="muted">Loading…</p>');
      if (r.state !== "ok") return head + err + '<div class="lv-empty"><h2>' + (r.state === "absent" ? "No theme facts yet." : "The theme facts cannot be read.") + '</h2><p class="muted">' + esc(r.why || "") + "</p><p>Write them in a terminal: <code>./zn board</code></p></div>";
      const f = r.facts, themes = f.themes || [];
      if (!themes.length) return head + err + '<div class="lv-empty"><h2>No themes are defined.</h2><p class="muted">A project lists its themes in tributaries.toml. ' + esc(WHEN) + "</p></div>";
      const approvals = f.approvalsAt != null
        ? "Approval counts come from the last ./zn approve --queue, read " + pt(num(f.approvalsAt)) + (f.approvalsScope ? " for " + f.approvalsScope + " only, so the counts of every other unit include units whose approval state is unknown" : "") + ": run it again to refresh them (it makes these facts again)."
        : "Approval counts are not known: no approval queue has been read yet. Run ./zn approve --queue. Until then, units that wait for your approval are counted as in flight or not started.";
      return head + err + themeAge(f, a) + '<p class="muted th-age">' + esc(approvals) + '</p><ul class="th-list">' + themes.map(th => themeRow(th, f, themes.some(o => o.project !== themes[0].project), a)).join("") + "</ul>";
    }
    function stripUnit(u) {
      const phase = u.phase === "owner" ? ' <span class="chip c-back">waiting on you (a question or a blocked idea)</span>'
        : u.phase === "claimed" ? ' <span class="chip c-wait">claimed ' + (u.claimedAt ? esc(u.claimedAt) : "(day unknown)") + ", no worker</span>" : "";
      return "<li><span>" + mono(u.id) + " " + esc(u.title) + '</span><span class="th-st"><span class="chip c-land">' + esc(u.stage) + "</span>" + phase + " " +
        (u.holder ? esc(u.holder) : '<span class="muted">no worker</span>') + (u.since != null ? ' <span class="muted">in ' + esc(u.stage) + " for " + esc(fmtDur(u.now - num(u.since) * 1000)) + "</span>" : "") + "</span></li>";
    }
    function strip(a) {
      const head = '<section class="th-strip" aria-labelledby="th-coming"><h2 id="th-coming">What is coming</h2>';
      const r = a.themes, now = a.now == null ? env.now() : a.now;
      if (!r) return head + '<p class="muted">Loading what is coming…</p></section>';
      if (r.state !== "ok") return head + '<p class="muted">What is on its way is not known: ' + esc(r.why || "no theme facts") + "</p><p>Write them in a terminal: <code>./zn board</code></p></section>";
      const f = r.facts, all = f.themes || [], shown = a.theme ? all.filter(t => t.id === a.theme && (a.project == null || a.project === "" || t.project === a.project)) : all;
      const rows = shown.filter(t => (t.units || []).length);
      const age = themeAge(f, { now });
      if (!rows.length) {
        const pick = a.theme ? [a.theme] : (all.filter(t => num((t.counts || {}).open) > 0).map(t => t.id).concat(all.map(t => t.id))).filter((v, i, arr) => arr.indexOf(v) === i).slice(0, 3);
        const cmds = pick.map(workCmd).filter(Boolean).map((c, i) => cmdBox(c, "st-" + i)).join("");
        return head + "<p>Nothing is on its way" + (a.theme ? " in theme " + esc(a.theme) : "") + ": no unit is in flight and none waits on you for something else. " +
          (cmds ? "To start a worker " + (a.theme ? "on this theme" : "on a theme") + ", run this in a terminal of your own:</p>" + cmds : "</p>") + age + "</section>";
      }
      return head + '<p class="muted">Units on their way to you, not there yet: in flight, or waiting on you for something other than approval.</p>' + rows.map(t =>
        "<h3>" + esc(t.title) + '</h3><ul class="steps">' + t.units.map(u => stripUnit(Object.assign({ now }, u))).join("") + "</ul>").join("") + age + "</section>";
    }
    const themes = { view: themesView, workCmd, reviewCmd, COUNTS };

    /* ---------------- f0437 step 4: the Approvals view. One ticket at a time, in the order the facts give (theme, raft bottom
       first, ticket). Approve and Send back only SHOW the command the person types in their own terminal: this page sends
       nothing that changes state, because approving is the person's own act. */
    const STAGES = ["idea", "design", "code"];
    /* these two shapes are the engine's: ID_RE is store.isIssueId (four digits), RUN_RE is approverun.validRun (%x: either case); change them together */
    const ID_RE = /^[fdc]\d{4}$/, RUN_RE = /^\d{8}T\d{6}Z-[0-9a-fA-F]{4}$/;
    const shq = s => "'" + String(s).replace(/'/g, "'\\''") + "'";
    /* Approve is the RULING form bound to the run (its queue hash, checked again by --apply), never a bare ./zn approve <id>, which records at once with no check */
    const approveCmd = (run, id) => (RUN_RE.test(String(run)) && ID_RE.test(String(id)) ? "./zn approve --ruling " + run + " " + id + " approve" : null);
    function sendBackCmd(run, id, stage, msg) {
      const note = String(msg == null ? "" : msg).replace(/\s+/g, " ").trim();
      if (!RUN_RE.test(String(run)) || !ID_RE.test(String(id)) || STAGES.indexOf(stage) < 0 || !note) return null;
      return "./zn approve --ruling " + run + " " + id + " change --stage " + stage + " --note " + shq(note);
    }
    function flat(facts) {
      const out = [], themes = (facts && facts.themes) || [];
      themes.forEach((th, ti) => (th.rafts || []).forEach((rf, ri) => (rf.tickets || []).forEach((tk, ki) => out.push({
        theme: th, raft: rf, ticket: tk, themeN: ti + 1, themes: themes.length, raftN: ri + 1, rafts: th.rafts.length, ticketN: ki + 1, tickets: rf.tickets.length }))));
      return out;
    }
    /* the facts of one theme (all of them when no theme is asked for), so positions and the outline count only what is shown */
    /* the rafts of one theme: a raft belongs to its own theme and every one its members name (raft.themes), the one rule the overview counts by; project and name key a theme */
    const scoped = (facts, theme, project) => {
      if (!theme || !facts) return facts;
      const all = facts.themes || [], rafts = [];
      const here = t => project == null || project === "" || t.project == null || t.project === project;
      all.forEach(t => { if (here(t)) (t.rafts || []).forEach(r => { if ((Array.isArray(r.themes) && r.themes.length ? r.themes : [t.id]).indexOf(theme) >= 0) rafts.push(r); }); });
      const home = all.find(t => t.id === theme && here(t)) || { id: theme, title: theme, purpose: "", project: project || "" };
      return Object.assign({}, facts, { themes: rafts.length ? [Object.assign({}, home, { rafts })] : [] });
    };
    const position = x => "theme " + x.themeN + " of " + x.themes + ", raft " + x.raftN + " of " + x.rafts + ", ticket " + x.ticketN + " of " + x.tickets;
    function keyAction(e) {
      if (e.metaKey || e.ctrlKey || e.altKey) return null;
      const tag = e.target && e.target.tagName;
      if (tag === "TEXTAREA" || tag === "INPUT" || tag === "SELECT") return null;
      if (e.key === "ArrowRight" || e.key === "j") return "next";
      if (e.key === "ArrowLeft" || e.key === "k") return "prev";
      return null;
    }
    const nl = t => esc(t).replace(/\n/g, "<br>");
    /* a url with credentials is shown without them and never linked */
    const link = u => {
      const m = /^(https?:\/\/)([^\/?#]*@)?(.*)$/.exec(String(u));
      if (!m) return esc(u);
      if (m[2]) return esc(m[1] + m[3]);
      return '<a href="' + esc(u) + '" rel="noreferrer noopener">' + esc(u) + "</a>";
    };
    const nf = n => (Number.isFinite(+n) ? Math.round(+n).toLocaleString("en-US") : "0");
    function cmdBox(cmd, what) {
      return '<div class="ap-cmd"><code>' + esc(cmd) + '</code><button class="btn sm" data-copy="' + esc(cmd) + '" data-k="copy-' + esc(what) + '">Copy</button></div>';
    }
    function sendBackBlock(a, tk, run) {
      const cmd = sendBackCmd(run, tk.id, a.stage, a.msg);
      return cmd
        ? "<p>Copy this, paste it in a terminal of your own, then apply it there:</p>" + cmdBox(cmd, "sb") + "<p class=\"muted\">Then run <code>./zn approve --apply " + esc(run) + "</code> and answer its question. The ruling is only words until you do.</p>"
        : '<p class="muted">' + (run ? "Choose where it goes back to and write what to change; the command appears here." : "There is no approval run yet: run <code>./zn approve --queue</code> first.") + "</p>";
    }
    function ticketHtml(x, a, run) {
      const tk = x.ticket, ap = approveCmd(run, tk.id);
      const guess = g => '<li class="ap-card"><h4>' + esc(g.id) + ' <span class="muted">(' + esc(g.step) + ", " + esc(g.when) + ')</span></h4><dl><dt>What was open</dt><dd>' + nl(g.open) + "</dd><dt>What was chosen</dt><dd>" + nl(g.chose) + "</dd><dt>Why</dt><dd>" + nl(g.why) + "</dd></dl></li>";
      const rv = tk.reviews || [];
      const cost = tk.cost ? nf(tk.cost.tokens) + " tokens, " + nf(tk.cost.minutes) + " min" : "no cost recorded";
      const links = [tk.links && tk.links.pr ? "pull request " + link(tk.links.pr) : "", tk.links && tk.links.branch ? "branch " + mono(tk.links.branch) : ""].filter(Boolean);
      return '<p class="muted ap-crumb">' + esc(x.theme.title) + " &rsaquo; " + esc(x.raft.single ? "on its own" : x.raft.id + " " + x.raft.title) + " &rsaquo; <strong>" + esc(position(x)) + "</strong></p>" +
        "<h2>" + mono(tk.id) + " " + esc(tk.title) + '</h2><p><span class="chip c-wait">' + esc(tk.why) + '</span> <span class="muted">read at ' + esc(tk.place) + ", contract " + esc(String(tk.hash || "-").slice(0, 12)) + "</span></p>" +
        '<section class="ap-sec" aria-labelledby="ap-idea"><h3 id="ap-idea">The idea</h3><h4>Problem</h4><p>' + nl(tk.idea.problem || "(none written)") + "</p><h4>Solution</h4><p>" + nl(tk.idea.solution || "(none written)") + "</p></section>" +
        '<section class="ap-sec" aria-labelledby="ap-design"><h3 id="ap-design">The design</h3>' + ((tk.design || []).length ? tk.design.map(d => "<h4>" + esc(d.heading) + "</h4><p>" + nl(d.text) + "</p>").join("") : '<p class="muted">No design text yet.</p>') + "</section>" +
        '<section class="ap-sec" aria-labelledby="ap-guess"><h3 id="ap-guess">Guesses <span class="count">' + (tk.guesses || []).length + '</span></h3>' + ((tk.guesses || []).length ? '<ul class="ap-cards">' + tk.guesses.map(guess).join("") + "</ul>" : '<p class="muted">No guesses were recorded.</p>') + "</section>" +
        '<section class="ap-sec" aria-labelledby="ap-rev"><h3 id="ap-rev">Reviews, cost and links</h3>' +
        (rv.length ? '<ul class="steps">' + rv.map(r => "<li><span>" + esc(r.name) + '</span><span class="chip c-trib">' + esc(r.verdict) + "</span></li>").join("") + "</ul>" : '<p class="muted">No review rounds are recorded in this folder.</p>') +
        "<p>Cost: " + esc(cost) + ".</p><p>" + (links.length ? links.join(", ") : '<span class="muted">No pull request or branch yet.</span>') + "</p></section>" +
        '<section class="ap-sec ap-decide" aria-labelledby="ap-dec"><h3 id="ap-dec">Your ruling</h3>' +
        "<h4>Approve</h4><p>Run these in a terminal of your own. Nothing is recorded by this page: approving is yours alone. The first writes your ruling; the second asks you, shows the title and the guesses, and refuses if the contract changed since this queue.</p>" +
        (ap ? cmdBox(ap, "ap") + "<p>Then <code>./zn approve --apply " + esc(run) + "</code></p>" : '<p class="muted">There is no approval run yet: run <code>./zn approve --queue</code> first.</p>') +
        '<p class="muted">This page is display only: what you approve is what the terminal shows. Compare the contract hash above with the line <code>--apply</code> prints before you answer y.</p>' +
        '<h4>Send back</h4><div class="ap-sb"><label for="ap-stage">Back to</label> <select id="ap-stage" data-k="ap-stage">' + STAGES.map(s => '<option value="' + s + '"' + (a.stage === s ? " selected" : "") + ">" + s + "</option>").join("") + "</select>" +
        '<label for="ap-msg">What to change (required)</label><textarea id="ap-msg" data-k="ap-msg" rows="3">' + esc(a.msg || "") + '</textarea><div id="ap-sbcmd">' + sendBackBlock(a, tk, run) + "</div></div></section>";
    }
    function approvalsView(a) {
      const head = '<div class="pg-t"><h1>Approvals</h1><p class="muted">One ticket at a time: a theme, then a raft (the bottom of a stack first), then a ticket.</p></div>';
      const err = a.err ? '<p class="lv-err" role="alert">' + esc(UNREACHABLE) + " Showing the last facts it sent.</p>" : "";
      const r = a.resp, coming = strip({ themes: a.themes, theme: a.theme, project: a.project, now: a.now });
      if (!r) return head + (a.err ? err : '<p class="muted">Loading…</p>');
      if (r.state !== "ok") return head + err + coming + '<div class="lv-empty"><h2>' + (r.state === "absent" ? "No approval facts yet." : "The approval facts cannot be read.") + '</h2><p class="muted">' + esc(r.why || "") + "</p><p>Ask for them in a terminal: <code>./zn approve --queue</code></p></div>";
      const list = flat(scoped(r.facts, a.theme, a.project));
      const scope = r.facts.scope ? String(r.facts.scope) : "";
      const themeLine = a.theme ? '<p class="lv-err" role="status"><strong>showing theme: ' + esc(a.theme) + '</strong>. <button class="btn sm" data-theme-go="" data-k="th-all">Show every theme</button></p>' : "";
      const sub = "facts read " + pt(num(r.facts.at)) + (r.facts.run ? ", run " + r.facts.run : "") + ". They were read when that command last ran; run it again to refresh.";
      if (!list.length && a.theme && scope) return head + err + themeLine + coming + '<div class="lv-empty"><h2>These approval facts do not cover theme ' + esc(a.theme) + '.</h2><p class="muted">They were made for ' + esc(scope) + ' only, so they say nothing about this theme. Refresh them for everything: <code>./zn approve --queue</code>. ' + esc(sub) + "</p></div>";
      if (!list.length) return head + err + themeLine + coming + '<div class="lv-empty"><h2>' + (a.theme ? "Nothing waits in theme " + esc(a.theme) + "." : scope ? "Nothing waits in " + esc(scope) + "." : "Nothing waits for your approval.") + '</h2><p class="muted">' + (scope ? "This was a scoped queue; run ./zn approve --queue for everything. " : "") + 'When a worker finishes a ticket that needs you, run <code>./zn approve --queue</code> and it appears here. ' + esc(sub) + "</p></div>";
      const idx = Math.max(0, Math.min(list.length - 1, a.idx | 0)), x = list[idx];
      let outline = "", cur = null, curRaft = null;
      list.forEach((y, i) => {
        if (cur !== y.theme) { cur = y.theme; curRaft = null; outline += "<h3>" + esc(y.theme.title) + "</h3>"; }
        if (curRaft !== y.raft) { curRaft = y.raft; outline += "<h4>" + esc(y.raft.single ? "on its own" : y.raft.id) + "</h4>"; }
        outline += '<button class="ap-o" data-ap-go="' + i + '" data-k="apo-' + i + '"' + (i === idx ? ' aria-current="true"' : "") + ">" + esc(y.ticket.id + " " + y.ticket.title) + "</button>";
      });
      const nav = '<div class="ap-nav" role="group" aria-label="Move between tickets"><button class="btn sm" data-k="ap-prev" data-ap="prev"' + (idx === 0 ? " disabled" : "") + '>Previous</button><span class="muted">' + (idx + 1) + " of " + list.length + '. Keys: j or right arrow for next, k or left arrow for previous.</span><button class="btn sm" data-k="ap-next" data-ap="next"' + (idx === list.length - 1 ? " disabled" : "") + ">Next</button></div>";
      return head + err + themeLine + coming + (scope ? '<p class="lv-err" role="status"><strong>showing: ' + esc(scope) + ' only</strong>. This queue was made for that scope; run ./zn approve --queue for everything.</p>' : "") + '<p class="muted ap-read">' + esc(sub) + '</p><div class="ap-layout"><nav class="ap-outline" aria-label="Outline of what waits">' + outline + '</nav><div class="ap-main">' + nav + ticketHtml(x, a, r.facts.run) + "</div></div>";
    }
    const approvals = { view: approvalsView, flat, scoped, position, keyAction, approveCmd, sendBackCmd, sendBackBlock, strip, STAGES };
    return { card, claims, header, body, badge, empty, UNREACHABLE, approvals, themes };
  }

  /* ------------------------------------------------------------------ wiring into the page */
  const CSS = "#srcbadge{position:fixed;right:14px;bottom:14px;z-index:60;display:inline-flex;align-items:center;gap:7px;border-radius:999px;padding:5px 13px;font-size:13px;font-weight:700;border:1px solid var(--line);background:var(--surface);color:var(--text-2);box-shadow:var(--shadow);pointer-events:none}" +
    "#srcbadge.live{color:var(--ok);background:var(--ok-bg);border-color:var(--ok)}#srcbadge.warn{color:var(--back);background:var(--back-bg);border-color:var(--back)}" +
    ".srcbadge{display:inline-block;border-radius:999px;padding:1px 9px;font-size:12px;font-weight:700;border:1px solid var(--line);color:var(--text-2);vertical-align:middle}.srcbadge.sim{background:var(--surface-2)}" +
    ".lv-empty{border:1px dashed var(--line-ui);border-radius:16px;padding:18px 20px;background:var(--surface)}.lv-empty code{font-family:var(--mono);background:var(--surface-2);border-radius:6px;padding:2px 6px}" +
    ".ap-layout{display:grid;grid-template-columns:minmax(180px,260px) minmax(0,1fr);gap:22px;align-items:start}@media(max-width:880px){.ap-layout{grid-template-columns:minmax(0,1fr)}}.ap-main{min-width:0;overflow-wrap:anywhere}.ap-main pre,.ap-main code{max-width:100%}.ap-main pre{overflow-x:auto;overflow-wrap:normal}.ap-sec p,.ap-card dd,.ap-crumb{overflow-wrap:anywhere}" +
    ".ap-outline{position:sticky;top:0;max-height:calc(100vh - 160px);overflow:auto;border:1px solid var(--line);border-radius:14px;background:var(--surface);padding:10px}.ap-outline h3{font-size:13px;margin:10px 4px 2px;color:var(--text)}.ap-outline h4{font-size:12px;margin:6px 4px 2px;color:var(--text-2);font-weight:600}" +
    ".ap-o{display:block;width:100%;text-align:left;border:0;border-radius:8px;background:transparent;color:var(--text);padding:5px 8px;font:inherit;font-size:13px;cursor:pointer}.ap-o:hover{background:var(--surface-2)}.ap-o[aria-current=true]{background:var(--tint);font-weight:700;box-shadow:inset 3px 0 0 var(--accent)}" +
    ".ap-nav{display:flex;align-items:center;gap:12px;margin-bottom:10px}.ap-nav .muted{flex:1;font-size:13px}.ap-sec{margin:18px 0;border-top:1px solid var(--line-soft);padding-top:8px}.ap-sec h4{margin:10px 0 2px;font-size:14px}" +
    ".ap-cards{list-style:none;margin:0;padding:0;display:grid;gap:10px}.ap-card{border:1px solid var(--line);border-radius:14px;background:var(--surface);padding:10px 14px}.ap-card h4{margin:0 0 6px}.ap-card dt{font-weight:700;font-size:13px;color:var(--text-2)}.ap-card dd{margin:0 0 6px}" +
    ".ap-cmd{display:flex;gap:10px;align-items:center;border:1px solid var(--line);border-radius:10px;background:var(--surface-2);padding:8px 10px;margin:6px 0}.ap-cmd code{flex:1;font-family:var(--mono);font-size:13px;overflow-wrap:anywhere;color:var(--text)}" +
    ".ap-main a{color:var(--accent);text-decoration:underline}.ap-sb{display:grid;gap:6px}.ap-sb textarea,.ap-sb select{font:inherit;color:var(--text);background:var(--surface);border:1px solid var(--line-ui);border-radius:10px;padding:6px 8px}.ap-read{margin:0 0 10px}" +
    ".th-list{list-style:none;margin:0;padding:0;display:grid;gap:14px}.th-row,.th-strip{overflow-wrap:anywhere;min-width:0}@media(max-width:520px){.th-row{padding:12px}.th-cmds{grid-template-columns:minmax(0,1fr)}.th-h h2{font-size:18px}}.th-row{border:1px solid var(--line);border-radius:16px;background:var(--surface);padding:14px 16px}.th-h{display:flex;align-items:baseline;gap:12px;flex-wrap:wrap}.th-h h2{margin:0;font-size:20px}.th-go{border:0;background:transparent;color:var(--accent);font:inherit;font-weight:700;text-decoration:underline;cursor:pointer;padding:0}.th-p{font-size:14px}" +
    ".th-bar{display:flex;gap:2px;height:10px;margin:10px 0 8px;border-radius:999px;overflow:hidden;background:var(--surface)}.th-bar i{display:block;height:100%}.bar-done{background:var(--ok)}.bar-flight{background:var(--land)}.bar-approval{background:var(--wait)}.bar-owner{background:var(--back)}.bar-open{background:var(--line-ui)}.bar-none{background:var(--line)}" +
    ".th-counts{list-style:none;margin:0 0 8px;padding:0;display:flex;flex-wrap:wrap;gap:4px 18px;font-size:14px}.th-counts .sw{display:inline-block;width:10px;height:10px;border-radius:3px;margin-right:6px}.th-who{margin:6px 0;font-size:14px}.th-cmds{display:grid;grid-template-columns:repeat(auto-fit,minmax(260px,1fr));gap:4px 18px}.th-cmds h3{font-size:13px;margin:8px 0 0;color:var(--text-2)}.th-age{margin:0 0 8px;font-size:13px}" +
    ".th-strip{border:1px solid var(--line);border-radius:14px;background:var(--surface);padding:10px 16px;margin:0 0 14px}.th-strip h2{margin:0 0 4px;font-size:16px}.th-strip h3{margin:8px 0 2px;font-size:14px}.th-st{display:inline-flex;flex-wrap:wrap;gap:6px;align-items:center}.th-strip code{font-family:var(--mono);background:var(--surface-2);border-radius:6px;padding:2px 6px}" +
    ".lv-claims{margin-top:22px}.lv-err{border:1px solid var(--back);background:var(--back-bg);color:var(--back);border-radius:12px;padding:10px 14px;margin-bottom:12px;font-weight:600}";

  function install(g) {
    const doc = g.document;
    const LIVE = { on: !!g.location && (g.location.protocol === "http:" || g.location.protocol === "https:"), state: null, err: null, stream: false, why: "", busy: false, again: false };
    LIVE.ap = { resp: null, err: null, idx: 0, stage: "design", msg: "", busy: false, again: false, theme: null, project: null };
    LIVE.th = { resp: null, err: null, busy: false, again: false };
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
      renderWorkers: typeof renderWorkers, renderView: typeof renderView, liveText: typeof liveText, renderDetail: typeof renderDetail, ensurePage: typeof ensurePage,
      withFocus: typeof withFocus, queueHtml: typeof queueHtml, queue: typeof queue, updateLive: typeof updateLive, esc: typeof esc, mono: typeof mono,
      ic: typeof ic, pl: typeof pl, fmtDur: typeof fmtDur, ptTime: typeof ptTime, "$": typeof $, "$$": typeof $$,
      NAV: typeof NAV, st: typeof st, sim: typeof sim, WSTATE: typeof WSTATE, parseRoute: typeof parseRoute, applyRoute: typeof applyRoute
    };
    const missing = Object.keys(present).filter(k => present[k] === "undefined");
    for (const k of ["renderWorkers", "renderView", "liveText", "parseRoute"]) {
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
      const b = R.badge({ on: LIVE.on, isWorkers: st.view === "workers", isApprovals: st.view === "approvals", isThemes: st.view === "themes", kind: route.kind, name: label(st.view), err: st.view === "approvals" ? LIVE.ap.err : st.view === "themes" ? LIVE.th.err : LIVE.err, stream: LIVE.stream, why: LIVE.why });
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


    /* ---- f0437 step 4: Approvals. The view is replaced only over http; from file: the mockup's simulation stays. */
    const origRenderView = g.renderView, AP = LIVE.ap, A = R.approvals;
    const msgs = {};
    const TH = LIVE.th, T = R.themes;
    const apList = () => (AP.resp && AP.resp.state === "ok" ? A.flat(A.scoped(AP.resp.facts, AP.theme, AP.project)) : []);
    const apCurrent = () => { const l = apList(); return l[Math.max(0, Math.min(l.length - 1, AP.idx | 0))]; };
    function paintApprovals() {
      if (st.view !== "approvals" || !LIVE.on) return;
      ensurePage("approvals-live");
      const x = apCurrent();
      AP.msg = x ? (msgs[x.ticket.id] || "") : "";
      const v = $("#view"), sc = v.scrollTop;
      withFocus(() => { $("#pg-h").innerHTML = ""; $("#pg-body").innerHTML = '<div class="ap-root">' + A.view({ resp: AP.resp, err: AP.err, idx: AP.idx, stage: AP.stage, msg: AP.msg, theme: AP.theme, project: AP.project, themes: TH.resp, now: Date.now() }) + "</div>"; });
      v.scrollTop = sc;
    }
    function paintThemes() {
      if (st.view !== "themes" || !LIVE.on) return;
      ensurePage("themes-live");
      const v = $("#view"), sc = v.scrollTop;
      withFocus(() => { $("#pg-h").innerHTML = ""; $("#pg-body").innerHTML = '<div class="th-root">' + T.view({ resp: TH.resp, err: TH.err, state: LIVE.state, now: Date.now() }) + "</div>"; });
      v.scrollTop = sc;
    }
    function refreshThemes() {
      if (TH.busy) { TH.again = true; return; }
      TH.busy = true;
      g.fetch("/api/themes", { cache: "no-store" }).then(r => (r.ok ? r.json() : Promise.reject(new Error("HTTP " + r.status)))).then(j => {
        TH.resp = j; TH.err = null;
      }).catch(e => { TH.err = e && e.message ? e.message : String(e); }).then(() => {
        TH.busy = false;
        paintThemes(); if (st.view === "approvals") paintApprovals(); updateBadge();
        if (TH.again) { TH.again = false; refreshThemes(); }
      });
    }
    function refreshApprovals() {
      refreshThemes(); // the strip above the ticket
      if (AP.busy) { AP.again = true; return; }
      AP.busy = true;
      const was = apCurrent();
      g.fetch("/api/approvals", { cache: "no-store" }).then(r => (r.ok ? r.json() : Promise.reject(new Error("HTTP " + r.status)))).then(j => {
        AP.resp = j; AP.err = null;
        if (was) { const at = apList().findIndex(y => y.ticket.id === was.ticket.id); if (at >= 0) AP.idx = at; }
      }).catch(e => { AP.err = e && e.message ? e.message : String(e); }).then(() => {
        AP.busy = false;
        paintApprovals(); updateBadge();
        if (AP.again) { AP.again = false; refreshApprovals(); }
      });
    }
    g.renderView = function () {
      if (LIVE.on && st.view === "approvals") { paintApprovals(); refreshApprovals(); }
      else if (LIVE.on && st.view === "themes") { paintThemes(); refreshThemes(); }
      else origRenderView();
      updateBadge();
    };
    /* the home view: an empty hash, or #/themes, is Themes; every other hash is the page's own route. Nothing changes from file:. */
    if (LIVE.on) {
      const origParse = g.parseRoute;
      g.parseRoute = function () {
        const first = String((g.location.hash || "").replace(/^#\/?/, "").split("/")[0] || "");
        return first === "" || first === "themes" ? { view: "themes", kind: null, id: null } : origParse();
      };
      NAV.unshift(["themes", "board", "Themes"]);
    }
    function move(to) { const n = apList().length; if (!n) return; AP.idx = Math.max(0, Math.min(n - 1, to)); paintApprovals(); const v = $("#view"); if (v) v.scrollTop = 0; }
    const sbBox = x => { const box = doc.getElementById("ap-sbcmd"); if (box) box.innerHTML = A.sendBackBlock({ stage: AP.stage, msg: AP.msg }, x.ticket, AP.resp.facts.run); };
    doc.addEventListener("click", e => {
      if (!LIVE.on || (st.view !== "approvals" && st.view !== "themes") || !e.target || !e.target.closest) return;
      const tgo = e.target.closest("[data-theme-go]");
      if (tgo) { AP.theme = tgo.dataset.themeGo || null; AP.project = AP.theme ? (tgo.dataset.themeProject || null) : null; AP.idx = 0; if (st.view === "approvals") paintApprovals(); else g.location.hash = "#/approvals"; return; }
      const go = e.target.closest("[data-ap-go]"), nav = e.target.closest("[data-ap]"), cp = e.target.closest("[data-copy]");
      if (go) move(+go.dataset.apGo);
      else if (nav) move(AP.idx + (nav.dataset.ap === "next" ? 1 : -1));
      else if (cp) {
        const text = cp.dataset.copy, done = ok => { cp.textContent = ok ? "Copied" : "Select the command and copy it"; };
        try { g.navigator.clipboard.writeText(text).then(() => done(true), () => done(false)); } catch (err) { done(false); }
      }
    });
    doc.addEventListener("input", e => {
      const x = apCurrent();
      if (!x || !e.target || e.target.id !== "ap-msg") return;
      msgs[x.ticket.id] = e.target.value; AP.msg = e.target.value; sbBox(x);
    });
    doc.addEventListener("change", e => {
      const x = apCurrent();
      if (!x || !e.target || e.target.id !== "ap-stage" || A.STAGES.indexOf(e.target.value) < 0) return;
      AP.stage = e.target.value; sbBox(x);
    });
    doc.addEventListener("keydown", e => {
      if (!LIVE.on || st.view !== "approvals") return;
      const w = doc.getElementById("modal");
      if (w && w.hidden === false) return;
      const act = A.keyAction(e);
      if (act) { e.preventDefault(); move(AP.idx + (act === "next" ? 1 : -1)); }
    });

    function refresh() {
      if (LIVE.busy) { LIVE.again = true; return; }
      LIVE.busy = true;
      g.fetch("/api/state", { cache: "no-store" }).then(r => (r.ok ? r.json() : Promise.reject(new Error("HTTP " + r.status)))).then(s => {
        LIVE.state = s; LIVE.err = null;
      }).catch(e => { LIVE.err = e && e.message ? e.message : String(e); }).then(() => {
        LIVE.busy = false;
        if (st.view === "workers") g.renderWorkers();
        if (st.view === "approvals") refreshApprovals();
        if (st.view === "themes") refreshThemes();
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
    /* the page's own start code ran before this script: take the home route now */
    if (LIVE.on && !String(g.location.hash || "").replace(/^#\/?/, "")) applyRoute();
    updateBadge();
    return { missing: [] };
  }

  root.LiveApp = { make, install };
  root.LiveApp.result = install(root);
})(globalThis);
