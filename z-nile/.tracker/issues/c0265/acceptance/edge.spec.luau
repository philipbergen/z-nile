--!strict
-- c0265: what a blocking fixture can force with a `git` shim that acts on one named push or read: a beat that races a
-- takeover (another terminal restamps the item and swaps the heartbeat branches) is rejected by its lease and the beater
-- learns it lost the claim; a create-only beat that races one deletes what it created; a lease rejection from a co-beater
-- of the same claim is retried silently. Instant cases. Fixture under .cache/c0265-edge.
local fakecli = require("@tests/lib/fakecli")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local h: fakecli.Harness
local wt = ""
local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local P = "pickman/.tracker/issues"

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end
local function zn(cwd: string, args: { string }, extra: { [string]: string }?): fixture.Result
	local env: { [string]: string } = {
		FAKE_DIR = h.fakes,
		FAKE_OTHER = h.f.other,
		PATH = `{h.bin}:{process.env.PATH}`,
		ZN_AGENT_TOKEN_FILE = h.token,
		ZN_WATERMARK_DIR = `{h.f.base}/watermark`,
	}
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
-- the epochs of the beats origin holds for `stamp` (one branch per claim, the epoch in its commit subject)
local function epochs(stamp: string): { number }
	local out = {}
	local subjects =
		fixture.git(h.f.origin, { "for-each-ref", "--format=%(subject)", `refs/heads/hb/{stamp}` })
	for line in string.gmatch(subjects, "[^\n]+") do
		table.insert(out, tonumber(string.match(line, "(%d+)$")) :: number)
	end
	return out
end
local function tipOf(stamp: string): string
	return fixture.git(h.f.origin, { "for-each-ref", "--format=%(objectname)", `refs/heads/hb/{stamp}` })
end
local function issue(id: string, status: string, design: string?, raft: string?): string
	local doc = string.gsub(trackerfix.stub(id, id, status), "design: draft", `design: {design or "draft"}`)
	return (string.gsub(doc, "\nraft: \n", `\nraft: {raft or ""}\n`, 1))
end
local GH = '#!/bin/sh\n[ "$1" = pr ] && [ "$2" = list ] && echo "[]"\nexit 0\n'
-- the shim acts on one push at a time, each armed by a marker file it removes first (answers only what it names)
local SHIM = [[#!/bin/sh
# another terminal takes $FAKE_ITEM's claim over: it restamps the item on main and, in one atomic push, deletes the old
# owner's branch and creates its own
takeover() {
  o="$FAKE_OTHER"; f="$o/pickman/.tracker/issues/$FAKE_ITEM/$FAKE_ITEM.md"
  "$REAL_GIT" -C "$o" pull -q origin main
  sed -i.bak "s/^status: .*/status: $FAKE_NEWSTAMP/" "$f"; rm -f "$f.bak"
  "$REAL_GIT" -C "$o" add -A; "$REAL_GIT" -C "$o" -c user.name=race -c user.email=race@example.invalid commit -q -m takeover
  "$REAL_GIT" -C "$o" push -q origin HEAD:main
  tree=$("$REAL_GIT" -C "$o" rev-parse "HEAD^{tree}")
  new=$("$REAL_GIT" -C "$o" -c user.name=race -c user.email=race@example.invalid commit-tree "$tree" -p HEAD -m "hb $FAKE_NEWSTAMP 1")
  if "$REAL_GIT" -C "$o" ls-remote --exit-code origin "refs/heads/hb/$FAKE_OLDSTAMP" >/dev/null 2>&1; then
    "$REAL_GIT" -C "$o" push -q --atomic origin ":refs/heads/hb/$FAKE_OLDSTAMP" "$new:refs/heads/hb/$FAKE_NEWSTAMP"
  else
    "$REAL_GIT" -C "$o" push -q origin "$new:refs/heads/hb/$FAKE_NEWSTAMP"
  fi
}
if [ "$1" = push ]; then
  case "$*" in
    *":refs/heads/hb/$FAKE_OLDSTAMP"*)
      echo p >> "$FAKE_DIR/oldpushes"
      if [ -f "$FAKE_DIR/racebeat" ]; then rm -f "$FAKE_DIR/racebeat"; takeover; fi
      if [ -f "$FAKE_DIR/cobeat" ]; then
        rm -f "$FAKE_DIR/cobeat"
        # a co-beater of the SAME claim replaces the branch just before this push: a harmless lease rejection
        o="$FAKE_OTHER"; tree=$("$REAL_GIT" -C "$o" rev-parse "HEAD^{tree}")
        new=$("$REAL_GIT" -C "$o" -c user.name=race -c user.email=race@example.invalid commit-tree "$tree" -p HEAD -m "hb $FAKE_OLDSTAMP 7")
        "$REAL_GIT" -C "$o" push -q -f origin "$new:refs/heads/hb/$FAKE_OLDSTAMP"
      fi ;;
  esac
fi
]]

