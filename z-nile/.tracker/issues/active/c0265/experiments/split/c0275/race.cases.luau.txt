-- c0265 split: cases of race.spec (monolithic version) that belong to c0275. Not runnable alone: the file's

-- header, helpers, shim and setup are in ../race.spec.orig. They never ran against an implementation.



	it("a long outer command beats while it runs", function()
		local stamp = stampOf(`{P}/c0090/c0090.md`)
		local r = zn(wt, { "check", "c0090" }, { ZN_BEAT_EVERY = "1", STAMP = stamp })
		t.expect(r.ok).toBe(true)
		t.expect(fs.isFile(`{h.fakes}/check-beat`)).toBe(true)
	end)

	it(
		"a hung remote is bounded: status returns, warns, and a failed beat attempt is not retried inside the interval",
		function()
			fs.writeFile(`{h.fakes}/lshang`, "1")
			local started = os.time()
			local r = zn(
				h.f.main,
				{ "status" },
				{ ZN_NOW = tostring(os.time() + 5 * STALE), ZN_NET_SECONDS = "1" }
			)
			t.expect(r.ok).toBe(true)
			t.expect(os.time() - started < 20).toBe(true)
			t.expect(has(r.stderr, "heartbeats unreadable")).toBe(true)
			-- in a worktree that holds claims, a command that judges nothing makes one failed attempt per claim and no more
			local function calls(): number
				local text = if fs.isFile(`{h.fakes}/lscalls`) then fs.readFile(`{h.fakes}/lscalls`) else ""
				return #string.gsub(text, "[^x]", "")
			end
			local before = calls()
			must(
				zn(
					wt,
					{ "lessons", "--tags" },
					{ ZN_NOW = tostring(os.time() + 6 * STALE), ZN_NET_SECONDS = "1" }
				),
				"lessons in the worktree"
			)
			local first = calls()
			t.expect(first > before).toBe(true)
			must(
				zn(
					wt,
					{ "lessons", "--tags" },
					{ ZN_NOW = tostring(os.time() + 6 * STALE + 10), ZN_NET_SECONDS = "1" }
				),
				"lessons again"
			)
			t.expect(calls()).toBe(first) -- inside the interval: no new attempt
			fs.removeFile(`{h.fakes}/lshang`)
		end
	)
