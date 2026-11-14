-- c0265 split: cases of lost.spec (monolithic version) that belong to c0275. Not runnable alone: the file's

-- header, helpers, shim and setup are in ../lost.spec.orig. They never ran against an implementation.



	it("a failed first beat does not fail the claim", function()
		fs.writeFile(`{h.fakes}/lsfail`, "1")
		local r = zn(wt2, { "status", "c0075", "preparing" }, LATE)
		fs.removeFile(`{h.fakes}/lsfail`)
		t.expect(r.ok).toBe(true)
		t.expect(has(r.stderr, "beat: c0075:")).toBe(true) -- said, with the item named (not the board's own note)
		-- and the worktree still keeps the claim alive: the failed attempt wrote its throttle entry
		t.expect(fs.isFile(`{wt2}/.cache/tracker-beats/c0075`)).toBe(true)
		t.expect(string.sub(stampOf(`{P}/c0075/c0075.md`), 1, 10)).toBe("preparing-")
		t.expect(table.find(stampsWithBeats(), stampOf(`{P}/c0075/c0075.md`))).toBe(nil)
	end)

	it("a failed beat attempt is not retried inside the interval", function()
		local function calls(): number
			local text = if fs.isFile(`{h.fakes}/lscalls`) then fs.readFile(`{h.fakes}/lscalls`) else ""
			return #string.gsub(text, "[^x]", "")
		end
		fs.writeFile(`{h.fakes}/lsfail`, "1")
		local due = LATE + 4 * STALE
		local before = calls()
		must(zn(wt, { "lessons", "--tags" }, due), "lessons in the worktree") -- entries are due: one failed attempt each
		local first = calls()
		t.expect(first > before).toBe(true)
		must(zn(wt, { "lessons", "--tags" }, due + 10), "lessons again, inside the interval")
		t.expect(calls()).toBe(first) -- the failed attempt advanced the entries: nothing more is tried
		fs.removeFile(`{h.fakes}/lsfail`)
	end)

	it("an entry for a claim that merely ended is dropped with 'claim ended', not 'taken over'", function()
		local at = LATE + 12 * STALE
		local c0070Stamp = stampOf(`{P}/c0070/c0070.md`)
		t.expect(tipOf(c0070Stamp) ~= "").toBe(true)
		must(zn(wt2, { "status", "c0070", "new" }, at), "give c0070 back") -- wt2 claimed it earlier and holds an entry
		local told = zn(wt2, { "lessons", "--tags" }, at + 10)
		t.expect(told.ok).toBe(true)
		t.expect(has(told.stderr, "c0070's claim ended")).toBe(true)
		t.expect(has(told.stderr, "c0070's claim was taken over")).toBe(false)
		t.expect(fs.isFile(`{wt2}/.cache/tracker-beats/c0070`)).toBe(false)
		t.expect(tipOf(c0070Stamp)).toBe("") -- giving the claim back deleted its heartbeat branch
	end)
