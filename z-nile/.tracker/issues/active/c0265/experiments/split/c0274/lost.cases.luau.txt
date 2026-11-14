-- c0265 split: cases of lost.spec (monolithic version) that belong to c0274. Not runnable alone: the file's

-- header, helpers, shim and setup are in ../lost.spec.orig. They never ran against an implementation.



	it("a takeover is refused for a live claim, a parked one, and whenever the answer is unknown", function()
		must(zn(h.f.main, { "beat", "c0010", "--adopt" }, LATE + 6 * STALE), "keep c0010 alive")
		local live = zn(wt2, { "status", "c0010", "preparing" }, LATE + 6 * STALE + 10)
		t.expect(live.ok).toBe(false)
		t.expect(has(live.stderr, "is preparing on origin/main")).toBe(true)
		t.expect(has(live.stderr, "heartbeat")).toBe(true)
		local parked = zn(wt2, { "status", "c0020", "preparing" }, LATE + 9 * STALE)
		t.expect(parked.ok).toBe(false)
		t.expect(has(parked.stderr, "parked")).toBe(true)
		-- unknown: pull requests unreadable, beats unreadable, a malformed beat ref on origin
		local at = LATE + 9 * STALE
		fs.writeFile(`{h.fakes}/ghfail`, "1")
		t.expect(zn(wt2, { "status", "c0010", "preparing" }, at).ok).toBe(false)
		fs.removeFile(`{h.fakes}/ghfail`)
		fs.writeFile(`{h.fakes}/lsfail`, "1")
		local blind = zn(wt2, { "status", "c0010", "preparing" }, at)
		t.expect(blind.ok).toBe(false)
		t.expect(has(blind.stderr, "heartbeat")).toBe(true)
		fs.removeFile(`{h.fakes}/lsfail`)
		fixture.git(h.f.other, { "push", "-q", "origin", "HEAD:refs/heads/hb/garbage" })
		local bad = zn(wt2, { "status", "c0010", "preparing" }, at)
		t.expect(bad.ok).toBe(false)
		t.expect(has(bad.stderr, "refs/heads/hb/garbage")).toBe(true)
		-- a malformed ref makes every stale claim unknown, everywhere, and the message says how to clear it
		t.expect(has(bad.stderr, "git push origin :refs/heads/hb/garbage")).toBe(true)
		local still = zn(h.f.main, { "lost" }, at)
		t.expect(has(still.stdout, "c0010")).toBe(false)
		t.expect(has(still.stderr, "refs/heads/hb/garbage")).toBe(true)
		t.expect(has(lineOf(zn(h.f.main, { "status" }, at).stdout, "c0010"), "[stale?]")).toBe(true)
		fixture.git(h.f.other, { "push", "-q", "origin", ":refs/heads/hb/garbage" })
	end)

	it(
		"a lost claim is taken over with a fresh stamp, a first beat, and the old claim's beats pruned",
		function()
			local at = LATE + 9 * STALE
			local before = stampOf(`{P}/c0010/c0010.md`)
			must(zn(wt2, { "status", "c0010", "preparing" }, at), "takeover of a lost claim")
			local after = stampOf(`{P}/c0010/c0010.md`)
			t.expect(after ~= before).toBe(true)
			-- the takeover is recorded in the claim commit's subject: who it took the claim from
			t.expect(subjectOf(`{P}/c0010/c0010.md`)).toBe(`tracker: c0010 preparing (takes over {before})`)
			local stamps = stampsWithBeats()
			t.expect(table.find(stamps, after) ~= nil).toBe(true)
			-- the takeover deleted the old owner's branch and created its own in one push
			t.expect(table.find(stamps, before)).toBe(nil)
			t.expect(tipOf(before)).toBe("")
		end
	)

	it("a lost rafting claim is taken over the same way, its member following", function()
		local at = LATE + 9 * STALE
		local listing = must(zn(h.f.main, { "status" }, at), "status")
		local rid = string.match(listing, "(R%d+) preparing") or error("no rafting claim in the status list")
		raftId = rid
		local doc = `pickman/.tracker/rafts/{rid}/{rid}.md`
		local before = stampOf(doc)
		must(zn(wt2, { "status", rid, "preparing" }, at), "takeover of a rafting claim")
		local after = stampOf(doc)
		t.expect(after ~= before).toBe(true)
		t.expect(stampOf(`{P}/c0030/c0030.md`)).toBe(after)
		t.expect(subjectOf(doc)).toBe(`tracker: {rid} preparing (takes over {before})`)
		t.expect(table.find(stampsWithBeats(), after) ~= nil).toBe(true)
		-- the taker holds the stamp but not the rafting ownership: release needs --force, as after any status R preparing
		local rel = zn(wt2, { "release", rid }, at)
		t.expect(rel.ok).toBe(false)
		t.expect(has(rel.stderr, "not this checkout's")).toBe(true)
	end)

	it(
		"the taker's own carried move passes, because a takeover records the new stamp in its checkout",
		function()
			local doc = `{wt2}/{P}/c0010/c0010.md`
			must(zn(wt2, { "sync" }, LATE + 9 * STALE), "sync")
			fs.writeFile(doc, (string.gsub(fs.readFile(doc), "design: draft", "design: ready")))
			must(zn(wt2, { "status", "c0010", "prepared" }, LATE + 9 * STALE), "the taker's carried move")
		end
	)

	it("the old claimant's carried move is refused, and its worktree stops beating what it lost", function()
		local at = LATE + 9 * STALE
		local doc = `{wt}/{P}/c0010/c0010.md`
		-- the first command the old claimant runs tells it, once, and drops its entry (the stamp check comes first)
		local sync = zn(wt, { "sync" }, at)
		must(sync, "sync")
		t.expect(has(sync.stderr, "c0010's claim was taken over")).toBe(true)
		t.expect(has(sync.stderr, `{raftId}'s claim was taken over`)).toBe(true) -- the rafting claim too, by the same sync
		t.expect(fs.isFile(`{wt}/.cache/tracker-beats/c0010`)).toBe(false)
		fs.writeFile(doc, (string.gsub(fs.readFile(doc), "design: draft", "design: ready")))
		local r = zn(wt, { "status", "c0010", "prepared" }, at)
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stderr, "taken over")).toBe(true)
		-- coming back by an explicit beat or a restarted loop does not adopt the taker's claim: wt remembers the old stamp
		local tipTaken = tipOf(stampOf(`{P}/c0010/c0010.md`))
		local comeBack = zn(wt, { "beat", "c0010" }, at)
		t.expect(comeBack.ok).toBe(false)
		t.expect(has(comeBack.stderr, "c0010's claim was taken over")).toBe(true)
		-- an adoption never overrides a remembered different stamp: --adopt in the old owner's own checkout is told too
		local adopt = zn(wt, { "beat", "c0010", "--adopt" }, at)
		t.expect(adopt.ok).toBe(false)
		t.expect(has(adopt.stderr, "c0010's claim was taken over")).toBe(true)
		local loop = zn(
			wt,
			{ "beat", "c0010", "--watch" },
			at,
			{ ZN_BOUNDED_DEADLINE = tostring(os.time() + 600) }
		)
		t.expect(loop.ok).toBe(false)
		t.expect(has(loop.stderr, "c0010's claim was taken over")).toBe(true)
		t.expect(tipOf(stampOf(`{P}/c0010/c0010.md`))).toBe(tipTaken) -- the taker's branch was not touched
		-- the old rafting claimant (wt made it with `new raft`) is refused its carried move too. The stamp-record check
		-- runs before setStatus' member design check, so c0030 left at design: draft does not change the answer
		local rdoc = `{wt}/pickman/.tracker/rafts/{raftId}/{raftId}.md`
		fs.writeFile(rdoc, (string.gsub(fs.readFile(rdoc), "design: draft", "design: ready")))
		local oldRaft = zn(wt, { "status", raftId, "prepared" }, at)
		t.expect(oldRaft.ok).toBe(false)
		t.expect(has(oldRaft.stderr, "taken over")).toBe(true)
		-- an interval later its autobeat sees another stamp on origin: it drops the entry and writes no beat
		local taken = stampOf(`{P}/c0010/c0010.md`)
		local before = #beatRefs()
		local tipBefore = tipOf(taken)
		local told = zn(wt, { "lessons", "--tags" }, at + 2 * STALE)
		t.expect(told.ok).toBe(true)
		t.expect(has(told.stderr, "c0010's claim was taken over")).toBe(false) -- told once, by the first command
		t.expect(#beatRefs()).toBe(before) -- no branch came back for the old stamp, none was added
		t.expect(tipOf(taken)).toBe(tipBefore) -- and the taker's branch was not touched by the old owner
	end)

	it(
		"a lost readied raft is taken over by stop and ready: the old branch goes, a fresh active stamp and branch come, and the stop records the lost stamp",
		function()
			local at = LATE + 14 * STALE
			fs.writeFile(`{h.fakes}/prs.json`, "[]") -- no pull request names R0010 any more
			local doc = "pickman/.tracker/rafts/active/R0010/R0010.md"
			local old = stampOf(doc)
			t.expect(tipOf(old) ~= "").toBe(true)
			t.expect(has(zn(h.f.main, { "lost" }, at).stdout, "R0010 active")).toBe(true)
			must(zn(h.f.main, { "stop", "R0010" }, at), "stop")
			t.expect(tipOf(old)).toBe("") -- stop dropped the heartbeat branch
			t.expect(
				fixture.git(
					h.f.origin,
					{ "log", "-1", "--format=%s", "main", "--", "pickman/.tracker/rafts/R0010/R0010.md" }
				)
			).toBe(`tracker: stop R0010 (claim {old})`)
			must(zn(h.f.main, { "ready", "R0010" }, at + 10), "ready")
			local new = stampOf(doc)
			t.expect(new ~= old).toBe(true)
			t.expect(tipOf(new) ~= "").toBe(true) -- the new claim's first beat
			t.expect(tipOf(old)).toBe("")
		end
	)