return t.spec("c0265 beat races", function(it)
	it("sets up claims and the shim", function()
		h = fakecli.new("c0265-edge", {
			[".gitignore"] = fs.readFile(`{TOP}/.gitignore`),
			["pickman/.tracker/architecture.md"] = "# architecture\n",
			[`{P}/c0071/c0071.md`] = issue("c0071", "new-a-b-c"),
			[`{P}/c0072/c0072.md`] = issue("c0072", "new-a-b-c"),
			[`{P}/c0073/c0073.md`] = issue("c0073", "new-a-b-c"),
		})
		fs.writeFile(`{h.bin}/gh`, GH)
		process.exec("chmod", { "+x", `{h.bin}/gh` })
		local real = string.match(fs.readFile(`{h.bin}/git`), 'exec "([^"]+)" "%$@"')
			or error("no real git in the shim")
		fs.writeFile(
			`{h.bin}/git`,
			(
				string.gsub(
					fs.readFile(`{h.bin}/git`),
					"^#!/bin/sh\n",
					"#!/bin/sh\nREAL_GIT='" .. real .. "'; export REAL_GIT\n" .. string.sub(SHIM, 11),
					1
				)
			)
		)
		wt = (string.gsub(must(zn(h.f.main, { "worktree", "c0265-edge" }), "worktree"), "%s+$", ""))
		must(zn(wt, { "status", "c0071", "preparing" }), "claim c0071")
		must(zn(wt, { "status", "c0072", "preparing" }), "claim c0072")
		must(zn(wt, { "status", "c0073", "preparing" }), "claim c0073")
		-- each claim has a beat on origin: the branch a later beat replaces with a lease
		for _, id in { "c0071", "c0073" } do
			must(zn(wt, { "beat", id }, { ZN_NOW = tostring(os.time()) }), `first beat of {id}`)
		end
	end)

	it(
		"a beat that races a takeover is rejected by its lease: the old owner learns it lost the claim",
		function()
			local old = stampOf(`{P}/c0071/c0071.md`)
			local new = "preparing-mellow-badger-jolly"
			t.expect(tipOf(old) ~= "").toBe(true) -- the first beat made its branch: the next beat replaces it with a lease
			fs.writeFile(`{h.fakes}/racebeat`, "1")
			fs.writeFile(`{h.fakes}/oldpushes`, "")
			local told = zn(wt, { "beat", "c0071" }, {
				ZN_NOW = tostring(os.time() + 1000),
				FAKE_ITEM = "c0071",
				FAKE_OLDSTAMP = old,
				FAKE_NEWSTAMP = new,
			})
			t.expect(told.ok).toBe(false) -- the beater learns it lost the claim
			t.expect(has(told.stderr, `c0071's claim was taken over (now {new})`)).toBe(true)
			t.expect(stampOf(`{P}/c0071/c0071.md`)).toBe(new)
			t.expect(tipOf(old)).toBe("") -- the old owner's push was rejected: it did not recreate its branch
			-- and it learned from the rejection: one push to its branch, no second try on a claim it lost
			t.expect(#string.gsub(fs.readFile(`{h.fakes}/oldpushes`), "[^p]", "")).toBe(1)
			t.expect(tipOf(new) ~= "").toBe(true) -- the taker's branch stands, untouched by the old owner
			t.expect(epochs(new)).toEqual({ 1 })
		end
	)

	it("a create-only beat that races a takeover deletes what it created and reports the loss", function()
		local old = stampOf(`{P}/c0072/c0072.md`)
		local new = "preparing-silver-otter-quiet"
		-- c0072 was never beaten: its write is create-only. The takeover lands between the beat's reads and its push,
		-- so the write succeeds; the re-read of main shows another stamp and the beat deletes what it created
		fs.writeFile(`{h.fakes}/racebeat`, "1")
		local r = zn(wt, { "beat", "c0072" }, {
			ZN_NOW = tostring(os.time() + 1000),
			FAKE_ITEM = "c0072",
			FAKE_OLDSTAMP = old,
			FAKE_NEWSTAMP = new,
		})
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stderr, `c0072's claim was taken over (now {new})`)).toBe(true)
		t.expect(tipOf(old)).toBe("") -- what it created was deleted again
		t.expect(tipOf(new) ~= "").toBe(true) -- the taker's branch stands
		t.expect(epochs(new)).toEqual({ 1 })
	end)

	it("a lease rejection caused by a co-beater of the same claim retries silently and succeeds", function()
		local stamp = stampOf(`{P}/c0073/c0073.md`)
		fs.writeFile(`{h.fakes}/cobeat`, "1")
		local due = os.time() + 1000
		local told = zn(wt, { "beat", "c0073" }, { ZN_NOW = tostring(due), FAKE_OLDSTAMP = stamp })
		t.expect(told.ok).toBe(true)
		t.expect(has(told.stderr, "beat: c0073")).toBe(false) -- a "stale info" rejection is not worth saying
		t.expect(epochs(stamp)).toEqual({ due }) -- and the retry wrote this beat over the co-beater's
	end)
end)
