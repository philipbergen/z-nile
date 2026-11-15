--!strict
-- c0325 E1a (experiment, not promoted): where does `./zn spend <R-id> --phase prep --model X` write its row?
-- A raft in rafting (claimed, preparing) of two prepared members, in a github-shaped fixture, from a prep worktree.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local ROOT = "pickman/.tracker"
local CHECK = 'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"\n'
	.. 'check "AC1: ok" true\nfinish\n'

local function issue(id: string, raft: string): string
	return `---\nid: {id}\ntype: chore\ntitle: title {id}\nslug: {id}\nraft: {raft}\ndepends_on: []\nemergent: false\ndesign: ready\nreviews: judged\nrank: 7\ncreated: 2026-11-10\nstatus: prepared-quiet-copper-falcon\n---\n\n# {id}\n\n## Problem\nP.\n\n## Solution\nS.\n\n## Acceptance criteria\n- AC1: x\n`
end

return t.spec("c0325 E1a: where a raft's prep spend writes", function(it)
	it("spend <R-id> --phase prep --model X", function()
		local seed: { [string]: string } = {
			[`{ROOT}/architecture.md`] = "x\n",
			["z-nile/next"] = "issue 400 quiet-copper-falcon\nraft 70 quiet-copper-falcon\n",
			[`{ROOT}/rafts/R0200/R0200.md`] = `---\nid: R0200\ntype: chore\ntitle: R0200\nslug: r0200\nsingle: false\nissues: [c0290, c0291]\ndesign: ready\nreviews: judged\nrank: 3\ncreated: 2026-11-10\nstatus: preparing-quiet-copper-falcon\n---\n\n# R0200\n\n## Theme\nT.\n\n## Order & dependencies\nc0290\nc0291\n`,
			[`{ROOT}/rafts/R0200/check.sh`] = CHECK,
		}
		for _, id in { "c0290", "c0291" } do
			seed[`{ROOT}/issues/{id}/{id}.md`] = issue(id, "R0200")
			seed[`{ROOT}/issues/{id}/check.sh`] = CHECK
		end
		local f = trackerfix.new("c0325-E1a-github.com", seed)
		local bin = `{f.base}/bin`
		fs.writeDir(bin)
		fs.writeFile(`{bin}/gh`, "#!/bin/sh\nexit 0\n")
		process.exec("chmod", { "+x", `{bin}/gh` })
		local prep = `{f.base}/wt-prep`
		fixture.git(f.main, { "worktree", "add", "-q", "-b", "prep-e1a", prep, "origin/main" })
		local r = fixture.exec(
			prep,
			"./zn",
			{ "spend", "R0200", "--phase", "prep", "--model", "model-raft-prep" },
			{
				env = { PATH = `{bin}:{process.env.PATH or ""}`, CLAUDECODE = "", ZN_MODEL = "" },
			}
		)
		print(`spend exit {r.code}: {r.stdout}{r.stderr}`)
		for _, dir in { "rafts/R0200", "issues/c0290", "issues/c0291" } do
			local folder = `{prep}/{ROOT}/{dir}/spend.d`
			local seen = false
			if fs.isDir(folder) then
				for _, name in fs.readDir(folder) do
					for line in string.gmatch(fs.readFile(`{folder}/{name}`), "[^\n]+") do
						local c = string.split(line, "\t")
						if c[5] ~= "phase" then
							seen = true
							print(`  {dir}: phase={c[5]} model={c[7] or ""}`)
						end
					end
				end
			end
			if not seen then
				print(`  {dir}: no row`)
			end
		end
		t.expect(r.ok).toBe(true)
	end)
end)
