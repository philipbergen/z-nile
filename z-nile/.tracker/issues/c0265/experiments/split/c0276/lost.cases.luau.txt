-- c0265 split: cases of lost.spec (monolithic version) that belong to c0276. Not runnable alone: the file's

-- header, helpers, shim and setup are in ../lost.spec.orig. They never ran against an implementation.



	it(
		"the board's model carries each verdict, lost work first in its bucket, and none while claims are fresh",
		function()
			local out = `{h.f.main}/.cache/board-lost.html`
			must(zn(h.f.main, { "board", "--out", ".cache/board-lost.html", "-O" }, LATE), "board")
			local model = boardModel(out)
			local c0010 = itemOf(model, "c0010")
			t.expect(c0010.heartbeat).toBe("lost")
			-- minutes from each input's own clock: the last beat is dated T0 + 600, the claim landed earlier
			local landed = tonumber(
				fixture.git(h.f.origin, { "log", "-1", "--format=%ct", "main", "--", `{P}/c0010/c0010.md` })
			)
			t.expect(c0010.minutes).toBe(math.floor((LATE - math.max(landed :: number, T0 + 600)) / 60))
			t.expect(itemOf(model, "c0020").heartbeat).toBe("parked") -- a pull request names it
			t.expect(itemOf(model, "R0010").heartbeat).toBe("parked") -- a pull request names only the raft
			t.expect(itemOf(model, "c0070").heartbeat).toBe(nil) -- not claimed: no verdict
			-- lost work comes first within its bucket: c0050 (lost) before c0020 (parked), against id order
			local bucket = model.views.issues["not"]
			local lostAt, parkedAt = table.find(bucket, "c0050") or 0, table.find(bucket, "c0020") or 0
			t.expect(lostAt > 0 and parkedAt > 0 and lostAt < parkedAt).toBe(true)
			-- and longest silent first among the lost: c0050 (silent longest) before c0010 although its id is higher
			local firstAt, secondAt = table.find(bucket, "c0050") or 0, table.find(bucket, "c0010") or 0
			t.expect(firstAt > 0 and secondAt > 0 and firstAt < secondAt).toBe(true)
			-- pull requests that cannot be read: stale, shown as unconfirmed, never lost
			fs.writeFile(`{h.fakes}/ghfail`, "1")
			must(
				zn(h.f.main, { "board", "--out", ".cache/board-lost.html", "-O" }, LATE),
				"board, no pull requests"
			)
			t.expect(itemOf(boardModel(out), "c0010").heartbeat).toBe("stale")
			fs.removeFile(`{h.fakes}/ghfail`)
			-- fresh claims: no item carries a verdict
			must(
				zn(h.f.main, { "board", "--out", ".cache/board-lost.html", "-O" }, T0 + 60),
				"board while fresh"
			)
			local fresh = boardModel(out)
			for _, list in { fresh.issues, fresh.rafts } do
				for _, item in list do
					t.expect(item.heartbeat).toBe(nil)
				end
			end
		end
	)

	it("the board every publish rebuilds carries the verdicts too", function()
		must(zn(wt2, { "status", "c0070", "preparing" }, LATE), "a publish")
		local model = boardModel(`{h.f.main}/.cache/board.html`)
		t.expect(itemOf(model, "c0010").heartbeat).toBe("lost")
	end)

	it(
		"a protected checkout reads no remote: the board carries no verdicts, status refuses before any fetch, lost says so",
		function()
			local function calls(): number
				local text = if fs.isFile(`{h.fakes}/lscalls`) then fs.readFile(`{h.fakes}/lscalls`) else ""
				return #string.gsub(text, "[^x]", "")
			end
			local common = string.gsub(
				fixture.git(h.f.main, { "rev-parse", "--path-format=absolute", "--git-common-dir" }),
				"%s+$",
				""
			)
			local inherited = process.env.PICKMAN_FENCE_REAL_GIT or ""
			local listed = if inherited ~= "" then `{inherited}:{common}` else common
			local function fetches(): number
				local text = if fs.isFile(`{h.fakes}/fetchcalls`)
					then fs.readFile(`{h.fakes}/fetchcalls`)
					else ""
				return #string.gsub(text, "[^f]", "")
			end
			local before, fetchedBefore = calls(), fetches()
			must(
				zn(
					h.f.main,
					{ "board", "--out", ".cache/board-guarded.html", "-O" },
					LATE,
					{ PICKMAN_FENCE_REAL_GIT = listed }
				),
				"board"
			)
			local model = boardModel(`{h.f.main}/.cache/board-guarded.html`)
			for _, list in { model.issues, model.rafts } do
				for _, item in list do
					t.expect(item.heartbeat).toBe(nil)
				end
			end
			local listing = zn(h.f.main, { "status" }, LATE, { PICKMAN_FENCE_REAL_GIT = listed })
			-- status refuses in a protected checkout as it does today (publishing() is false there), before any fetch
			t.expect(listing.ok).toBe(false)
			t.expect(has(listing.stderr, "protected")).toBe(true)
			t.expect(has(listing.stdout, "[lost")).toBe(false)
			local lostHere = zn(h.f.main, { "lost" }, LATE, { PICKMAN_FENCE_REAL_GIT = listed })
			t.expect(lostHere.ok).toBe(true)
			t.expect(lostHere.stdout).toBe("")
			t.expect(has(lostHere.stderr, "protected checkout")).toBe(true)
			t.expect(calls()).toBe(before) -- no ls-remote: nothing was read from the remote
			t.expect(fetches()).toBe(fetchedBefore) -- and no fetch either
		end
	)
