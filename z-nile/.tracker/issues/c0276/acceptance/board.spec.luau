--!strict
-- c0276: the board, built by ./zn board and rebuilt after every publish and main-checkout sync, carries each claim's
-- verdict (the reads c0265's `status` makes), lost work first; it still builds when the heartbeats or the pull
-- requests cannot be read, and in a protected checkout it reads no remote at all. Time is ZN_NOW (honoured only inside a
-- spec run). Every beat here is another terminal's (a force-pushed branch), so the cases hold whether or not a later
-- layer beats by itself. Fixture under .cache/c0276-board.
local fakecli = require("@tests/lib/fakecli")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local heartbeat = require("@znile/engine/heartbeat")
local process = require("@lune/process")
local serde = require("@lune/serde")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local h: fakecli.Harness
local wt, wt2 = "", "" -- wt made the claims; wt2 holds none and publishes
local T0 = os.time()
local STALE = heartbeat.STALE
local LATE = T0 + 3 * STALE -- everything claimed at about T0 is stale then, whatever the seconds the fixture took
local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local P = "pickman/.tracker/issues"

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end
local function zn(cwd: string, args: { string }, now: number?, extra: { [string]: string }?): fixture.Result
	local env: { [string]: string } = {
		FAKE_DIR = h.fakes,
		PATH = `{h.bin}:{process.env.PATH}`,
		ZN_AGENT_TOKEN_FILE = h.token,
		ZN_WATERMARK_DIR = `{h.f.base}/watermark`,
	}
	if now then
		env.ZN_NOW = tostring(now)
	end
	for k, v in (extra or {}) :: { [string]: string } do
		env[k] = v
	end
	return fixture.exec(cwd, "bash", { "scripts/tracker.sh", table.unpack(args) }, { env = env })
end
local function must(r: fixture.Result, what: string): string
	if not r.ok then
		error(`{what} failed ({r.code}): {r.stderr}{r.stdout}`, 2)
	end
	return r.stdout
end
local function stampOf(path: string): string
	local text = fixture.git(h.f.origin, { "show", `main:{path}` })
	return string.match(text, "\nstatus: ([%a%-]+)\n") or error(`{path} has no status on origin`)
end
local function pushBeat(stamp: string, epoch: number)
	local tree = fixture.git(h.f.other, { "rev-parse", "HEAD^{tree}" })
	local sha = fixture.git(h.f.other, { "commit-tree", tree, "-p", "HEAD", "-m", `hb {stamp} {epoch}` })
	fixture.git(h.f.other, { "push", "-q", "-f", "origin", `{sha}:refs/heads/hb/{stamp}` })
end
local function issue(id: string, status: string): string
	return trackerfix.stub(id, id, status)
end
-- the model a page embeds
local function boardModel(path: string): any
	t.expect(fs.isFile(path)).toBe(true) -- a build that wrote no page fails here, not on a missing file
	local page = fs.readFile(path)
	local json = string.match(page, '<script type="application/json" id="board%-data">(.-)</script>')
	return serde.decode("json", json :: string)
end
local function itemOf(model: any, id: string): any
	for _, list in { model.rafts, model.issues } do
		for _, i in list do
			if i.id == id then
				return i
			end
		end
	end
	error(`the board shows no {id}`)
end
local function position(list: { string }, id: string): number
	return table.find(list, id) or 0
end
local function counts(file: string, mark: string): number
	local text = if fs.isFile(`{h.fakes}/{file}`) then fs.readFile(`{h.fakes}/{file}`) else ""
	return #string.gsub(text, `[^{mark}]`, "")
end
local function warnings(text: string): number
	local n = 0
	for line in string.gmatch(text, "[^\n]+") do
		if string.sub(line, 1, 15) == "warning: board:" then
			n += 1
		end
	end
	return n
end
-- the notes a rebuilt page carries (why its marks are missing), as the model embeds them
local function notesOf(model: any): { string }
	return model.notes or {}
end
local function board(cwd: string, now: number?, out: string?): any
	local file = out or ".cache/board-c0276.html"
	must(zn(cwd, { "board", "--out", file, "-O" }, now), "board")
	return boardModel(`{cwd}/{file}`)
end

local GH = [[#!/bin/sh
if [ "$1" = pr ] && [ "$2" = list ]; then
  [ -f "$FAKE_DIR/ghfail" ] && { echo "gh: fake failure" >&2; exit 1; }
  cat "$FAKE_DIR/prs.json" 2>/dev/null || echo "[]"
  exit 0
fi
exit 0
]]
-- the git shim: the heartbeat read (a fetch into refs/zn/hb-seen) fails when lsfail exists and is counted in lscalls;
-- every fetch is counted in fetchcalls
local SHIM = [[#!/bin/sh
if [ "$1" = fetch ] && [ -f "$FAKE_DIR/mainfail" ]; then case "$*" in *"origin main"*) echo "fatal: fake unreachable origin" >&2; exit 128;; esac; fi
if [ "$1" = ls-tree ] && [ -f "$FAKE_DIR/noregistry" ]; then echo "fatal: fake unreadable registry" >&2; exit 128; fi
if [ "$1" = show ] && [ -f "$FAKE_DIR/noshow" ]; then case "$*" in *origin/main:pickman/.tracker/issues/*) echo "fatal: fake vanished document" >&2; exit 128;; esac; fi
if [ "$1" = fetch ]; then echo f >> "$FAKE_DIR/fetchcalls"; fi
if [ "$1" = fetch ] && [ -f "$FAKE_DIR/fetchlog" ]; then echo "$*" >> "$FAKE_DIR/fetchlog"; fi
if [ "$1" = push ] && [ -f "$FAKE_DIR/fetchlog" ]; then echo "$*" >> "$FAKE_DIR/fetchlog"; fi
if [ "$1" = fetch ]; then
  case "$*" in
    *hb-seen*)
      echo x >> "$FAKE_DIR/lscalls"
      [ -f "$FAKE_DIR/lsfail" ] && { echo "fatal: fake heartbeat read failure" >&2; exit 128; } ;;
  esac
fi
]]

return t.spec("c0276 board shows lost work", function(it)
	it("sets up claims of every verdict, a raft with a pull request and the fakes", function()
		h = fakecli.new("c0276-board", {
			[".gitignore"] = fs.readFile(`{TOP}/.gitignore`),
			["pickman/.tracker/architecture.md"] = "# architecture\n",
			[`{P}/c0010/c0010.md`] = issue("c0010", "new-a-b-c"),
			[`{P}/c0020/c0020.md`] = issue("c0020", "new-a-b-c"),
			[`{P}/c0030/c0030.md`] = issue("c0030", "new-a-b-c"),
			[`{P}/c0070/c0070.md`] = issue("c0070", "new-a-b-c"),
			[`{P}/c0080/c0080.md`] = issue("c0080", "new-a-b-c"),
			-- claimed before the heartbeat landed (the seed): lost once it has beaten, [no beat] until then
			[`{P}/c0050/c0050.md`] = issue("c0050", "preparing-lucky-violet-heron"),
			[`{P}/c0090/c0090.md`] = issue("c0090", "preparing-brisk-amber-otter"),
			-- two rafts: R0010 prepared and unclaimed, R0020 claimed by z-raft (rafting stamps the raft only)
			["pickman/.tracker/rafts/R0010/R0010.md"] = "---\nid: R0010\ntype: chore\ntitle: Plain\nslug: plain\nsingle: false\nissues: []\ndesign: ready\ncreated: 2026-10-06\nstatus: prepared-quiet-copper-falcon\n---\n\n# R0010\n",
			["pickman/.tracker/rafts/R0020/R0020.md"] = "---\nid: R0020\ntype: chore\ntitle: Rafting\nslug: rafting\nsingle: false\nissues: []\ndesign: draft\ncreated: 2026-10-06\nstatus: preparing-lucky-brisk-heron\n---\n\n# R0020\n",
		})
		fs.writeFile(`{h.bin}/gh`, GH)
		process.exec("chmod", { "+x", `{h.bin}/gh` })
		local real = fs.readFile(`{h.bin}/git`)
		fs.writeFile(`{h.bin}/git`, (string.gsub(real, "^#!/bin/sh\n", SHIM, 1)))
		wt = (string.gsub(must(zn(h.f.main, { "worktree", "c0276-board" }), "worktree"), "%s+$", ""))
		wt2 = (string.gsub(must(zn(h.f.main, { "worktree", "c0276-pub" }), "worktree"), "%s+$", ""))
		for _, id in { "c0010", "c0020", "c0030" } do
			must(zn(wt, { "status", id, "preparing" }, T0), `claim {id}`)
		end
		-- the beats, all another terminal's and all set last: c0050 is silent longest, c0010 next (against id order),
		-- c0020 is parked by its pull request, c0030 beat a minute ago
		pushBeat(stampOf(`{P}/c0050/c0050.md`), T0 + 100)
		pushBeat(stampOf("pickman/.tracker/rafts/R0020/R0020.md"), T0 + 200)
		pushBeat(stampOf(`{P}/c0010/c0010.md`), T0 + 570)
		pushBeat(stampOf(`{P}/c0020/c0020.md`), T0 + 60)
		pushBeat(stampOf(`{P}/c0030/c0030.md`), LATE - 60)
		fs.writeFile(
			`{h.fakes}/prs.json`,
			'[{"title":"tracker: prep c0020 Something","headRefName":"prep-something"}]'
		)
		-- a publish no longer brings the main checkout up to date or rebuilds its board: sync does (and the board is built
		-- from the checkout's own documents), so the claims reach the board through it
		must(zn(h.f.main, { "sync" }, LATE), "sync")
	end)

	it(
		"the board carries each verdict, lost work first in its bucket and band, longest silent first",
		function()
			local model = board(h.f.main, LATE)
			t.expect(model.notes).toBe(nil) -- nothing failed: nothing to say
			local c0050, c0010 = itemOf(model, "c0050"), itemOf(model, "c0010")
			t.expect(c0050.heartbeat).toBe("lost")
			t.expect(c0010.heartbeat).toBe("lost")
			-- minutes from each beat's own epoch: floored, as `lost` prints them
			t.expect(c0010.minutes).toBe(math.floor((LATE - (T0 + 570)) / 60))
			t.expect(c0050.minutes).toBe(math.floor((LATE - (T0 + 100)) / 60))
			t.expect(itemOf(model, "c0020").heartbeat).toBe("parked")
			-- a raft's own claim (rafting stamps the raft only) reaches the page, in the Rafts view
			t.expect(itemOf(model, "R0020").heartbeat).toBe("lost")
			t.expect(itemOf(model, "R0010").heartbeat).toBe(nil)
			t.expect(position(model.views.rafts["not"], "R0020") > 0).toBe(true)
			t.expect(itemOf(model, "c0090").heartbeat).toBe("nobeat")
			for _, id in { "c0030", "c0070", "c0080" } do
				t.expect(itemOf(model, id).heartbeat).toBe(nil) -- live, and not claimed
				t.expect(itemOf(model, id).minutes).toBe(nil)
			end
			local bucket = model.views.issues["not"]
			-- c0050 (silent longest) before c0010 although its id is higher, and both before the parked c0020
			t.expect(position(bucket, "c0050") > 0).toBe(true)
			t.expect(position(bucket, "c0050") < position(bucket, "c0010")).toBe(true)
			t.expect(position(bucket, "c0010") < position(bucket, "c0020")).toBe(true)
			-- the same inside the project board's band
			local banded = false
			for _, bands in model.columns.pickman do
				for _, band in bands do
					if table.find(band.ids, "c0050") and table.find(band.ids, "c0010") then
						banded = true
						t.expect(position(band.ids, "c0050") < position(band.ids, "c0010")).toBe(true)
					end
				end
			end
			t.expect(banded).toBe(true) -- both lost claims sit in one band of the project board
			-- the marks are exactly what ./zn status prints
			local listing = must(zn(h.f.main, { "status" }, LATE), "status")
			t.expect(has(listing, "[lost")).toBe(true)
		end
	)

	it("fresh claims leave every card without a mark", function()
		for _, id in { "c0010", "c0020", "c0030", "c0050" } do
			pushBeat(stampOf(`{P}/{id}/{id}.md`), LATE + 10)
		end
		pushBeat(stampOf("pickman/.tracker/rafts/R0020/R0020.md"), LATE + 10)
		local model = board(h.f.main, LATE + 20)
		for _, list in { model.issues, model.rafts } do
			for _, i in list do
				if i.id ~= "c0090" then -- never beaten, made before the landing: [no beat], not live
					t.expect(i.heartbeat).toBe(nil)
				end
			end
		end
		pushBeat(stampOf(`{P}/c0010/c0010.md`), T0 + 570) -- back to the first cases' beats
		pushBeat(stampOf(`{P}/c0020/c0020.md`), T0 + 60)
		pushBeat(stampOf(`{P}/c0050/c0050.md`), T0 + 100)
		pushBeat(stampOf("pickman/.tracker/rafts/R0020/R0020.md"), T0 + 200)
	end)

	it("the board a main-checkout sync rebuilds carries the verdicts", function()
		fs.removeFile(`{h.f.main}/.cache/board.html`)
		trackerfix.elsewhere(
			h.f,
			{ [`{P}/c0081/c0081.md`] = issue("c0081", "new-a-b-c") },
			"another terminal's issue"
		)
		must(zn(h.f.main, { "sync" }, LATE), "sync")
		local model = boardModel(`{h.f.main}/.cache/board.html`)
		t.expect(itemOf(model, "c0081").title).toBe("c0081") -- the sync brought it in
		t.expect(itemOf(model, "c0050").heartbeat).toBe("lost")
		t.expect(itemOf(model, "c0020").heartbeat).toBe("parked")
	end)

	it(
		"unreadable pull requests leave stale claims stale (never lost), and the board still builds",
		function()
			fs.writeFile(`{h.fakes}/ghfail`, "1")
			local r = zn(h.f.main, { "board", "--out", ".cache/board-pr.html", "-O" }, LATE)
			fs.removeFile(`{h.fakes}/ghfail`)
			t.expect(r.ok).toBe(true)
			t.expect(has(r.stderr, "pull requests unreadable")).toBe(true)
			t.expect(warnings(r.stderr)).toBe(1)
			local model = boardModel(`{h.f.main}/.cache/board-pr.html`)
			t.expect(#notesOf(model)).toBe(1)
			t.expect(has(notesOf(model)[1], "pull requests unreadable")).toBe(true)
			for _, id in { "c0010", "c0020", "c0050" } do
				t.expect(itemOf(model, id).heartbeat).toBe("stale")
			end
		end
	)

	it("unreadable heartbeats build the board without marks and say so once", function()
		fs.writeFile(`{h.fakes}/lsfail`, "1")
		local r = zn(h.f.main, { "board", "--out", ".cache/board-hb.html", "-O" }, LATE)
		fs.removeFile(`{h.fakes}/lsfail`)
		t.expect(r.ok).toBe(true)
		t.expect(has(r.stderr, "heartbeats unreadable")).toBe(true)
		t.expect(warnings(r.stderr)).toBe(1) -- said once, not once per claim
		local model = boardModel(`{h.f.main}/.cache/board-hb.html`)
		t.expect(#notesOf(model)).toBe(1) -- and the page says so, not only the stderr of whoever built it
		t.expect(has(notesOf(model)[1], "heartbeats unreadable")).toBe(true)
		for _, list in { model.issues, model.rafts } do
			for _, i in list do
				t.expect(i.heartbeat).toBe(nil)
			end
		end
		-- and a sync whose rebuild cannot read them still syncs, and the page it rebuilds says why it has no marks
		fs.removeFile(`{h.f.main}/.cache/board.html`)
		fs.writeFile(`{h.fakes}/lsfail`, "1")
		local pub = zn(h.f.main, { "sync" }, LATE)
		fs.removeFile(`{h.fakes}/lsfail`)
		t.expect(pub.ok).toBe(true)
		local rebuilt = boardModel(`{h.f.main}/.cache/board.html`)
		t.expect(#notesOf(rebuilt)).toBe(1)
		t.expect(itemOf(rebuilt, "c0010").heartbeat).toBe(nil)
	end)

	it("an unreachable origin builds the board without marks, exits 0 and warns once", function()
		fs.writeFile(`{h.fakes}/mainfail`, "1")
		local r = zn(h.f.main, { "board", "--out", ".cache/board-main.html", "-O" }, LATE)
		fs.removeFile(`{h.fakes}/mainfail`)
		t.expect(r.ok).toBe(true)
		t.expect(warnings(r.stderr)).toBe(1)
		t.expect(has(r.stderr, "origin/main could not be read")).toBe(true)
		local model = boardModel(`{h.f.main}/.cache/board-main.html`)
		t.expect(#notesOf(model)).toBe(1)
		t.expect(has(notesOf(model)[1], "origin/main could not be read")).toBe(true)
		t.expect(itemOf(model, "c0010").heartbeat).toBe(nil)
	end)

	it("a document another checkout moved between two reads is one warning, never a failed build", function()
		fs.writeFile(`{h.fakes}/noshow`, "1")
		local r = zn(h.f.main, { "board", "--out", ".cache/board-show.html", "-O" }, LATE)
		fs.removeFile(`{h.fakes}/noshow`)
		t.expect(r.ok).toBe(true)
		t.expect(warnings(r.stderr)).toBe(1)
		t.expect(has(r.stderr, "could not be read; built without them")).toBe(true)
		t.expect(fs.isFile(`{h.f.main}/.cache/board-show.html`)).toBe(true)
		t.expect(itemOf(boardModel(`{h.f.main}/.cache/board-show.html`), "c0010").heartbeat).toBe(nil)
		t.expect(
			has(
				notesOf(boardModel(`{h.f.main}/.cache/board-show.html`))[1] or "",
				"could not be read; built without them"
			)
		).toBe(true)
		-- a rebuild (main-checkout sync) whose reads throw still writes its page, with the note
		fs.removeFile(`{h.f.main}/.cache/board.html`)
		fs.writeFile(`{h.fakes}/noshow`, "1")
		local synced = zn(h.f.main, { "sync" }, LATE)
		fs.removeFile(`{h.fakes}/noshow`)
		t.expect(synced.ok).toBe(true)
		t.expect(fs.isFile(`{h.f.main}/.cache/board.html`)).toBe(true)
		t.expect(
			has(
				notesOf(boardModel(`{h.f.main}/.cache/board.html`))[1] or "",
				"could not be read; built without them"
			)
		).toBe(true)
	end)

	it("a malformed beat branch names its cure in one warning and leaves stale claims stale", function()
		fixture.git(h.f.other, { "push", "-q", "origin", "HEAD:refs/heads/hb/garbage" })
		local r = zn(h.f.main, { "board", "--out", ".cache/board-garbage.html", "-O" }, LATE)
		fixture.git(h.f.other, { "push", "-q", "origin", ":refs/heads/hb/garbage" })
		t.expect(r.ok).toBe(true)
		t.expect(warnings(r.stderr)).toBe(1)
		t.expect(has(r.stderr, "git push origin :refs/heads/hb/garbage")).toBe(true)
		local model = boardModel(`{h.f.main}/.cache/board-garbage.html`)
		t.expect(#notesOf(model)).toBe(1)
		t.expect(has(notesOf(model)[1], "git push origin :refs/heads/hb/garbage")).toBe(true)
		t.expect(itemOf(model, "c0010").heartbeat).toBe("stale")
		t.expect(itemOf(model, "c0050").heartbeat).toBe("stale")
	end)

	it("a rebuild after a sync does not fetch origin main a second time", function()
		trackerfix.elsewhere(
			h.f,
			{ [`{P}/c0082/c0082.md`] = issue("c0082", "new-a-b-c") },
			"another terminal's issue"
		)
		fs.writeFile(`{h.fakes}/fetchlog`, "")
		must(zn(h.f.main, { "sync" }, LATE), "sync")
		local mainFetches = 0
		for line in string.gmatch(fs.readFile(`{h.fakes}/fetchlog`), "[^\n]+") do
			if string.sub(line, 1, 5) == "fetch" and has(line, "main") then
				mainFetches += 1 -- any spelling of main
			end
		end
		t.expect(mainFetches).toBe(1) -- sync's own; the rebuild trusts it
	end)

	it("without an origin to publish to nothing is read and nothing is said", function()
		local lsBefore, fetchBefore = counts("lscalls", "x"), counts("fetchcalls", "f")
		local r = zn(
			h.f.main,
			{ "board", "--out", ".cache/board-nopub.html", "-O" },
			LATE,
			{ PICKMAN_PUBLISH = "0" }
		)
		t.expect(r.ok).toBe(true)
		t.expect(r.stderr).toBe("")
		t.expect(itemOf(boardModel(`{h.f.main}/.cache/board-nopub.html`), "c0010").heartbeat).toBe(nil)
		t.expect(boardModel(`{h.f.main}/.cache/board-nopub.html`).notes).toBe(nil) -- nothing was tried: nothing to say
		t.expect(counts("lscalls", "x")).toBe(lsBefore)
		t.expect(counts("fetchcalls", "f")).toBe(fetchBefore)
	end)

	it("a checkout with no origin at all reads nothing and says nothing", function()
		local solo = `{h.f.base}/solo`
		fixture.git(h.f.main, { "clone", "-q", h.f.main, solo })
		fixture.git(solo, { "remote", "remove", "origin" })
		local lsBefore, fetchBefore = counts("lscalls", "x"), counts("fetchcalls", "f")
		local r = zn(solo, { "board", "--out", ".cache/board-solo.html", "-O" }, LATE)
		t.expect(r.ok).toBe(true)
		t.expect(r.stderr).toBe("")
		local model = boardModel(`{solo}/.cache/board-solo.html`)
		t.expect(model.notes).toBe(nil)
		t.expect(itemOf(model, "c0010").heartbeat).toBe(nil)
		t.expect(counts("lscalls", "x")).toBe(lsBefore)
		t.expect(counts("fetchcalls", "f")).toBe(fetchBefore)
	end)

	it("an unreadable registry on origin builds the board without marks and warns once", function()
		fs.writeFile(`{h.fakes}/noregistry`, "1")
		local r = zn(h.f.main, { "board", "--out", ".cache/board-reg.html", "-O" }, LATE)
		fs.removeFile(`{h.fakes}/noregistry`)
		t.expect(r.ok).toBe(true)
		t.expect(warnings(r.stderr)).toBe(1)
		t.expect(has(r.stderr, "projects could not be read")).toBe(true)
		t.expect(itemOf(boardModel(`{h.f.main}/.cache/board-reg.html`), "c0010").heartbeat).toBe(nil)
		t.expect(
			has(
				notesOf(boardModel(`{h.f.main}/.cache/board-reg.html`))[1] or "",
				"projects could not be read"
			)
		)
			.toBe(true)
	end)

	it("a protected checkout reads no remote for the board: no marks, no fetch", function()
		local lsBefore, fetchBefore = counts("lscalls", "x"), counts("fetchcalls", "f")
		-- the guards in the main checkout answer "guarded" (the fixture's own copy of fence.sh)
		local fence = `{h.f.main}/z-nile/lib/fence.sh`
		local original = fs.readFile(fence)
		fs.writeFile(fence, original .. "\npickman_guarded() { echo guarded; }\n")
		local r = zn(h.f.main, { "board", "--out", ".cache/board-guarded.html", "-O" }, LATE)
		fs.writeFile(fence, original)
		t.expect(r.ok).toBe(true)
		t.expect(r.stderr).toBe("") -- the guards' saying is the commands' that publish, not the board's
		local model = boardModel(`{h.f.main}/.cache/board-guarded.html`)
		t.expect(model.notes).toBe(nil)
		for _, list in { model.issues, model.rafts } do
			for _, i in list do
				t.expect(i.heartbeat).toBe(nil)
			end
		end
		t.expect(counts("lscalls", "x")).toBe(lsBefore) -- no read of the heartbeat branches
		t.expect(counts("fetchcalls", "f")).toBe(fetchBefore) -- and no fetch at all
	end)
end)
