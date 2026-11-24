"use strict";
/* f0437 data layer of the app page (served by the live daemon at /live.js, loaded by one <script src> in index.html).
   Over http the Workers view shows the daemon's real workers and claims (/api/state), redrawn when /api/events says
   something changed. Every other view keeps the simulation and says so in the badge. Opened from file:// nothing is fetched
   and every view says "simulated". If the mockup's global functions this layer replaces are missing, it says so in the badge
   and leaves the simulation alone.

   make(env) holds the pure renderers (state in, HTML out; every daemon string goes through env.esc). install(g) wires
   them into the page's globals. tests/tooling/app-live.node.js runs both against a stub document. */
(function (root) {
  /* ------------------------------------------------------------------ markdown (f0437 step 6)
     Ticket text is untrusted. mdMake(esc).render(text, opt) builds HTML from a fixed set of elements only: p h3-h6 ul ol li
     strong em code pre table thead tbody tr th td blockquote hr a br div span. The only attributes are `class` (fixed words),
     `start` and `value` (digits) and `href` (an in-app route built here from an id or a name that opt.known says exists). Every
     string from the text goes through esc (after visible(), which marks invisible characters). No raw html is interpreted; an
     outside address is shown as text and is never clickable. Nothing is dropped, cut or collapsed without a visible notice. The
     bounds are step counts, not clocks, and every regular expression run on text is linear (see the review in the ticket: a
     step budget does not bound a regular expression): block expressions only see lines up to blockLine long. */
  const MD_LIMITS = { input: 400000, line: 20000, blockLine: 2000, depth: 8, emph: 256, rows: 200, cols: 40, steps: 2000000, nodes: 20000 };
  /* the colour pairs the renderer defines, as data: the css is made from them and a test checks every pair for contrast in
     both themes. `mark` is the non-colour carrier that tells the thing apart without colour. */
  const MD_RULES = [
    { sel: ".md code", color: "--text", bg: "--surface-2", css: "font-family:var(--mono);font-size:.92em;padding:0 4px;border-radius:5px;overflow-wrap:anywhere", mark: "monospace" },
    { sel: ".md pre", color: "--text", bg: "--surface-2", css: "margin:6px 0;padding:10px 12px;border:1px solid var(--line);border-radius:10px;overflow-x:auto;overflow-wrap:normal;max-width:100%;tab-size:4", mark: "a box with a border" },
    { sel: ".md th", color: "--text", bg: "--surface-2", css: "text-align:left;border:1px solid var(--line);padding:4px 8px;vertical-align:top", mark: "bold" },
    { sel: ".md-note", color: "--text", bg: "--tint", css: "margin:8px 0;border:1px dashed var(--tint-line);border-radius:10px;padding:6px 10px", mark: "dashed border and the label text" },
    { sel: ".md-label", color: "--text", bg: "--tint", css: "display:block;font-size:12px;font-weight:700;margin-bottom:2px", mark: "the words: a note hidden in the document" },
    { sel: ".md-cut", color: "--back", bg: "--back-bg", css: "margin:6px 0;border:1px solid var(--back);border-radius:8px;padding:4px 10px;font-weight:600", mark: "border and the words of the notice" },
    { sel: ".md-addr", color: "--text", bg: "--surface-2", css: "font-family:var(--mono);font-size:.9em;padding:0 4px;border-radius:5px;overflow-wrap:anywhere", mark: "parentheses and monospace" },
    { sel: ".md-lang", color: "--text-2", bg: "--surface", css: "display:block;font-size:12px;font-family:var(--mono)", mark: "the words" },
    { sel: ".md-open", color: "--text-2", bg: "--surface", css: "display:block;font-size:12px", mark: "the words" },
    { sel: ".md", color: "--text", bg: "--surface", css: "min-width:0;overflow-wrap:anywhere", mark: "text" },
    { sel: ".md a", color: "--accent", bg: "--surface", css: "text-decoration:underline", mark: "underline" },
    { sel: ".md-miss", color: "--text", bg: "--surface", css: "border-bottom:1px dotted var(--text-2);cursor:help", mark: "dotted underline and the tooltip" },
    { sel: ".md blockquote", color: "--text-2", bg: "--surface", css: "margin:6px 0;padding:2px 12px;border-left:3px solid var(--line-ui)", mark: "left bar" },
  ];
  const MD_CSS = MD_RULES.map(r => r.sel + "{color:var(" + r.color + ");" + (r.sel === ".md pre" || r.sel === ".md code" || r.sel === ".md th" || r.sel === ".md-note" || r.sel === ".md-cut" || r.sel === ".md-addr" ? "background:var(" + r.bg + ");" : "") + r.css + "}").join("") +
    ".md p{margin:6px 0}.md h3,.md h4,.md h5,.md h6{margin:12px 0 4px}.md ul,.md ol{margin:4px 0;padding-left:22px}.md li{margin:2px 0}.md hr{border:0;border-top:1px solid var(--line);margin:10px 0}" +
    ".md pre code{background:transparent;padding:0;display:block;white-space:pre}.md-scroll{max-width:100%;overflow-x:auto;margin:6px 0}.md-scroll table{border-collapse:collapse;min-width:100%}.md td{border:1px solid var(--line);padding:4px 8px;vertical-align:top;min-width:12ch;overflow-wrap:break-word}.md th{font-weight:700;min-width:12ch;overflow-wrap:break-word}.md-fence{margin:6px 0}.md-fence pre{margin:2px 0}";

  const MD_ID = /^(?:[cfd]\d{4}|R\d{4})$/;
  const MD_NAME = /^[a-z0-9][a-z0-9-]{0,63}$/;
  /* the in-app address of a unit that is an id: the walk when the unit waits for approval (G30), else its detail view; null when
     the index does not hold it. Built only from a checked id and the route word, never from text. */
  function idHref(id, known) {
    if (typeof known !== "function" || !MD_ID.test(id)) return null;
    const kind = id[0] === "R" ? "raft" : "ticket";
    if (kind === "ticket" && known("approvals", id)) return "#/approvals/" + encodeURIComponent(id);
    return known(kind, id) ? "#/" + kind + "/" + encodeURIComponent(id) : null;
  }
  /* the in-app address of a link's target, or null. A target is an id or a route word and an id or name that opt.known says
     exists; any other address (and every other `#/...`) is not an in-app link. */
  function mdHref(dest, known) {
    if (typeof known !== "function") return null;
    let word = "", key = dest;
    const m = /^#\/(ticket|raft|approvals|tributary)\/([^\/?#]+)$/.exec(dest);
    if (m) { word = m[1]; key = m[2]; }
    let id = key;
    try { id = decodeURIComponent(key); } catch (e) { return null; }
    if (MD_ID.test(id)) {
      if (word === "tributary") return null;
      const kind = id[0] === "R" ? "raft" : "ticket";
      if (word && word !== "approvals" && word !== kind) return null;
      if (!word) return idHref(id, known);
      if (!known(word === "approvals" ? "approvals" : kind, id)) return null;
      return "#/" + (word === "approvals" ? "approvals" : kind) + "/" + encodeURIComponent(id);
    }
    if (word === "tributary" && MD_NAME.test(id) && known("tributary", id)) return "#/tributary/" + encodeURIComponent(id);
    return null;
  }

  function mdMake(esc) {
    const L = MD_LIMITS;
    const OVER = { over: true };
    const hex = n => "‹U+" + n.toString(16).toUpperCase().padStart(4, "0") + "›";
    /* every invisible or default-ignorable character becomes a visible mark: text cannot reorder, hide or smuggle. Newline and tab
       stay. A joiner between two pictographs, and a variation selector after a pictograph or a keycap base, stay unmarked so
       that emoji sequences read right; anywhere else they are marked. */
    const INVIS = /[\p{Cc}\p{Cf}\p{Co}\p{Cn}\p{Cs}\p{Zl}\p{Zp}\p{Default_Ignorable_Code_Point}]/gu;
    const PICT = /^[\p{Extended_Pictographic}\u{1F3FB}-\u{1F3FF}]$/u;
    const cpBefore = (s, off) => { if (off <= 0) return -1; const lo = s.charCodeAt(off - 1); if (lo >= 0xDC00 && lo <= 0xDFFF && off >= 2) { const hi = s.charCodeAt(off - 2); if (hi >= 0xD800 && hi <= 0xDBFF) return s.codePointAt(off - 2); } return lo; };
    const cpAt = (s, off) => (off < s.length ? s.codePointAt(off) : -1);
    const isPict = cp => cp >= 0 && PICT.test(String.fromCodePoint(cp));
    /* review N7: where the browser can tell (Intl.Segmenter for grapheme clusters, the v flag for RGI_Emoji), a joiner or a variation selector
       stays unmarked only when its whole cluster is a real emoji; elsewhere the pictograph rule below is the fallback */
    const SEG = typeof Intl !== "undefined" && Intl.Segmenter ? new Intl.Segmenter(undefined, { granularity: "grapheme" }) : null;
    let RGI = null;
    try { RGI = new RegExp("^\\p{RGI_Emoji}$", "v"); } catch (e) { RGI = null; }
    const JOINERS = new RegExp("[" + String.fromCharCode(0x200D, 0xFE0F) + "]");
    function visible(s) {
      if (SEG && RGI && JOINERS.test(s)) {
        let out = "";
        for (const g of SEG.segment(s)) { const c = g.segment; out += JOINERS.test(c) && RGI.test(c) ? c : c.replace(INVIS, m => { const cc = m.codePointAt(0); return cc === 10 || cc === 9 ? m : hex(cc); }); }
        return out;
      }
      return s.replace(INVIS, (m, off) => {
        const c = m.codePointAt(0);
        if (c === 10 || c === 9) return m;
        if (c === 0x200D) {
          let p = cpBefore(s, off), back = off;
          while (p === 0xFE0F) { back -= 1; p = cpBefore(s, back); }
          if (isPict(p) && isPict(cpAt(s, off + 1))) return m;
        } else if (c === 0xFE0F) {
          const p = cpBefore(s, off);
          if (isPict(p) || ((p >= 48 && p <= 57 || p === 35 || p === 42) && cpAt(s, off + 1) === 0x20E3)) return m;
        }
        return hex(c);
      });
    }
    const decodeEntities = t => t.replace(/&(amp|lt|gt|quot|#39);/g, (_, e) => ({ amp: "&", lt: "<", gt: ">", quot: '"', "#39": "'" }[e]));
    const FENCE = /^( {0,3})(`{3,}|~{3,})(.*)$/;
    const FENCECLOSE = /^ {0,3}(`{3,}|~{3,})[ ]*$/;
    const HEAD = /^ {0,3}(#{1,6})(?:[ ]+(.*))?$/;
    const LISTMARK = /^( {0,3})([-*+]|\d{1,9}[.)])(?: |$)/;
    const QUOTE = /^ {0,3}>(?!=)/;
    const blank = s => !/\S/.test(s);
    /* a line over blockLine characters is a paragraph's text, never a block start: block expressions only see short lines */
    function leadW(l) { let c = 0; for (let i = 0; i < l.length; i++) { const ch = l[i]; if (ch === " ") c++; else if (ch === "\t") c += 4 - (c % 4); else break; } return c; }
    function norm(l) {
      if (l.indexOf("\t") < 0) return l;
      let i = 0, c = 0, out = "";
      while (i < l.length && (l[i] === " " || l[i] === "\t")) { if (l[i] === "\t") { const w = 4 - (c % 4); out += " ".repeat(w); c += w; } else { out += " "; c++; } i++; }
      return out + l.slice(i);
    }
    function stripCols(l, n) {
      let i = 0, c = 0;
      while (i < l.length && c < n) {
        const ch = l[i];
        if (ch === " ") { c++; i++; } else if (ch === "\t") { const w = 4 - (c % 4); if (c + w > n) return " ".repeat(c + w - n) + l.slice(i + 1); c += w; i++; } else break;
      }
      return l.slice(i);
    }
    /* block expressions only ever see the first blockLine characters of a line: a marker is at the start, so a long list item or
       heading is still one, and what follows the marker is cut from the whole line, not from what the expression saw */
    const bl = l => norm(l);
    const H = b => (b.length > L.blockLine ? b.slice(0, L.blockLine) : b);
    const QUOTEH = b => QUOTE.test(H(b));
    /* the window decides the KIND of a line (a list marker followed by a space), never what text it holds: the content and the
       spaces before it are read from the whole line. Returns [line, indent, marker, spaces, content] (spaces and content
       undefined for an empty item). */
    const LISTH = b => {
      const m = LISTMARK.exec(H(b));
      if (!m) return null;
      const after = b.slice(m[1].length + m[2].length);
      let sp = 0; while (sp < after.length && after[sp] === " ") sp++;
      return sp === after.length ? [b, m[1], m[2], undefined, undefined] : [b, m[1], m[2], after.slice(0, sp), after.slice(sp)];
    };
    const tailAfter = (b, m, k) => (m[k] === undefined ? "" : b.slice(H(b).length - m[k].length));
    function fenceOpen(b) {
      const m = FENCE.exec(H(b));
      if (!m) return null;
      const info = b.slice(m[1].length + m[2].length).trim(); // the whole line: the window never cuts an info string
      if (m[2][0] === "`" && info.indexOf("`") >= 0) return null;
      return { indent: m[1].length, ch: m[2][0], len: m[2].length, info };
    }
    function fenceClose(b, f) { const tb = b.trimEnd(); if (tb.length > L.blockLine) return false; const m = FENCECLOSE.exec(tb); return !!m && m[1][0] === f.ch && m[1].length >= f.len; }
    function isHr(b) {
      const m = /^ {0,3}([-*_])/.exec(b);
      if (!m) return false;
      let n = 0;
      for (let i = 0; i < b.length; i++) { const c = b[i]; if (c === m[1]) n++; else if (c !== " ") return false; }
      return n >= 3;
    }
    function isDelim(b) {
      let s = b.trim();
      if (s[0] === "|") s = s.slice(1);
      if (s.length && s[s.length - 1] === "|") s = s.slice(0, -1);
      if (!s.length) return false;
      const cells = s.split("|");
      for (const c of cells) { const t = c.trim(); if (!/^:?-+:?$/.test(t)) return false; }
      return true;
    }
    const isWord = c => c !== undefined && /[A-Za-z0-9_]/.test(c);
    const isPath = c => c !== undefined && /[\/\\.]/.test(c);

    let renders = 0;
    function render(src, opt) {
      renders++;
      opt = opt || {};
      const st = { steps: 0, nodes: 0, cuts: 0, notes: 0, flat: 0, elements: {}, free: false, longs: [] };
      const tick = n => { st.steps += n; if (!st.free && st.steps > L.steps) throw OVER; };
      const node = tag => { st.nodes++; st.elements[tag] = (st.elements[tag] || 0) + 1; if (!st.free && st.nodes > L.nodes) throw OVER; };
      const cut = msg => { st.cuts++; node("p"); return '<p class="md-cut">' + esc(msg) + "</p>"; };
      let text = String(src == null ? "" : src);
      let tail = "";
      if (text.length > L.input) {
        const cps = Array.from(text);
        if (cps.length > L.input) {
          const keep = L.input - 200;
          tail = cut("Text cut here: the first " + keep + " of " + cps.length + " characters are shown; the rest is in the ticket file.");
          text = cps.slice(0, keep).join("");
        }
      }
      text = visible(text.replace(/\r\n?/g, "\n"));
      const lines = text.split("\n");
      let at = 0; // the top-level line the current block began at
      /* ---- inline */
      /* the code spans of s, found first so that no other delimiter ever opens or closes inside one */
      function codeSpans(s) {
        const spans = [], noClose = {};
        let i = 0;
        while (i < s.length) {
          const q = s.indexOf("`", i);
          if (q < 0) break;
          let r = q; while (s[r] === "`") r++;
          tick(r - i);
          if (q > 0 && s[q - 1] === "\\") { i = q + 1; continue; }
          const n = r - q;
          if (noClose[n]) { i = r; continue; }
          let k = r, close = -1;
          while (k < s.length) {
            const x = s.indexOf("`", k);
            if (x < 0) { tick(s.length - k); break; }
            tick(x - k + 1);
            let y = x; while (s[y] === "`") y++;
            if (y - x === n) { close = x; break; }
            k = y;
          }
          if (close < 0) { noClose[n] = true; i = r; continue; }
          spans.push({ a: q, b: close + n, n, inner: s.slice(r, close) });
          i = close + n;
        }
        return spans;
      }
      function spanAt(spans, pos) {
        let lo = 0, hi = spans.length - 1;
        while (lo <= hi) { const mid = (lo + hi) >> 1; if (spans[mid].b <= pos) lo = mid + 1; else if (spans[mid].a > pos) hi = mid - 1; else return mid; }
        return -1;
      }
      /* ---- f0437 slice 2: ids and tributary names in running text. Linear: every character is ticked. An id is `[cfd]` or `R` and four
         digits, bounded on both sides by anything that is not a letter, digit or underscore (the lead's ruling, 2026-11-24, G58):
         `c0250-c0306`, `c0250/c0306`, `R0100/5/c0277`, `c0250.md` and `(c0250)` link every id. It links when opt.known says the index
         holds it, and is marked (a dotted underline and a tooltip) when it does not and opt.missing says there is an index. No id
         links inside a URL (a `scheme:` token to the next white space) or a token holding `@`, inside link text, or inside a longer
         token (`xc0250`, `c0250c0306`). Ids inside inline code link too; code keeps its text. A tributary name links only directly
         after the word tributary or theme (any case, a colon or quotes allowed), or when it is hyphenated and a theme's exactly; never
         in code (79 of 80 such links on the real tracker were ordinary words). Nothing is read into an href but a checked id or name. */
      const known = typeof opt.known === "function" ? opt.known : null;
      const isRun = c => c !== undefined && ((c >= "a" && c <= "z") || (c >= "A" && c <= "Z") || (c >= "0" && c <= "9") || c === "_" || c === "-");
      const WORDCH = /[\p{L}\p{N}\p{M}_]/u;
      const touchBefore = (s, i) => { const cp = cpBefore(s, i); return cp >= 0 && WORDCH.test(String.fromCodePoint(cp)); };
      const touchAfter = (s, j) => j < s.length && WORDCH.test(String.fromCodePoint(s.codePointAt(j)));
      const idShape = r => r.length === 5 && (r[0] === "c" || r[0] === "f" || r[0] === "d" || r[0] === "R") && r[1] >= "0" && r[1] <= "9" && r[2] >= "0" && r[2] <= "9" && r[3] >= "0" && r[3] <= "9" && r[4] >= "0" && r[4] <= "9";
      const isWs = c => c === " " || c === "\n" || c === "\t" || c === "\r";
      const SCHEMES = ["http", "https", "mailto", "file", "ftp", "sftp", "ssh", "git", "data", "javascript", "tel", "ws", "wss"];
      /* the characters of every white-space-delimited token that holds an `@`, from the start of any `scheme://` or known `scheme:` inside it
         (after any punctuation: `{https://x/c0250}`, `foo,https://...`, `URL:https://...`) to the token's end: one pass, each token read once,
         the colons of a token found while it is read. null when the text has no `@` and no `:`. The map is made once per text and handed
         down, with an offset, to emphasis and code inside it. */
      function blocked(s) {
        if (s.indexOf("@") < 0 && s.indexOf(":") < 0) return null;
        const n = s.length, m = new Uint8Array(n);
        tick(n);
        let i = 0;
        while (i < n) {
          if (isWs(s[i])) { i++; continue; }
          let j = i, at = false;
          const colons = [];
          while (j < n && !isWs(s[j])) { if (s[j] === "@") at = true; else if (s[j] === ":") colons.push(j); j++; }
          if (at) m.fill(1, i, j);
          else {
            for (const c of colons) {
              let b = c; while (b > i && c - b < 32 && /[A-Za-z0-9+.-]/.test(s[b - 1])) b--;
              if (b < c && (s.slice(c + 1, c + 3) === "//" || SCHEMES.indexOf(s.slice(b, c).toLowerCase()) >= 0)) { m.fill(1, b, j); break; }
            }
          }
          i = j;
        }
        return m;
      }
      const aTag = (href, inner) => { node("a"); return '<a href="' + esc(href) + '">' + inner + "</a>"; };
      const idHtml = (id, ctx) => {
        const href = idHref(id, known);
        if (href) return aTag(href, esc(id));
        if (typeof opt.missing === "string" && opt.missing) { node("span"); return '<span class="md-miss" title="' + esc(opt.missing) + '">' + esc(id) + "</span>"; }
        return null;
      };
      /* the word before position i inside [a, i): tributary or theme, in any case, after spaces, a colon or quotes */
      const afterWord = (s, a, i) => {
        let k = i; while (k > a && (s[k - 1] === '"' || s[k - 1] === "'")) k--;
        while (k > a && s[k - 1] === " ") k--;
        if (k > a && s[k - 1] === ":") { k--; while (k > a && s[k - 1] === " ") k--; }
        if (k === i) return false;
        let e = k; while (e > a && isRun(s[e - 1])) e--;
        tick(i - e); // the separators and the word, each read once
        const w = s.slice(e, k).toLowerCase();
        return w === "tributary" || w === "theme";
      };
      function plain(s, a, b, ctx, bm) {
        if (!known || ctx.noIds) return esc(s.slice(a, b));
        let out = "", ps = a, i = a;
        while (i < b) {
          if (!isRun(s[i])) { tick(1); i++; continue; }
          let j = i; while (j < b && isRun(s[j])) j++;
          tick(j - i);
          let p = i;
          for (let q = i; q <= j; q++) {
            if (q !== j && s[q] !== "-") continue;
            if (q - p === 5 && idShape(s.slice(p, q)) && !touchBefore(s, p) && !touchAfter(s, q) && !(bm && bm[p])) {
              const html = idHtml(s.slice(p, q), ctx);
              if (html !== null) { if (p > ps) out += esc(s.slice(ps, p)); out += html; ps = q; }
            }
            p = q + 1;
          }
          if (!ctx.idsOnly && ps <= i && j - i <= 64) {
            const run = s.slice(i, j);
            if (MD_NAME.test(run) && known("tributary", run) && !(i > 0 && isRun(s[i - 1])) && !touchBefore(s, i) && !touchAfter(s, j) && !(bm && bm[i]) && (run.indexOf("-") >= 0 || afterWord(s, a, i))) {
              if (i > ps) out += esc(s.slice(ps, i));
              out += aTag("#/tributary/" + encodeURIComponent(run), esc(run)); ps = j;
            }
          }
          i = j;
        }
        if (b > ps) out += esc(s.slice(ps, b));
        return out;
      }
      function inline(s, depth, ctx, bmIn) {
        if (s.length > L.line) { node("span"); st.longs.push(s.length); return esc(s); }
        const spans = codeSpans(s);
        const bm = bmIn !== undefined ? bmIn : known && !ctx.noIds ? blocked(s) : null;
        let out = "", i = 0, ps = 0;
        const flush = to => { if (to > ps) out += plain(s, ps, to, ctx, bm); };
        while (i < s.length) {
          tick(1);
          const c = s[i];
          if (c === "\\") {
            const n = s[i + 1];
            if (n === "\n") { flush(i); node("br"); out += "<br>"; i += 2; ps = i; continue; }
            if (n !== undefined && /[!-\/:-@\[-`{-~]/.test(n)) { flush(i); out += esc(n); i += 2; ps = i; continue; }
            i++; continue;
          }
          if (c === "\n") {
            const piece = s.slice(ps, i);
            let e = piece.length; while (e > 0 && piece[e - 1] === " ") e--;
            if (piece.length - e >= 2) { out += plain(s, ps, ps + e, ctx, bm); node("br"); out += "<br>"; } else out += plain(s, ps, i, ctx, bm) + " ";
            i++; ps = i; continue;
          }
          if (c === "`") {
            const si = spanAt(spans, i);
            if (si >= 0 && spans[si].a === i) {
              flush(i);
              const sp = spans[si];
              let code = sp.inner.replace(/\n/g, " ");
              if (code.length > 2 && code[0] === " " && code[code.length - 1] === " " && /\S/.test(code)) code = code.slice(1, -1);
              node("code");
              let cb = null;
              if (known && !ctx.noIds) {
                cb = blocked(code);
                if (bm) { const off = sp.a + sp.n + (code.length < sp.inner.length ? 1 : 0), pm = bm.subarray(off, off + code.length), merged = new Uint8Array(code.length); tick(code.length); for (let x = 0; x < code.length; x++) merged[x] = pm[x] | (cb ? cb[x] : 0); cb = merged; }
              }
              const codeHtml = "<code>" + (known && !ctx.noIds ? plain(code, 0, code.length, { idsOnly: true }, cb) : esc(code)) + "</code>";
              out += codeHtml;
              i = sp.b; ps = i; continue;
            }
            while (s[i] === "`") i++;
            continue;
          }
          if (c === "*" && depth < L.depth) {
            let j = i; while (s[j] === "*") j++;
            const run = j - i, after = s[j], before = s[i - 1];
            const canOpen = run <= 3 && after !== undefined && /\S/.test(after) && !(isWord(before) && isWord(after)) && !(isPath(before) && (isWord(after) || isPath(after)));
            if (canOpen && ctx.emph.n < L.emph) {
              ctx.emph.n++;
              let pos = j, close = -1;
              while (pos < s.length) {
                const q = s.indexOf("*", pos);
                if (q < 0) { tick(s.length - pos); break; }
                tick(q - pos + 1);
                const sp = spanAt(spans, q);
                if (sp >= 0) { pos = spans[sp].b; continue; }
                let r = q; while (s[r] === "*") r++;
                const pb = s[q - 1], na = s[r];
                if (r - q === run && q > j && /\S/.test(pb) && pb !== "\\" && !(isWord(pb) && isWord(na)) && !(isPath(pb) && (isWord(na) || isPath(na)))) { close = q; break; }
                pos = r;
              }
              if (close >= 0) {
                flush(i);
                const inner = inline(s.slice(j, close), depth + 1, ctx, bm ? bm.subarray(j, close) : bm);
                if (run === 1) { node("em"); out += "<em>" + inner + "</em>"; }
                else if (run === 2) { node("strong"); out += "<strong>" + inner + "</strong>"; }
                else { node("strong"); node("em"); out += "<strong><em>" + inner + "</em></strong>"; }
                i = close + run; ps = i; continue;
              }
            }
            i = j; continue;
          }
          if (c === "[" && !ctx.noLink) {
            let d = 0, k = i;
            for (; k < s.length; k++) {
              if (s[k] === "\\") { k++; continue; }
              if (s[k] === "[") d++;
              else if (s[k] === "]") { d--; if (d === 0) break; }
              if (d > 3) { k = s.length; break; }
            }
            tick(k - i + 1);
            if (k < s.length && s[k + 1] === "(") {
              const m = /^\(([^()\n]{0,2000})\)/.exec(s.slice(k + 1, k + 2004));
              if (m) {
                flush(i);
                const label = s.slice(i + 1, k), address = m[1].trim(), token = address.split(/\s+/)[0] || "";
                const innerHtml = inline(label, depth + 1, { emph: ctx.emph, noLink: true, noIds: true });
                let href = address === token ? mdHref(token, opt.known) : null;
                /* a label that is an id never links to another unit: the text and the target would disagree */
                const shown = decodeEntities(innerHtml.replace(/<[^>]*>/g, "")).replace(/\u2039U\+[0-9A-F]+\u203A/g, "").trim(); /* the text the reader sees */
                const idLabel = MD_ID.test(shown) ? shown : MD_ID.test(label.trim()) ? label.trim() : "";
                if (href && idLabel) { let tail = ""; try { tail = decodeURIComponent(href.slice(href.lastIndexOf("/") + 1)); } catch (e) { tail = ""; } if (tail !== idLabel) href = null; }
                if (href) {
                  node("a"); out += '<a href="' + esc(href) + '">' + innerHtml + "</a>";
                  node("span"); out += label.trim() !== token ? ' <span class="md-addr">(' + esc(token) + ")</span>" : ' <span class="md-addr">' + esc(token) + "</span>";
                } else {
                  out += innerHtml;
                  if (label.trim() !== address) { node("span"); out += ' <span class="md-addr">(' + esc(address) + ")</span>"; }
                  else { node("span"); out += ' <span class="md-addr">' + esc(address) + "</span>"; }
                }
                i = k + 1 + m[0].length; ps = i; continue;
              }
            }
            i++; continue;
          }
          i++;
        }
        flush(s.length);
        return out;
      }
      const para = (s, depth) => {
        node("p");
        const before = st.longs.length, body = inline(s, depth, { emph: { n: 0 }, noLink: false });
        const notice = st.longs.length > before ? cut("This paragraph is too long to format; shown unformatted: " + st.longs[before] + " characters.") : "";
        if (notice) st.longs.length = before;
        return notice + "<p>" + body + "</p>";
      };
      /* ---- tables */
      function splitRow(line) {
        tick(line.length);
        let s = line.trim();
        if (s[0] === "|") s = s.slice(1);
        if (s.length && s[s.length - 1] === "|" && s[s.length - 2] !== "\\") s = s.slice(0, -1);
        const spans = s.indexOf("`") >= 0 ? codeSpans(s) : [];
        const cells = []; let cur = "";
        for (let i = 0; i < s.length; i++) {
          const si = spans.length ? spanAt(spans, i) : -1;
          if (si >= 0 && spans[si].a === i) { cur += s.slice(spans[si].a, spans[si].b).replace(/\\\|/g, "|"); i = spans[si].b - 1; continue; }
          const c = s[i];
          if (c === "\\" && s[i + 1] === "|") { cur += "|"; i++; continue; }
          if (c === "|") { cells.push(cur.trim()); cur = ""; continue; }
          cur += c;
        }
        cells.push(cur.trim());
        return cells;
      }
      const isTableAt = (ls, B, i) => i + 1 < ls.length && ls[i].indexOf("|") >= 0 && isDelim(B[i + 1]) && splitRow(ls[i]).length === splitRow(ls[i + 1]).length;
      function table(ls, B, i, depth) {
        let joined = 0;
        const cellsOf = row => { const c = splitRow(row); if (c.length > L.cols) { joined = Math.max(joined, c.length - (L.cols - 1)); const keep = c.slice(0, L.cols - 1); keep.push(c.slice(L.cols - 1).join(" | ")); return keep; } return c; };
        const cell = (tag, t) => { node(tag); return "<" + tag + ">" + inline(t, depth + 1, { emph: { n: 0 }, noLink: false }) + "</" + tag + ">"; };
        node("div"); node("table"); node("thead"); node("tr");
        let out = '<div class="md-scroll"><table><thead><tr>' + cellsOf(ls[i]).map(c => cell("th", c)).join("") + "</tr></thead>";
        let j = i + 2, rows = "", n = 0;
        while (j < ls.length && !blank(ls[j]) && ls[j].indexOf("|") >= 0) {
          if (n >= L.rows) break;
          node("tr"); rows += "<tr>" + cellsOf(ls[j]).map(c => cell("td", c)).join("") + "</tr>"; n++; j++;
        }
        if (rows) { node("tbody"); out += "<tbody>" + rows + "</tbody>"; }
        out += "</table></div>";
        if (joined) out += cut("Columns past " + L.cols + ": " + joined + " columns are joined into the last cell.");
        if (j < ls.length && !blank(ls[j]) && ls[j].indexOf("|") >= 0) {
          const rest = []; while (j < ls.length && !blank(ls[j]) && ls[j].indexOf("|") >= 0) { rest.push(ls[j]); j++; }
          node("pre"); node("code");
          out += cut("Table cut after " + L.rows + " rows: the " + rest.length + " rows that follow are shown as text.") + '<pre class="md-rest"><code>' + esc(rest.join("\n")) + "</code></pre>";
        }
        return [out, j];
      }
      /* ---- blocks */
      /* the closer of every comment is found once per line array (one linear pass), not once per question asked: the first line at or
         after each line that holds a closing mark, and where. Each answer is remembered. */
      const noteInfo = new WeakMap();
      const noteEnd = (ls, i) => {
        let info = noteInfo.get(ls);
        if (!info) { info = { memo: new Array(ls.length), nextClose: null, pos: null }; noteInfo.set(ls, info); }
        if (info.memo[i] !== undefined) return info.memo[i];
        const s = ls[i];
        let a = 0; while (a < s.length && (s[a] === " " || s[a] === "\t")) a++;
        let res = -1;
        if (s.slice(a, a + 4) === "<!--") {
          let k = s.indexOf("-->", a + 4), e = i;
          if (k < 0) {
            if (!info.nextClose) {
              tick(ls.length);
              info.nextClose = new Array(ls.length + 1); info.pos = new Array(ls.length); info.nextClose[ls.length] = -1;
              for (let j = ls.length - 1; j >= 0; j--) { info.pos[j] = ls[j].indexOf("-->"); tick(ls[j].length); info.nextClose[j] = info.pos[j] >= 0 ? j : info.nextClose[j + 1]; }
            }
            e = info.nextClose[i + 1]; k = e >= 0 ? info.pos[e] : -1;
          }
          if (k >= 0 && e >= 0) res = blank(ls[e].slice(k + 3)) ? e : -1;
        }
        tick(s.length);
        info.memo[i] = res;
        return res;
      };
      const headOf = b => { const m = HEAD.exec(H(b)); return m && m[2] !== undefined ? { level: m[1].length, text: tailAfter(b, m, 2).trim() } : null; };
      const startsBlock = (ls, B, i) => { const b = B[i]; tick(b.length); return !!fenceOpen(b) || !!headOf(b) || isHr(b) || QUOTEH(b) || LISTH(b) || (ls[i].indexOf("|") >= 0 && isTableAt(ls, B, i)) || noteEnd(ls, i) >= 0; };
      function blocks(ls, depth) {
        if (depth >= L.depth) {
          st.flat++; node("pre"); node("code");
          return cut("Nesting deeper than " + L.depth + " levels: " + ls.length + (ls.length === 1 ? " line is" : " lines are") + " shown as plain text.") + '<pre class="md-flat"><code>' + esc(ls.join("\n")) + "</code></pre>";
        }
        { let n = ls.length; for (const l of ls) n += l.length; tick(n); } // work: every character of every line, at every nesting level
        const B = ls.map(bl);
        let out = "", i = 0;
        while (i < ls.length) {
          tick(1);
          if (depth === 0) at = i;
          const raw = ls[i], b = B[i];
          if (blank(raw)) { i++; continue; }
          let m;
          const fo = fenceOpen(b);
          if (fo) {
            const body = []; let j = i + 1, closed = false;
            while (j < ls.length) { tick(1); if (fenceClose(B[j], fo)) { closed = true; break; } body.push(stripCols(ls[j], fo.indent)); j++; }
            node("div"); node("pre"); node("code");
            out += '<div class="md-fence">' + (fo.info ? (node("span"), '<span class="md-lang">' + esc(fo.info) + "</span>") : "") + "<pre><code>" + esc(body.join("\n")) + "</code></pre>" + (closed ? "" : (node("span"), '<span class="md-open">No closing fence: the rest of the text is shown as code.</span>')) + "</div>";
            i = closed ? j + 1 : j; continue;
          }
          const ne = noteEnd(ls, i);
          if (ne >= 0) {
            st.notes++; node("div"); node("span"); node("pre"); node("code");
            out += '<div class="md-note"><span class="md-label">A note hidden in the document:</span><pre><code>' + esc(ls.slice(i, ne + 1).join("\n").trim()) + "</code></pre></div>";
            i = ne + 1; continue;
          }
          if ((m = headOf(b))) {
            const tag = "h" + Math.min(6, m.level + 2); node(tag);
            out += "<" + tag + ">" + inline(m.text, depth + 1, { emph: { n: 0 }, noLink: true }) + "</" + tag + ">"; i++; continue;
          }
          if (isHr(b)) { node("hr"); out += "<hr>"; i++; continue; }
          if (QUOTEH(b)) {
            const q = []; while (i < ls.length && QUOTEH(B[i])) { tick(1); q.push(B[i].replace(/^ {0,3}> ?/, "")); i++; }
            node("blockquote"); out += "<blockquote>" + blocks(q, depth + 1) + "</blockquote>"; continue;
          }
          if (raw.indexOf("|") >= 0 && isTableAt(ls, B, i)) { const r = table(ls, B, i, depth); out += r[0]; i = r[1]; continue; }
          if ((m = LISTH(b))) {
            const ordered = /\d/.test(m[2][0]);
            const kindKey = ordered ? m[2].slice(-1) : m[2];
            const base = m[1].length;
            let items = "", first = true, startNum = ordered ? parseInt(m[2], 10) : 1, prevNum = startNum - 1;
            while (i < ls.length) {
              tick(1);
              const mm = LISTH(B[i]);
              if (!mm) break;
              const od = /\d/.test(mm[2][0]), key = od ? mm[2].slice(-1) : mm[2], ind = mm[1].length;
              if (od !== ordered || key !== kindKey || ind < base || (!first && ind >= base + 4)) break;
              first = false;
              const sp = mm[3] ? mm[3].length : 1;
              const off = ind + mm[2].length + (sp >= 5 || !mm[4] ? 1 : sp);
              const body = [mm[4] || ""];
              let fs = null;
              { const o = fenceOpen(bl(body[0])); if (o) fs = o; }
              let j = i + 1;
              while (j < ls.length) {
                tick(1);
                const l = ls[j];
                if (fs) { // inside a fence the item goes on whatever the indent, a blank line included
                  const s2 = stripCols(l, off);
                  body.push(s2);
                  if (fenceClose(bl(s2), fs)) fs = null;
                  j++; continue;
                }
                if (blank(l)) {
                  let k = j + 1; while (k < ls.length && blank(ls[k])) k++;
                  if (k < ls.length && leadW(ls[k]) >= off) { for (let z = j; z < k; z++) body.push(""); j = k; continue; }
                  break;
                }
                const lead = leadW(l);
                if (lead >= off) {
                  const s2 = stripCols(l, off);
                  body.push(s2);
                  const o = fenceOpen(bl(s2)); if (o) fs = o;
                  j++; continue;
                }
                if (LISTH(B[j])) break;
                if (!blank(body[body.length - 1]) && !fenceOpen(B[j]) && !headOf(B[j]) && !isHr(B[j]) && !QUOTEH(B[j])) { body.push(l.trim()); j++; continue; }
                break;
              }
              let inner = blocks(body, depth + 1);
              if (inner.slice(0, 3) === "<p>" && inner.slice(-4) === "</p>" && inner.indexOf("</p>") === inner.length - 4) inner = inner.slice(3, -4);
              node("li");
              let attr = "";
              if (ordered) { const num = parseInt(mm[2], 10); if (num !== prevNum + 1) attr = ' value="' + String(num) + '"'; prevNum = num; }
              items += "<li" + attr + ">" + inner + "</li>";
              i = j;
              while (i < ls.length && blank(ls[i])) { const nx = i + 1; if (nx < ls.length && LISTH(B[nx])) { i = nx; break; } break; }
            }
            if (ordered) { node("ol"); out += "<ol" + (startNum !== 1 ? ' start="' + String(startNum) + '"' : "") + ">" + items + "</ol>"; }
            else { node("ul"); out += "<ul>" + items + "</ul>"; }
            continue;
          }
          if (leadW(b) >= 4) {
            const code = [];
            while (i < ls.length && ((!blank(ls[i]) && leadW(B[i]) >= 4) || (blank(ls[i]) && i + 1 < ls.length && !blank(ls[i + 1]) && leadW(B[i + 1]) >= 4))) { tick(1); code.push(stripCols(ls[i], 4)); i++; }
            node("pre"); node("code"); out += "<pre><code>" + esc(code.join("\n")) + "</code></pre>"; continue;
          }
          const pl = [raw.replace(/^[ \t]+/, "")]; i++;
          while (i < ls.length && !blank(ls[i]) && !startsBlock(ls, B, i)) { tick(1); pl.push(ls[i].replace(/^[ \t]+/, "")); i++; }
          out += para(pl.join("\n"), depth);
        }
        return out;
      }
      let html = "", over = false, spent = 0;
      try { html = blocks(lines, 0); }
      catch (e) {
        if (e !== OVER) throw e;
        /* the budget or the element cap ran out: the blocks before the one in progress are rebuilt (they fitted before), and the
           rest is shown as escaped text with a notice. Nothing throws from here on. */
        over = true; spent = Math.min(st.steps, L.steps);
        st.free = true; st.steps = 0; st.nodes = 0; st.elements = {}; st.cuts = 0; st.notes = 0; st.flat = 0;
        const rest = lines.slice(at).join("\n");
        html = blocks(lines.slice(0, at), 0);
        html += cut("The text is too large to format: from here on " + (lines.length - at) + ((lines.length - at) === 1 ? " line is" : " lines are") + " shown as plain text.") + '<pre class="md-rest"><code>' + esc(rest) + "</code></pre>";
      }
      st.free = true;
      for (const n of st.longs) html += cut("A heading or cell is too long to format; shown unformatted: " + n + " characters.");
      node("div");
      return { html: '<div class="md">' + html + tail + "</div>", over, steps: over ? spent : st.steps, nodes: st.nodes, cuts: st.cuts + (over && tail ? 1 : 0), notes: st.notes, flat: st.flat, elements: st.elements };
    }
    /* the one way the page uses the renderer: whatever goes wrong, the escaped source is shown with a visible notice */
    const cache = new Map(); let cacheChars = 0;
    function safe(text, opt) {
      /* memoised per section text and, when ids are linked, per index signature (opt.sig): a repaint renders nothing again, and a new
         index renders again. A link context with no signature is never cached. */
      const key = typeof text !== "string" ? null : !opt ? text : typeof opt.sig === "string" ? opt.sig + "\u0000" + text : null;
      if (key !== null && cache.has(key)) return cache.get(key);
      try {
        const html = render(text, opt).html;
        if (key !== null && key.length <= 600000) {
          cache.set(key, html); cacheChars += key.length + html.length;
          while (cacheChars > 16000000 || cache.size > 400) { const old = cache.keys().next().value; cacheChars -= old.length + cache.get(old).length; cache.delete(old); }
        }
        return html;
      }
      catch (e) {
        let src = "";
        try { src = visible(String(text == null ? "" : text)); } catch (e2) { src = ""; }
        return '<div class="md"><p class="md-cut">This text could not be formatted; it is shown as plain text.</p><pre class="md-rest"><code>' + esc(src) + "</code></pre></div>";
      }
    }
    return { render, safe, visible, hrefOf: mdHref, idHref, LIMITS: MD_LIMITS, get renders() { return renders; }, get cacheChars() { return cacheChars; } };
  }

  /* ------------------------------------------------------------------ pure renderers */
  function make(env) {
    const { esc, mono, ic, WSTATE, fmtDur, ptTime, pl } = env;
    const md = mdMake(esc);
    const since = sec => fmtDur(env.now() - sec * 1000);
    const pt = sec => ptTime(sec * 1000) + " PT";
    const num = n => (Number.isFinite(+n) ? +n : 0);

    const caps = w => (w.can && w.can.length
      ? w.can.map(c => '<span class="chip c-alias" title="' + tx("can deliver " + c) + '">' + tx(c) + "</span>").join("")
      : '<span class="chip c-none">no capabilities declared</span>');
    function now(w) {
      const h = w.holds;
      /* the daemon calls a worker whose process lives but who said nothing for a while "lost": nobody is lost while its process lives */
      if (w.state === "lost") {
        const q = pt(num(w.lost_since || w.heard));
        return h ? '<p class="now"><strong>Working, quiet since ' + q + ".</strong> Still holds " + idLink(h.unit) + " (" + tx(h.activity) + ") since " + pt(num(h.since)) + ". Nobody else can take it; if it is gone, free it with <code>./zn live release --worker " + tx(w.id) + "</code>.</p>"
          : '<p class="now"><strong>Quiet since ' + q + ".</strong> It holds nothing.</p>";
      }
      if (h) {
        return '<p class="now"><strong>Working</strong> on ' + tx(h.activity) + " for " + idLink(h.unit) + (h.step ? " (" + tx(h.step) + ")" : "") + '</p><p class="elapsed">' + ic("clock") +
          '<span data-lsince="' + num(h.since) + '">' + since(num(h.since)) + "</span> so far, since " + pt(num(h.since)) + '</p><div class="bar" aria-hidden="true"><i></i></div>';
      }
      return '<p class="now"><strong>Idle</strong> and ready for work it can deliver.</p><p class="elapsed">' + ic("moon") + 'registered <span data-lsince="' + num(w.started) + '">' + since(num(w.started)) + "</span> ago, at " + pt(num(w.started)) + "</p>";
    }
    function card(w) {
      const S = WSTATE[w.state === "lost" && w.holds ? "working" : w.state] || WSTATE.idle;
      return '<li><article class="wcard s-' + tx(w.state) + '" aria-label="' + tx(w.id + ", " + S[2]) + '"><div class="wc-h"><div class="wc-id"><span class="cliav" aria-hidden="true">' + tx(String(w.cli).slice(0, 2).toUpperCase()) +
        '</span><div><h3>' + tx(w.id) + '</h3><p class="wc-cli">' + tx(w.cli + " CLI, " + w.mode + (w.account ? ", account " + w.account : "") + (w.stop ? ", asked to stop" : "")) + '</p></div></div><span class="chip ' + S[0] + '">' + ic(S[1]) + S[2] + "</span></div>" +
        now(w) + '<dl class="wmeta"><div><dt>Last heard</dt><dd><span data-lheard="' + num(w.heard) + '">' + since(num(w.heard)) + " ago</span></dd></div></dl>" +
        '<div class="caps" role="group" aria-label="What it can deliver">' + caps(w) + "</div></article></li>";
    }
    const empty = () => '<div class="lv-empty"><h2>No workers are registered.</h2><p class="muted">A worker registers when it starts. To add one by hand: <code>./zn live register --cli claude --pid &lt;pid&gt;</code>. This page updates by itself when one does.</p></div>';
    function claims(cs) {
      return '<section class="lv-claims" aria-labelledby="lvc"><h2 id="lvc">Claims <span class="count">' + cs.length + "</span></h2>" + (cs.length
        ? '<ul class="steps">' + cs.map(c => "<li><span>" + idLink(c.unit) + " " + tx(c.activity) + " held by " + monoV(c.worker) + '</span><span class="muted">since ' + pt(num(c.since)) + ", " + '<span data-lsince="' + num(c.since) + '">' + since(num(c.since)) + "</span></span></li>").join("") + "</ul>"
        : '<p class="muted">Nothing is claimed.</p>') + "</section>";
    }
    function header(state) {
      const ws = state ? state.workers : [];
      const n = s => ws.filter(w => w.state === s).length;
      const sub = state ? pl(n("working"), "worker") + " working, " + n("idle") + " idle, " + n("lost") + " lost. Every row is the live daemon's own record of registrations, claims and heartbeats." : "Waiting for the live daemon…";
      return '<div class="pg-t"><h1>Workers</h1><p class="muted">' + tx(sub) + '</p></div><div class="simbar"><span class="sim-state live"><span class="live-dot" aria-hidden="true"></span>Live</span></div>';
    }
    const UNREACHABLE = "Cannot reach the live daemon. It stopped or restarted: run ./zn app for its new address.";
    /* the part of the Workers view that is real: the cards and the claims (the queue panel beside it is still simulated) */
    function body(state, err, linkArgs) {
      return withLinks(linkArgs ? linkCtx(linkArgs) : null, () => bodyOf(state, err));
    }
    function bodyOf(state, err) {
      return (err ? '<p class="lv-err" role="alert">' + tx(UNREACHABLE) + " Showing the last state it sent.</p>" : "") +
        '<section aria-label="Workers">' + (!state ? '<p class="muted">Loading…</p>' : state.workers.length ? '<ul class="wgrid">' + state.workers.map(card).join("") + "</ul>" : empty()) +
        (state ? claims(state.claims) : "") + "</section>";
    }
    /* the badge: live (real data) or simulated, per view */
    function badge(a) {
      const name = a.name + (a.kind === "queue" ? " queue entry" : "");
      if (a.on && a.isDetail) return a.err ? { cls: "warn", dot: false, text: name + ": live, cannot reach the daemon (run ./zn app)" } : { cls: "live", dot: true, text: name + ": live" };
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
      return '<p class="muted th-age">facts made ' + pt(num(f.at)) + " (" + fmtDur((a.now == null ? env.now() : a.now) - num(f.at) * 1000) + " ago)" + (f.commit ? ", read at commit " + monoV(f.commit) : ", commit unknown") + ". " + tx(WHEN) + "</p>";
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
      return '<div class="th-bar" role="img" aria-label="' + tx(label) + '">' + COUNTS.filter(k => num(c[k[0]]) > 0).map(k => '<i class="' + k[2] + '" style="width:' + Math.round(1000 * num(c[k[0]]) / total) / 10 + '%"></i>').join("") + "</div>";
    }
    function themeRow(th, f, multi, a) {
      const c = th.counts || {}, known = f.approvalsAt != null;
      const wc = workCmd(th.id), ws = th.workers || [];
      const words = COUNTS.map(k => (k[0] === "approval" && !known ? '<li><span class="sw bar-approval" aria-hidden="true"></span>waiting for your approval: not known yet</li>'
        : '<li><span class="sw ' + k[2] + '" aria-hidden="true"></span>' + num(c[k[0]]) + " " + tx(k[1]) + "</li>")).join("");
      const ago = fmtDur((a && a.now != null ? a.now : env.now()) - num(f.at) * 1000) + " ago";
      const nowHold = liveHolders(th, a && a.state);
      const chips = l => l.map(w => '<span class="chip c-trib">' + tx(w) + "</span>").join(" ");
      const who = nowHold
        ? (nowHold.length ? chips(nowHold) : '<span class="muted">no worker holds a unit listed here now</span>') + ' <span class="muted">(live; only units the facts list are joined)</span>'
        : !f.live ? '<span class="muted">who holds what is unknown: the live layer did not answer when these facts were made, ' + tx(ago) + "</span>"
        : (ws.length ? chips(ws) : '<span class="muted">no worker holds a unit here</span>') + ' <span class="muted">(when these facts were made, ' + tx(ago) + ")</span>";
      return '<li><article class="th-row" aria-label="' + tx("Theme " + th.title) + '"><div class="th-h"><h2><button class="th-go" data-theme-go="' + tx(th.id) + '" data-theme-project="' + tx(th.project || "") + '" data-k="th-' + tx(th.id) + '">' + tx(th.title) + "</button></h2>" + (multi ? '<span class="chip c-trib" title="the project that defines this theme">' + tx(th.project) + "</span>" : "") +
        '<span class="muted th-p">' + tx(th.purpose) + "</span></div>" + bar(c) + '<ul class="th-counts">' + words + '</ul><p class="muted th-asof">These counts are as they were when these facts were made, ' + tx(ago) + ".</p>" +
        '<p class="th-who"><strong>' + (nowHold ? "Workers here now" : "Workers when the facts were made") + ':</strong> ' + who + "</p>" +
        '<div class="th-cmds"><div><h3>Work this theme</h3>' + (wc ? cmdBox(wc, "tw-" + th.id) : '<p class="muted">No command: this name is not a theme name.</p>') + "</div>" +
        "<div><h3>Review what waits</h3>" + cmdBox(reviewCmd(), "tr-" + th.id) + '<p class="muted">Then open the theme above to see its approvals.</p></div></div></article></li>';
    }
    function themesView(a) {
      const head = '<div class="pg-t"><h1>Themes</h1><p class="muted">Where everything stands, one theme at a time. Pick a theme to go through what waits for you in it.</p></div>';
      const err = a.err ? '<p class="lv-err" role="alert">' + tx(UNREACHABLE) + " Showing the last facts it sent.</p>" : "";
      const r = a.resp;
      if (!r) return head + (a.err ? err : '<p class="muted">Loading…</p>');
      if (r.state !== "ok") return head + err + '<div class="lv-empty"><h2>' + (r.state === "absent" ? "No theme facts yet." : "The theme facts cannot be read.") + '</h2><p class="muted">' + tx(r.why || "") + "</p><p>Write them in a terminal: <code>./zn board</code></p></div>";
      const f = r.facts, themes = f.themes || [];
      if (!themes.length) return head + err + '<div class="lv-empty"><h2>No themes are defined.</h2><p class="muted">A project lists its themes in tributaries.toml. ' + tx(WHEN) + "</p></div>";
      const approvals = f.approvalsAt != null
        ? "Approval counts come from the last ./zn approve --queue, read " + pt(num(f.approvalsAt)) + (f.approvalsScope ? " for " + f.approvalsScope + " only, so the counts of every other unit include units whose approval state is unknown" : "") + ": run it again to refresh them (it makes these facts again)."
        : "Approval counts are not known: no approval queue has been read yet. Run ./zn approve --queue. Until then, units that wait for your approval are counted as in flight or not started.";
      return head + err + droppedLine(Z(f.dropped)) + themeAge(f, a) + '<p class="muted th-age">' + tx(approvals) + '</p><ul class="th-list">' + themes.map(th => themeRow(th, f, themes.some(o => o.project !== themes[0].project), a)).join("") + "</ul>";
    }
    function stripUnit(u) {
      const phase = u.phase === "owner" ? ' <span class="chip c-back">waiting on you (a question or a blocked idea)</span>'
        : u.phase === "claimed" ? ' <span class="chip c-wait">claimed ' + (u.claimedAt ? tx(u.claimedAt) : "(day unknown)") + ", no worker</span>" : "";
      return "<li><span>" + idLink(u.id) + " " + tx(u.title) + '</span><span class="th-st"><span class="chip c-land">' + tx(u.stage) + "</span>" + phase + " " +
        (u.holder ? tx(u.holder) : '<span class="muted">no worker</span>') + (u.since != null ? ' <span class="muted">in ' + tx(u.stage) + " for " + tx(fmtDur(u.now - num(u.since) * 1000)) + "</span>" : "") + "</span></li>";
    }
    function strip(a) {
      const head = '<section class="th-strip" aria-labelledby="th-coming"><h2 id="th-coming">What is coming</h2>';
      const r = a.themes, now = a.now == null ? env.now() : a.now;
      if (!r) return head + '<p class="muted">Loading what is coming…</p></section>';
      if (r.state !== "ok") return head + '<p class="muted">What is on its way is not known: ' + tx(r.why || "no theme facts") + "</p><p>Write them in a terminal: <code>./zn board</code></p></section>";
      const f = r.facts, all = f.themes || [], shown = a.theme ? all.filter(t => t.id === a.theme && (a.project == null || a.project === "" || t.project === a.project)) : all;
      const rows = shown.filter(t => (t.units || []).length);
      const age = themeAge(f, { now });
      if (!rows.length) {
        const pick = a.theme ? [a.theme] : (all.filter(t => num((t.counts || {}).open) > 0).map(t => t.id).concat(all.map(t => t.id))).filter((v, i, arr) => arr.indexOf(v) === i).slice(0, 3);
        const cmds = pick.map(workCmd).filter(Boolean).map((c, i) => cmdBox(c, "st-" + i)).join("");
        return head + "<p>Nothing is on its way" + (a.theme ? " in theme " + tx(a.theme) : "") + ": no unit is in flight and none waits on you for something else. " +
          (cmds ? "To start a worker " + (a.theme ? "on this theme" : "on a theme") + ", run this in a terminal of your own:</p>" + cmds : "</p>") + age + "</section>";
      }
      return head + '<p class="muted">Units on their way to you, not there yet: in flight, or waiting on you for something other than approval.</p>' + rows.map(t =>
        "<h3>" + tx(t.title) + '</h3><ul class="steps">' + t.units.map(u => stripUnit(Object.assign({ now }, u))).join("") + "</ul>").join("") + age + "</section>";
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
      const byId = {};
      /* one raft may sit under several theme objects (its waiting members sit in different themes): it is listed once, its tickets joined in order */
      all.forEach(t => { if (here(t)) (t.rafts || []).forEach(r => {
        if ((Array.isArray(r.themes) && r.themes.length ? r.themes : [t.id]).indexOf(theme) < 0) return;
        if (byId[r.id]) byId[r.id].tickets = byId[r.id].tickets.concat(r.tickets || []);
        else { byId[r.id] = Object.assign({}, r, { tickets: (r.tickets || []).slice() }); rafts.push(byId[r.id]); }
      }); });
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
    /* ---------------- f0437 step 6, slice 2: the link context. A view sets it for the length of one render (withLinks); every text the
       renderer is given and every id the page shows outside the renderer reads it. It holds what the units index, the approval
       facts and the theme facts say exists, and how old the index is; with no index it is "not ok", ids stay plain, and one line
       says why. Nothing in it comes from a ticket's text but the ids the index lists. */
    let CUR = null;
    const lookups = new WeakMap(); // a response -> the sets built from it (built once per response, never per paint)
    const memo = (resp, build) => { if (!resp || typeof resp !== "object") return build(null); let m = lookups.get(resp); if (!m) { m = build(resp); lookups.set(resp, m); } return m; };
    const ageWords = ms => { const s = Math.max(0, Math.floor(ms / 1000)); return s < 60 ? "less than a minute" : s < 3600 ? Math.floor(s / 60) + " min" : s < 172800 ? Math.floor(s / 3600) + " h" : Math.floor(s / 86400) + " days"; };
    const isObj = v => v !== null && typeof v === "object" && !Array.isArray(v);
    const own = (o, k) => Object.prototype.hasOwnProperty.call(o, k);
    const S = v => (typeof v === "string" ? v : "");
    const L = v => (Array.isArray(v) ? v.filter(x => typeof x === "string") : []);
    const Z = v => (typeof v === "number" && Number.isFinite(v) && v >= 0 ? Math.floor(v) : 0);
    /* one unit of the index, whatever the file held: every field has its type, so no view can throw on a hostile or confused index */
    function normUnit(u) {
      return { id: S(u.id), kind: S(u.kind), title: S(u.title), project: S(u.project), state: S(u.state), tributary: S(u.tributary), themes: L(u.themes), raft: S(u.raft), members: L(u.members), depends_on: L(u.depends_on),
        problem: S(u.problem), solution: S(u.solution), problem_size: Z(u.problem_size), solution_size: Z(u.solution_size), clipped: u.clipped === true, when: S(u.when), subject: S(u.subject), fate: S(u.fate), to: S(u.to),
        design: (Array.isArray(u.design) ? u.design : []).filter(isObj).map(d => ({ heading: S(d.heading), text: S(d.text), size: Z(d.size) })) };
    }
    function linkCtx(a) {
      const un = isObj(a.units) ? a.units : {}, resp = isObj(un.resp) ? un.resp : null;
      const okResp = resp && resp.state === "ok" && isObj(resp.facts) && Array.isArray(resp.facts.units);
      const status = un.old ? "old" : okResp ? "ok" : resp && typeof resp.state === "string" ? (resp.state === "ok" ? "unreadable" : resp.state) : un.err ? "error" : "loading";
      const now = a.now == null ? env.now() : a.now;
      const ap = isObj(a.approvals) && a.approvals.state === "ok" && isObj(a.approvals.facts) ? a.approvals : null, th = isObj(a.themes) && a.themes.state === "ok" && isObj(a.themes.facts) ? a.themes : null;
      const ctx = { status, why: status === "old" ? "" : status === "error" ? String(un.err) : resp ? S(resp.why) : "", facts: status === "ok" ? resp.facts : null, now, ap, th, dropped: 0, cut: 0, dup: 0 };
      const rows0 = th ? memo(th, r => (Array.isArray(r.facts.themes) ? r.facts.themes : []).filter(x => isObj(x) && typeof x.id === "string")) : [];
      ctx.rows = rows0; ctx.units = []; ctx.byId = new Map(); ctx.waiting = new Set(); ctx.names = new Set(rows0.map(x => x.id));
      if (status !== "ok") { ctx.known = () => false; ctx.opt = undefined; return ctx; }
      const f = resp.facts;
      const idx = memo(resp, r => { const m = new Map(), list = []; let dup = 0; for (const u of r.facts.units) { if (!isObj(u) || typeof u.id !== "string") continue; if (m.has(u.id)) { dup++; continue; } const n = normUnit(u); m.set(n.id, n); list.push(n); } return { m, list, dup }; });
      const waiting = ap ? memo(ap, r => { const set = new Set(); for (const t of Array.isArray(r.facts.themes) ? r.facts.themes : []) for (const rf of isObj(t) && Array.isArray(t.rafts) ? t.rafts : []) for (const k of isObj(rf) && Array.isArray(rf.tickets) ? rf.tickets : []) if (isObj(k) && typeof k.id === "string") set.add(k.id); return set; }) : new Set();
      const names = ctx.names;
      ctx.byId = idx.m; ctx.units = idx.list; ctx.waiting = waiting;
      ctx.dropped = Z(f.dropped); ctx.cut = Z(f.withdrawn_cut); ctx.dup = idx.dup;
      ctx.known = (kind, id) => {
        if (kind === "approvals") return waiting.has(id);
        if (kind === "tributary") return names.has(id);
        const u = idx.m.get(id);
        return !!u && u.kind === kind;
      };
      /* the tooltip holds the clock time the index was made, never an age: an age in a tooltip would freeze (a 304 repaints nothing) */
      ctx.missing = "not in the units index made at " + pt(num(f.at));
      ctx.opt = { known: ctx.known, missing: ctx.missing, sig: [S(f.sig), ap ? S(ap.facts.run) + "/" + S(ap.facts.at) : "-", th ? S(th.facts.at) : "-", ctx.missing].join("|") };
      return ctx;
    }
    function withLinks(ctx, fn) { const was = CUR; CUR = ctx; try { return fn(); } finally { CUR = was; } }
    const mdh = text => md.safe(text, CUR ? CUR.opt : undefined);
    /* the line that says why ids are plain text, or "" when they are links */
    const IDS_WHY = { old: "this daemon is older than the page: restart it with ./zn app.", loading: "" };
    const droppedLine = n => (n > 0 ? '<p class="lv-err" role="status">' + nf(n) + " theme rows were not understood and are left out (the daemon counted them).</p>" : "");
    function idsLine(ctx) {
      return (ctx && ctx.th ? droppedLine(Z(ctx.th.facts.dropped)) : "") + idsLineCore(ctx);
    }
    function idsLineCore(ctx) {
      if (ctx && ctx.status === "ok") {
        const left = ctx.dropped + ctx.dup;
        return (left > 0 ? '<p class="lv-err" role="status">' + nf(left) + " units of the index were not understood and are left out (the daemon counted them).</p>" : "") +
          (ctx.cut > 0 ? '<p class="lv-err" role="status">' + nf(ctx.cut) + " more withdrawn ids are not listed.</p>" : "");
      }
      if (!ctx) return "";
      if (ctx.status === "loading") return '<p class="lv-err" role="status" data-k="ids-note">Ids are plain text until the units index has loaded.</p>';
      const why = ctx.status === "old" ? IDS_WHY.old : ctx.status === "error" ? "the units index could not be fetched (" + ctx.why + ")." : ctx.why;
      return '<p class="lv-err" role="status" data-k="ids-note">Ids are plain text: ' + tx(why) + "</p>";
    }
    /* an id the page shows outside the renderer: a link when the index holds it, else as it was */
    function idLink(id, shown) {
      const href = CUR && CUR.status === "ok" ? md.idHref(String(id), CUR.known) : null;
      return href ? '<a href="' + esc(href) + '">' + monoV(shown == null ? id : shown) + "</a>" : monoV(shown == null ? id : shown);
    }
    /* every string of the facts that is shown outside the renderer: invisible characters are marked, then it is escaped (review F13) */
    const tx = s => esc(md.visible(String(s == null ? "" : s)));
    const monoV = s => mono(md.visible(String(s == null ? "" : s)));
    const sized = (heading, text) => "<h4>" + tx(heading) + ' <span class="muted count">' + nf(String(text).length) + " characters</span></h4>" + mdh(text);
    /* the pull request address is text with a Copy control, never a clickable outside link (G43); credentials are not shown */
    const link = u => {
      const m = /^([a-z][a-z0-9+.-]*:\/\/)([^\/?#]*@)?(.*)$/i.exec(String(u));
      const shown = m && m[2] ? m[1] + m[3] : String(u);
      return '<code class="md-addr">' + tx(shown) + '</code> <button class="btn sm" data-copy="' + tx(shown) + '" data-copy-kind="address" data-k="copy-pr">Copy</button>';
    };
    const copyFail = kind => (kind === "address" ? "Select the address and copy it" : "Select the command and copy it");
    const nf = n => (Number.isFinite(+n) ? Math.round(+n).toLocaleString("en-US") : "0");
    function cmdBox(cmd, what) {
      return '<div class="ap-cmd"><code>' + esc(cmd) + '</code><button class="btn sm" data-copy="' + esc(cmd) + '" data-k="copy-' + tx(what) + '">Copy</button></div>';
    }
    function sendBackBlock(a, tk, run) {
      const cmd = sendBackCmd(run, tk.id, a.stage, a.msg);
      return cmd
        ? "<p>Copy this, paste it in a terminal of your own, then apply it there:</p>" + cmdBox(cmd, "sb") + "<p class=\"muted\">Then run <code>./zn approve --apply " + tx(run) + "</code> and answer its question. The ruling is only words until you do.</p>"
        : '<p class="muted">' + (run ? "Choose where it goes back to and write what to change; the command appears here." : "There is no approval run yet: run <code>./zn approve --queue</code> first.") + "</p>";
    }
    function ticketHtml(x, a, run) {
      const tk = x.ticket, ap = approveCmd(run, tk.id);
      const guess = g => '<li class="ap-card"><h4>' + tx(g.id) + ' <span class="muted">(' + tx(g.step) + ", " + tx(g.when) + ')</span></h4><dl><dt>What was open</dt><dd>' + mdh(g.open) + "</dd><dt>What was chosen</dt><dd>" + mdh(g.chose) + "</dd><dt>Why</dt><dd>" + mdh(g.why) + "</dd></dl></li>";
      const rv = tk.reviews || [];
      const cost = tk.cost ? nf(tk.cost.tokens) + " tokens, " + nf(tk.cost.minutes) + " min" : "no cost recorded";
      const links = [tk.links && tk.links.pr ? "pull request " + link(tk.links.pr) : "", tk.links && tk.links.branch ? "branch " + monoV(tk.links.branch) : ""].filter(Boolean);
      /* review F6: the contract ends a section at any `## ` line, even inside a code block; the engine counts what is left outside */
      const fenced = h => (tk.fenced || []).filter(f => f.heading === h).map(f => '<p class="lv-err" role="status">this section ends at a heading inside a code block; ' + nf(num(f.lines)) + " lines after it are outside what you approve</p>").join("");
      const extraFenced = fenced("Acceptance criteria") + fenced("Test plan");
      return '<p class="muted ap-crumb">' + tx(x.theme.title) + " &rsaquo; " + (x.raft.single ? tx("on its own") : idLink(x.raft.id) + " " + tx(x.raft.title)) + " &rsaquo; <strong>" + tx(position(x)) + "</strong></p>" +
        "<h2>" + monoV(tk.id) + " " + tx(tk.title) + '</h2><p><span class="chip c-wait">' + tx(tk.why) + '</span> <span class="muted">read at ' + tx(tk.place) + ", contract " + tx(String(tk.hash || "-").slice(0, 12)) + "</span></p>" +
        '<section class="ap-sec" aria-labelledby="ap-idea"><h3 id="ap-idea">The idea</h3>' + (tk.idea.problem ? sized("Problem", tk.idea.problem) : "<h4>Problem</h4><p class=\"muted\">(none written)</p>") + fenced("Problem") + (tk.idea.solution ? sized("Solution", tk.idea.solution) : "<h4>Solution</h4><p class=\"muted\">(none written)</p>") + fenced("Solution") + (num(tk.comments) > 0 ? '<p class="muted" role="status">' + pl(num(tk.comments), "template comment") + " not shown (they are the template's own notes).</p>" : "") + "</section>" +
        '<section class="ap-sec" aria-labelledby="ap-design"><h3 id="ap-design">The design</h3>' + ((tk.design || []).length ? tk.design.map(d => sized(d.heading, d.text)).join("") : '<p class="muted">No design text yet.</p>') + fenced("Design") + "</section>" +
        ((tk.extra || []).length || extraFenced ? '<section class="ap-sec" aria-labelledby="ap-extra"><h3 id="ap-extra">Acceptance criteria and test plan</h3>' + (tk.extra || []).map(d => sized(d.heading, d.text) + fenced(d.heading)).join("") + ((tk.extra || []).some(d => d.heading === "Acceptance criteria") ? "" : fenced("Acceptance criteria")) + ((tk.extra || []).some(d => d.heading === "Test plan") ? "" : fenced("Test plan")) + "</section>" : "") +
        '<section class="ap-sec" aria-labelledby="ap-guess"><h3 id="ap-guess">Guesses <span class="count">' + (tk.guesses || []).length + '</span></h3>' + ((tk.guesses || []).length ? '<ul class="ap-cards">' + tk.guesses.map(guess).join("") + "</ul>" : '<p class="muted">No guesses were recorded.</p>') + "</section>" +
        '<section class="ap-sec" aria-labelledby="ap-rev"><h3 id="ap-rev">Reviews, cost and links</h3>' +
        (rv.length ? '<ul class="steps">' + rv.map(r => "<li><span>" + tx(r.name) + '</span><span class="chip c-trib">' + tx(r.verdict) + "</span></li>").join("") + "</ul>" : '<p class="muted">No review rounds are recorded in this folder.</p>') +
        "<p>Cost: " + tx(cost) + ".</p><p>" + (links.length ? links.join(", ") : '<span class="muted">No pull request or branch yet.</span>') + "</p></section>" +
        '<section class="ap-sec ap-decide" aria-labelledby="ap-dec"><h3 id="ap-dec">Your ruling</h3>' +
        "<h4>Approve</h4><p>Run these in a terminal of your own. Nothing is recorded by this page: approving is yours alone. The first writes your ruling; the second asks you, shows the title and the guesses, and refuses if the contract changed since this queue.</p>" +
        (ap ? cmdBox(ap, "ap") + "<p>Then <code>./zn approve --apply " + tx(run) + "</code></p>" : '<p class="muted">There is no approval run yet: run <code>./zn approve --queue</code> first.</p>') +
        '<p class="muted">This page is display only: what you approve is what the terminal shows. Compare the contract hash above with the line <code>--apply</code> prints before you answer y.</p>' +
        '<h4>Send back</h4><div class="ap-sb"><label for="ap-stage">Back to</label> <select id="ap-stage" data-k="ap-stage">' + STAGES.map(s => '<option value="' + s + '"' + (a.stage === s ? " selected" : "") + ">" + s + "</option>").join("") + "</select>" +
        '<label for="ap-msg">What to change (required)</label><textarea id="ap-msg" data-k="ap-msg" rows="3">' + esc(a.msg || "") + '</textarea><div id="ap-sbcmd">' + sendBackBlock(a, tk, run) + "</div></div></section>";
    }
    /* the note that says what a route id did: the filter was cleared for it, or it no longer waits */
    function noteLine(note, ctx) {
      if (!note) return "";
      if (note.kind === "cleared") return '<p class="lv-err" role="status"><strong>' + tx(note.id) + " is not in theme " + tx(note.theme) + ", so the theme filter was cleared.</strong></p>";
      const link = ctx && ctx.status === "ok" && MD_ID.test(String(note.id)) && ctx.known(String(note.id)[0] === "R" ? "raft" : "ticket", note.id) ? ' It is in the tracker: <a href="' + esc("#/" + (String(note.id)[0] === "R" ? "raft" : "ticket") + "/" + encodeURIComponent(note.id)) + '">open its page</a>.' : "";
      const wasUnit = ctx && ctx.status === "ok" && ctx.byId && ctx.byId.has(String(note.id));
      return '<p class="lv-err" role="status"><strong>' + (wasUnit ? tx(note.id) + " no longer waits for your approval." : "No ticket " + tx(note.id) + " waits for your approval.") + "</strong>" + link + " Showing the first ticket that does.</p>";
    }
    function approvalsView(a) {
      const ctx = linkCtx({ units: a.units, approvals: a.resp, themes: a.themes, now: a.now });
      return withLinks(ctx, () => approvalsBody(a, ctx));
    }
    function approvalsBody(a, ctx) {
      const head = '<div class="pg-t"><h1>Approvals</h1><p class="muted">One ticket at a time: a theme, then a raft (the bottom of a stack first), then a ticket.</p></div>' + idsLine(ctx) + noteLine(a.note, ctx);
      const err = a.err ? '<p class="lv-err" role="alert">' + esc(UNREACHABLE) + " Showing the last facts it sent.</p>" : "";
      const r = a.resp, coming = strip({ themes: a.themes, theme: a.theme, project: a.project, now: a.now });
      if (!r) return head + (a.err ? err : '<p class="muted">Loading…</p>');
      if (r.state !== "ok") return head + err + coming + '<div class="lv-empty"><h2>' + (r.state === "absent" ? "No approval facts yet." : "The approval facts cannot be read.") + '</h2><p class="muted">' + tx(r.why || "") + "</p><p>Ask for them in a terminal: <code>./zn approve --queue</code></p></div>";
      const list = flat(scoped(r.facts, a.theme, a.project));
      const scope = r.facts.scope ? String(r.facts.scope) : "";
      const themeLine = a.theme ? '<p class="lv-err" role="status"><strong>showing theme: ' + tx(a.theme) + '</strong>. <button class="btn sm" data-theme-go="" data-k="th-all">Show every theme</button></p>' : "";
      const sub = "facts read " + pt(num(r.facts.at)) + (r.facts.run ? ", run " + r.facts.run : "") + ". They were read when that command last ran; run it again to refresh.";
      if (!list.length && a.theme && scope) return head + err + themeLine + coming + '<div class="lv-empty"><h2>These approval facts do not cover theme ' + tx(a.theme) + '.</h2><p class="muted">They were made for ' + tx(scope) + ' only, so they say nothing about this theme. Refresh them for everything: <code>./zn approve --queue</code>. ' + tx(sub) + "</p></div>";
      if (!list.length) return head + err + themeLine + coming + '<div class="lv-empty"><h2>' + (a.theme ? "Nothing waits in theme " + tx(a.theme) + "." : scope ? "Nothing waits in " + tx(scope) + "." : "Nothing waits for your approval.") + '</h2><p class="muted">' + (scope ? "This was a scoped queue; run ./zn approve --queue for everything. " : "") + 'When a worker finishes a ticket that needs you, run <code>./zn approve --queue</code> and it appears here. ' + tx(sub) + "</p></div>";
      const idx = Math.max(0, Math.min(list.length - 1, a.idx | 0)), x = list[idx];
      let outline = "", cur = null, curRaft = null;
      list.forEach((y, i) => {
        if (cur !== y.theme) { cur = y.theme; curRaft = null; outline += "<h3>" + tx(y.theme.title) + "</h3>"; }
        if (curRaft !== y.raft) { curRaft = y.raft; outline += "<h4>" + tx(y.raft.single ? "on its own" : y.raft.id) + "</h4>"; }
        outline += '<button class="ap-o" data-ap-go="' + i + '" data-k="apo-' + i + '"' + (i === idx ? ' aria-current="true"' : "") + ">" + tx(y.ticket.id + " " + y.ticket.title) + "</button>";
      });
      const nav = '<div class="ap-nav" role="group" aria-label="Move between tickets"><button class="btn sm" data-k="ap-prev" data-ap="prev"' + (idx === 0 ? " disabled" : "") + '>Previous</button><span class="muted">' + (idx + 1) + " of " + list.length + '. Keys: j or right arrow for next, k or left arrow for previous.</span><button class="btn sm" data-k="ap-next" data-ap="next"' + (idx === list.length - 1 ? " disabled" : "") + ">Next</button></div>";
      const olderNote = num(r.facts.version) < 2 ? '<p class="lv-err" role="status"><strong>made by an older engine: texts are clipped and Acceptance criteria and Test plan are missing; run ./zn approve --queue</strong></p>' : "";
      return head + err + olderNote + themeLine + coming + (scope ? '<p class="lv-err" role="status"><strong>showing: ' + tx(scope) + ' only</strong>. This queue was made for that scope; run ./zn approve --queue for everything.</p>' : "") + '<p class="muted ap-read">' + tx(sub) + '</p><div class="ap-layout"><nav class="ap-outline" aria-label="Outline of what waits">' + outline + '</nav><div class="ap-main">' + nav + ticketHtml(x, a, r.facts.run) + "</div></div>";
    }
    /* ---------------- f0437 step 6, slice 2: the detail view of one unit, read only. A ticket, a raft, a tributary, a done unit, a
       withdrawn id (a stub) or an id the index does not hold. Each source says its own age; nothing here is a request or a button. */
    const STATE_WORDS = { backlog: "in the backlog", active: "in code (active)", done: "done", closed: "closed (it will not be done)", retired: "retired (folded into another raft)", withdrawn: "withdrawn" };
    const OPEN = { backlog: true, active: true };
    const isOpen = u => own(OPEN, u.state);
    const DETAIL_KINDS = ["ticket", "raft", "tributary"];
    const DETAIL_MAX = 200;
    const crumb = tail => '<p class="muted ap-crumb"><a href="#/themes">Themes</a> &rsaquo; <a href="#/approvals">Approvals</a> &rsaquo; <strong>' + tail + "</strong></p>";
    const stateChip = u => '<span class="chip c-land">' + tx(own(STATE_WORDS, u.state) ? STATE_WORDS[u.state] : u.state) + "</span>";
    /* an age is a span the page's own tick keeps current (data-lheard), never text fixed at paint */
    const age = (verb, sec, now) => verb + ' <span data-lheard="' + num(sec) + '">' + tx(fmtDur(Math.max(0, now - num(sec) * 1000)) + " ago") + "</span>";
    function sourcesLine(ctx, a) {
      const f = ctx.facts, ap = ctx.ap && ctx.ap.facts, th = ctx.th && ctx.th.facts;
      return '<p class="muted th-age">Sources, each with its own age: units index ' + (f ? age("made", f.at, ctx.now) + (S(f.commit) ? ", read at commit " + monoV(f.commit) : "") : "not read") +
        "; approval facts " + (ap ? age("read", ap.at, ctx.now) : "not read") + "; theme facts " + (th ? age("made", th.at, ctx.now) : "not read") +
        "; live claims " + (a.state && Array.isArray(a.state.claims) ? "as of now" : "not known") + ".</p>";
    }
    const idItem = (id, ctx) => {
      const u = ctx.byId && ctx.byId.get(id);
      return "<li>" + idLink(id) + (u && u.title ? " " + tx(u.title) : "") + (u ? " " + stateChip(u) : "") + "</li>";
    };
    const bytesOf = t => { try { return unescape(encodeURIComponent(t)).length; } catch (e) { return t.length; } };
    const CONT = /\n(?:`{3,}|~{3,})\n\n\(the code continues in the ticket file\)$/;
    /* one part of a preview: the text as the index clipped it, and how much of the whole it is ("first N of M bytes") */
    function partHtml(text, size) {
      if (text === "" && size === 0) return '<p class="muted">empty</p>';
      const whole = bytesOf(text) === size;
      const shown = whole ? size : bytesOf(text.replace(CONT, "").replace(/\.\.\.$/, ""));
      return mdh(text) + (whole ? "" : '<p class="muted" role="status">first ' + nf(shown) + " of " + nf(size) + " bytes; the full text is in the ticket file.</p>");
    }
    function preview(u) {
      let out = '<section class="ap-sec"><h3>The idea and the design (a clipped preview)</h3>';
      out += "<h4>Problem</h4>" + (u.problem || u.problem_size ? partHtml(u.problem, u.problem_size) : '<p class="muted">(none written)</p>');
      out += "<h4>Solution</h4>" + (u.solution || u.solution_size ? partHtml(u.solution, u.solution_size) : '<p class="muted">(none written)</p>');
      const omitted = [];
      for (const d of u.design) {
        if (d.text === "" && d.size > 0) { omitted.push(d); continue; }
        out += "<h4>" + tx(d.heading) + "</h4>" + partHtml(d.text, d.size);
      }
      if (omitted.length) out += '<p class="muted" role="status">' + nf(omitted.length) + (omitted.length === 1 ? " more part" : " more parts") + " not shown (" + nf(omitted.reduce((n, d) => n + d.size, 0)) + " bytes): " + omitted.map(d => tx(d.heading)).join(", ") + "; they are in the ticket file.</p>";
      return out + "</section>";
    }
    const tribLink = name => (CUR && CUR.status === "ok" && MD_NAME.test(String(name)) && CUR.known("tributary", name) ? '<a href="' + esc("#/tributary/" + encodeURIComponent(name)) + '">' + tx(name) + "</a>" : tx(name));
    function unitBody(u, ctx, a) {
      const wait = ctx.waiting && ctx.waiting.has(u.id) && MD_ID.test(u.id);
      const held = (Array.isArray(a.state && a.state.claims) ? a.state.claims : []).filter(c => isObj(c) && (c.unit === u.id || c.raft === u.id)).map(c => tx(c.worker) + " (" + tx(c.activity) + ")");
      let out = crumb(monoV(u.id)) + "<h2>" + monoV(u.id) + " " + tx(u.title) + '</h2><p><span class="chip c-trib">' + tx(u.kind) + "</span> " + stateChip(u) + (u.project ? ' <span class="muted">project ' + tx(u.project) + "</span>" : "") + "</p>";
      out += "<p>" + (wait ? '<strong>Waits for your approval.</strong> <a href="' + esc("#/approvals/" + encodeURIComponent(u.id)) + '">Open it in the walk</a> at its place.' : isOpen(u) ? "Does not wait for your approval now (by the approval facts below)." : "Nothing is asked of you here.") +
        (held.length ? " Held now by " + held.join(", ") + "." : "") + "</p>";
      if (u.raft) out += "<p>Raft: " + idLink(u.raft) + "</p>";
      if (u.tributary) out += "<p>Tributary: " + tribLink(u.tributary) + (u.themes.length > 1 || (u.themes.length === 1 && u.themes[0] !== u.tributary) ? " (themes: " + u.themes.map(tribLink).join(", ") + ")" : "") + "</p>";
      const firstOf = (l, h) => "<h3>" + h + "</h3>" + (l.length > DETAIL_MAX ? '<p class="muted">first ' + nf(DETAIL_MAX) + " of " + nf(l.length) + "; the rest are in the ticket file.</p>" : "") + "<ul>" + l.slice(0, DETAIL_MAX).map(id => idItem(id, ctx)).join("") + "</ul>";
      if (u.depends_on.length) out += firstOf(u.depends_on, "Depends on");
      if (u.members.length) out += firstOf(u.members, "Tickets, in order");
      else if (u.kind === "raft" && isOpen(u)) out += '<p class="muted">This raft holds no tickets.</p>';
      if (isOpen(u)) out += preview(u);
      else out += '<p class="muted">A ' + tx(u.state === "done" ? "done" : u.state) + " unit's text is not in the index: its title and place are all this page holds. The ticket file has the rest.</p>";
      return out;
    }
    /* what became of an id whose document is gone: withdrawn only when the commit's subject says so, renumbered when the compaction map names it */
    function stubBody(u) {
      const day = tx(u.when), subj = tx(u.subject);
      const what = u.fate === "renumbered" && MD_ID.test(u.to) ? '<span class="chip c-back">renumbered</span> <strong>Renumbered to</strong> ' + idLink(u.to) + " on " + day + ": " + subj
        : u.fate === "withdrawn" ? '<span class="chip c-back">withdrawn</span> <strong>Withdrawn</strong> on ' + day + ": " + subj
        : '<span class="chip c-back">removed</span> <strong>Removed</strong> on ' + day + ": " + subj;
      return crumb(monoV(u.id)) + "<h2>" + monoV(u.id) + "</h2><p>" + what + '</p><p class="muted">No ticket file exists for it now; git remembers it. This is a stub: only the day and the subject of the commit that removed it are known.</p>';
    }
    function tributaryBody(name, ctx, a) {
      const rows = ctx.rows.filter(t => t.id === name);
      const all = ctx.units ? ctx.units.filter(u => u.state !== "withdrawn" && u.themes.indexOf(name) >= 0) : [];
      if (!rows.length && !all.length) return crumb(tx(name)) + "<h2>No tributary " + tx(name) + " in the themes</h2><p>No theme facts and no unit of the index name it. <a href=\"#/themes\">Back to the themes</a>.</p>";
      const section = (row, units) => {
        units = units.slice().sort((p, q) => (isOpen(q) ? 1 : 0) - (isOpen(p) ? 1 : 0));
        const c = row && isObj(row.counts) ? row.counts : null;
        return (row ? '<p class="muted">' + (rows.length > 1 ? "project " + tx(S(row.project)) + ": " : "") + tx(S(row.purpose)) + "</p>" + (c ? "<p>" + nf(c.done) + " done, " + nf(c.flight) + " in flight, " + nf(c.approval) + " waiting for your approval, " + nf(c.owner) + " waiting on you for something else, " + nf(c.open) + " not started.</p>" : "") : '<p class="muted">No theme facts hold this name (the index names it).</p>') +
          "<h3>Units</h3>" + (units.length ? '<p class="muted">' + (units.length > DETAIL_MAX ? "first " + nf(DETAIL_MAX) + " of " + nf(units.length) + " (open ones first); the rest are in the ticket files." : nf(units.length) + " units (open ones first).") + "</p><ul>" + units.slice(0, DETAIL_MAX).map(u => idItem(u.id, ctx)).join("") + "</ul>" : '<p class="muted">The units index holds none.</p>');
      };
      /* a tributary is a project's own: each row lists the units of its project; with no row the units are all there is */
      const rest = rows.length >= 2 ? all.filter(u => !rows.some(r => S(r.project) === u.project)) : [];
      const restHtml = rest.length ? "<h3>Units of projects with no row for this name</h3>" + '<p class="muted">' + nf(rest.length) + (rest.length === 1 ? " unit" : " units") + " of projects with no row for this name" + (rest.length > DETAIL_MAX ? "; first " + nf(DETAIL_MAX) + " of " + nf(rest.length) : "") + ".</p><ul>" + rest.slice(0, DETAIL_MAX).map(u => idItem(u.id, ctx)).join("") + "</ul>" : "";
      return crumb(tx(name)) + "<h2>Tributary " + tx(name) + "</h2>" + (rows.length ? rows.map(r => section(r, all.filter(u => rows.length < 2 || u.project === S(r.project)))).join("") : section(null, all)) + restHtml;
    }
    function detailView(a) {
      const ctx = linkCtx({ units: a.units, approvals: a.approvals, themes: a.themes, now: a.now });
      return withLinks(ctx, () => {
        const id = String(a.id == null ? "" : a.id), kind = a.kind;
        let body;
        if (kind === "tributary") body = tributaryBody(id, ctx, a);
        else if (ctx.status !== "ok") body = crumb(monoV(id)) + "<h2>" + monoV(id) + "</h2>";
        else {
          const u = ctx.byId.get(id);
          if (!u) body = crumb(monoV(id)) + "<h2>No unit " + tx(id) + " in the tracker now</h2><p>The units index does not hold it. If it was made after the index, it appears when the board is rebuilt.</p><p><a href=\"#/themes\">Back to the themes</a></p>";
          else if (u.state === "withdrawn") body = stubBody(u);
          else {
            body = unitBody(u, ctx, a);
            if (u.kind !== kind) body = '<p class="lv-err" role="status"><strong>' + tx(id) + " is a " + tx(u.kind) + ", not a " + tx(kind) + ".</strong> " + idLink(id) + "</p>" + body;
          }
        }
        return '<div class="pg-t"><h1>' + tx(kind === "tributary" ? "Tributary" : kind === "raft" ? "Raft" : "Ticket") + '</h1></div>' + idsLine(ctx) + body + sourcesLine(ctx, a);
      });
    }
    const detail = { view: detailView, KINDS: DETAIL_KINDS };
    const links = { ctx: linkCtx, idsLine, ageWords };
    const approvals = { view: approvalsView, flat, scoped, position, keyAction, approveCmd, sendBackCmd, sendBackBlock, strip, STAGES };
    return { card, claims, header, body, badge, empty, UNREACHABLE, approvals, themes, detail, links, md, copyFail };
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
    ".th-strip a,.dt-root a,.ap-crumb a{color:var(--accent);text-decoration:underline}.dt-root{min-width:0;overflow-wrap:anywhere}.dt-root ul{padding-left:22px}.dt-root li{margin:2px 0}" +
    ".lv-claims{margin-top:22px}.lv-err{border:1px solid var(--back);background:var(--back-bg);color:var(--back);border-radius:12px;padding:10px 14px;margin-bottom:12px;font-weight:600}" + MD_CSS;

  function install(g) {
    const doc = g.document;
    const LIVE = { on: !!g.location && (g.location.protocol === "http:" || g.location.protocol === "https:"), state: null, err: null, stream: false, why: "", busy: false, again: false };
    LIVE.ap = { resp: null, err: null, raw: null, note: null, appliedHash: null, idx: 0, stage: "design", msg: "", busy: false, again: false, theme: null, project: null };
    LIVE.th = { resp: null, err: null, raw: null, busy: false, again: false };
    LIVE.un = { resp: null, err: null, raw: null, etag: null, old: false, busy: false, again: false };
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
      const b = R.badge({ on: LIVE.on, isWorkers: st.view === "workers", isApprovals: st.view === "approvals", isThemes: st.view === "themes", isDetail: isDetail(), kind: route.kind, name: isDetail() ? route.kind.charAt(0).toUpperCase() + route.kind.slice(1) : label(st.view), err: isDetail() ? (LIVE.ap.err || LIVE.th.err || LIVE.un.err) : st.view === "approvals" ? LIVE.ap.err : st.view === "themes" ? LIVE.th.err : LIVE.err, stream: LIVE.stream, why: LIVE.why });
      paint(badgeEl(), b.cls, (b.dot ? '<span class="live-dot" aria-hidden="true"></span>' : "") + esc(R.md.visible(String(b.text))));
    }
    const origRenderWorkers = g.renderWorkers, origLiveText = g.liveText;
    function renderLiveWorkers() {
      ensurePage("workers");
      sim.sel = null; // the worker drawer is the simulation's: it never opens over the real list
      const v = $("#view"), sc = v.scrollTop;
      withFocus(() => {
        $("#pg-h").innerHTML = R.header(LIVE.state);
        const q = queueHtml(queue()).replace('<h2 id="qph">', '<h2 id="qph"><span class="srcbadge sim">simulated</span> ');
        $("#pg-body").innerHTML = '<div class="wlayout">' + R.body(LIVE.state, LIVE.err, UN.resp ? { units: UN, approvals: AP.resp, themes: TH.resp } : null) + q + "</div>";
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
    const origRenderView = g.renderView, AP = LIVE.ap, A = R.approvals, UN = LIVE.un, DT = R.detail;
    const msgs = {};
    const TH = LIVE.th, T = R.themes;
    const apList = () => (AP.resp && AP.resp.state === "ok" ? A.flat(A.scoped(AP.resp.facts, AP.theme, AP.project)) : []);
    const apCurrent = () => { const l = apList(); return l[Math.max(0, Math.min(l.length - 1, AP.idx | 0))]; };
    const isDetail = () => st.view === "tickets" && !!st.route && DT.KINDS.indexOf(st.route.kind) >= 0;
    /* the page keeps the reader's place in its own memory: the scroll position of each route, by its address */
    const scrolls = {};
    const SCROLL_KEYS = 300; // routes remembered; past it the memory starts again (a reader's place is a convenience)
    const hashKey = () => String(g.location.hash || "").replace(/^#\/?/, "");
    /* a route id: `#/approvals/<id>` takes the walk to that ticket. A ticket outside the theme filter clears the filter and says so; one
       that no longer waits says so (never the first ticket, silently). Applied once per address: stepping keeps the address in step. */
    function syncWalkRoute() {
      const key = g.location.hash || "";
      if (AP.appliedHash === key || !AP.resp || AP.resp.state !== "ok") return;
      AP.appliedHash = key;
      const r = st.route || {};
      if (r.view !== "approvals" || !r.id) return;
      const at = apList().findIndex(y => y.ticket.id === r.id);
      if (at >= 0) { AP.idx = at; AP.note = null; return; }
      const full = A.flat(AP.resp.facts), inFull = full.findIndex(y => y.ticket.id === r.id);
      if (inFull >= 0) { const was = AP.theme; AP.theme = null; AP.project = null; AP.idx = inFull; AP.note = was ? { kind: "cleared", id: r.id, theme: was } : null; return; }
      AP.note = { kind: "gone", id: r.id };
    }
    function paintApprovals() {
      if (st.view !== "approvals" || !LIVE.on) return;
      ensurePage("approvals-live");
      syncWalkRoute();
      const x = apCurrent();
      AP.msg = x ? (msgs[x.ticket.id] || "") : "";
      const v = $("#view"), sc = v.scrollTop;
      withFocus(() => { $("#pg-h").innerHTML = ""; $("#pg-body").innerHTML = '<div class="ap-root">' + A.view({ resp: AP.resp, err: AP.err, idx: AP.idx, stage: AP.stage, msg: AP.msg, theme: AP.theme, project: AP.project, themes: TH.resp, units: UN, note: AP.note, now: Date.now() }) + "</div>"; });
      v.scrollTop = sc;
      /* the address names the ticket on show (no new history entry), so that Back from a link lands on this ticket */
      if (x && g.history && typeof g.history.replaceState === "function") {
        const want = "#/approvals/" + encodeURIComponent(x.ticket.id);
        if (g.location.hash !== want) g.history.replaceState(null, "", want);
        AP.appliedHash = want;
      }
    }
    function paintThemes() {
      if (st.view !== "themes" || !LIVE.on) return;
      ensurePage("themes-live");
      const v = $("#view"), sc = v.scrollTop;
      withFocus(() => { $("#pg-h").innerHTML = ""; $("#pg-body").innerHTML = '<div class="th-root">' + T.view({ resp: TH.resp, err: TH.err, state: LIVE.state, now: Date.now() }) + "</div>"; });
      v.scrollTop = sc;
    }
    function paintDetail() {
      if (!LIVE.on || !isDetail()) return;
      ensurePage("detail-live");
      const r = st.route, v = $("#view"), sc = v.scrollTop;
      withFocus(() => { $("#pg-h").innerHTML = ""; $("#pg-body").innerHTML = '<div class="dt-root">' + DT.view({ kind: r.kind, id: r.id, units: UN, approvals: AP.resp, themes: TH.resp, state: LIVE.state, now: Date.now() }) + "</div>"; });
      v.scrollTop = sc;
    }
    /* what is on show is repainted only when what it is made of changed: an event that changes nothing repaints nothing (the reader's
       place, a half-written message and the scroll position are not touched) */
    function repaint() { if (st.view === "approvals") paintApprovals(); else if (st.view === "themes") paintThemes(); else paintDetail(); }
    /* one GET of a facts file: true when what it says (or whether it could be read) differs from the last time */
    const BAD_BODY = why => ({ state: "unreadable", why });
    function getFacts(url, S) {
      return g.fetch(url, { cache: "no-store", headers: S.etag ? { "If-None-Match": S.etag } : {} }).then(r => {
        if (r.status === 304) return null; // the tag it holds is still the file: nothing to read, nothing to repaint
        if (!r.ok) return Promise.reject(new Error("HTTP " + r.status));
        S.tag = (r.headers && r.headers.get && r.headers.get("ETag")) || null;
        return r.text();
      }).then(text => {
        const was = S.err; S.err = null;
        if (text === null) return was !== null;
        if (text === S.raw) { S.etag = S.tag; return was !== null; }
        let parsed = null;
        try { parsed = JSON.parse(text); } catch (e) { parsed = null; }
        if (parsed === null || typeof parsed !== "object") {
          /* a body that is not facts: said in words, the old facts are not left on screen as current, no tag or text is kept (so no 304 can
             confirm it) and the next event asks again */
          const same = S.bad === true;
          S.bad = true; S.raw = null; S.etag = null;
          S.resp = BAD_BODY("The facts cannot be read: the daemon sent text that is not valid JSON (a truncated or damaged answer). The page asks again at the next event.");
          return !same || was !== null;
        }
        S.bad = false; S.resp = parsed; S.raw = text; S.etag = S.tag;
        return true;
      }).catch(e => { const msg = e && e.message ? e.message : String(e); const changed = S.err !== msg; S.err = msg; return changed; });
    }
    function refreshThemes() {
      if (TH.busy) { TH.again = true; return; }
      TH.busy = true;
      getFacts("/api/themes", TH).then(changed => {
        TH.busy = false;
        if (changed) repaint();
        updateBadge();
        if (TH.again) { TH.again = false; refreshThemes(); }
      });
    }
    /* the units index: asked for on first need and again with the tag it holds, so an unchanged index costs a 304 and no repaint; a 404
       is an older daemon, said in words and not asked again */
    function refreshUnits() {
      if (UN.old) return;
      if (UN.busy) { UN.again = true; return; }
      UN.busy = true;
      g.fetch("/api/units", { cache: "no-store", headers: UN.etag ? { "If-None-Match": UN.etag } : {} }).then(r => {
        if (r.status === 404) { const was = UN.old; UN.old = true; UN.resp = null; return !was; }
        if (r.status === 304) return false;
        if (!r.ok) return Promise.reject(new Error("HTTP " + r.status));
        const tag = (r.headers && r.headers.get && r.headers.get("ETag")) || null;
        return r.text().then(text => {
          const was = UN.err; UN.err = null;
          if (text === UN.raw) { UN.etag = tag; return was !== null; }
          let parsed = null;
          try { parsed = JSON.parse(text); } catch (e) { parsed = null; }
          if (parsed === null || typeof parsed !== "object") {
            const same = UN.bad === true;
            UN.bad = true; UN.raw = null; UN.etag = null;
            UN.resp = BAD_BODY("the units index sent by the daemon is not valid JSON (a truncated or damaged answer); the page asks again at the next event");
            return !same || was !== null;
          }
          UN.bad = false; UN.resp = parsed; UN.raw = text; UN.etag = tag;
          return true;
        });
      }).catch(e => { const msg = e && e.message ? e.message : String(e); const changed = UN.err !== msg; UN.err = msg; return changed; }).then(changed => {
        UN.busy = false;
        if (changed) repaint();
        updateBadge();
        if (UN.again) { UN.again = false; refreshUnits(); }
      });
    }
    function refreshApprovals() {
      refreshThemes(); // the strip above the ticket
      refreshUnits(); // ids become links once it is here
      if (AP.busy) { AP.again = true; return; }
      AP.busy = true;
      const was = apCurrent();
      getFacts("/api/approvals", AP).then(changed => {
        AP.busy = false;
        if (was) { const at = apList().findIndex(y => y.ticket.id === was.ticket.id); if (at >= 0) AP.idx = at; }
        if (changed) repaint();
        updateBadge();
        if (AP.again) { AP.again = false; refreshApprovals(); }
      });
    }
    g.renderView = function () {
      if (LIVE.on && st.view === "approvals") { paintApprovals(); refreshApprovals(); }
      else if (LIVE.on && st.view === "themes") { paintThemes(); refreshThemes(); }
      else if (LIVE.on && isDetail()) { paintDetail(); refreshApprovals(); }
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
    function move(to) { const n = apList().length; if (!n) return; AP.idx = Math.max(0, Math.min(n - 1, to)); AP.note = null; paintApprovals(); const v = $("#view"); if (v) v.scrollTop = 0; }
    const sbBox = x => { const box = doc.getElementById("ap-sbcmd"); if (box) box.innerHTML = A.sendBackBlock({ stage: AP.stage, msg: AP.msg }, x.ticket, AP.resp.facts.run); };
    doc.addEventListener("click", e => {
      if (!LIVE.on || (st.view !== "approvals" && st.view !== "themes") || !e.target || !e.target.closest) return;
      const tgo = e.target.closest("[data-theme-go]");
      if (tgo) { AP.theme = tgo.dataset.themeGo || null; AP.project = AP.theme ? (tgo.dataset.themeProject || null) : null; AP.idx = 0; AP.note = null; if (st.view === "approvals") paintApprovals(); else g.location.hash = "#/approvals"; return; }
      const go = e.target.closest("[data-ap-go]"), nav = e.target.closest("[data-ap]"), cp = e.target.closest("[data-copy]");
      if (go) move(+go.dataset.apGo);
      else if (nav) move(AP.idx + (nav.dataset.ap === "next" ? 1 : -1));
      else if (cp) {
        const text = cp.dataset.copy, done = ok => { cp.textContent = ok ? "Copied" : R.copyFail(cp.dataset.copyKind); };
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
    /* the reader's place: the scroll position of the route on show is remembered as it moves, and given back when Back returns to the
       route (the page's own router resets it to the top, and its listener ran first). Kept in page memory only. */
    doc.addEventListener("scroll", e => { if (LIVE.on && e && e.target && e.target === $("#view")) { if (Object.keys(scrolls).length > SCROLL_KEYS) for (const k of Object.keys(scrolls)) delete scrolls[k]; scrolls[hashKey()] = e.target.scrollTop; } }, true);
    g.addEventListener("hashchange", () => {
      const v = $("#view"), key = hashKey();
      if (LIVE.on && v && Object.prototype.hasOwnProperty.call(scrolls, key)) v.scrollTop = scrolls[key];
    });

    function refresh() {
      if (LIVE.busy) { LIVE.again = true; return; }
      LIVE.busy = true;
      g.fetch("/api/state", { cache: "no-store" }).then(r => (r.ok ? r.json() : Promise.reject(new Error("HTTP " + r.status)))).then(s => {
        LIVE.state = s; LIVE.err = null;
      }).catch(e => { LIVE.err = e && e.message ? e.message : String(e); }).then(() => {
        LIVE.busy = false;
        if (st.view === "workers") g.renderWorkers();
        if (st.view === "approvals" || isDetail()) refreshApprovals();
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

  root.LiveApp = { make, install, MD_RULES, MD_CSS };
  root.LiveApp.result = install(root);
})(globalThis);
