--!strict
-- c0369 AC7: every text that restates where and how a design is approved says the one command from anywhere, and
-- none still sends the person to a worktree or to a second command.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

local function read(rel: string): string
	return fs.readFile(`{TOP}/{rel}`)
end
-- the phrases of `wanted` that `rel` lacks
local function lacks(rel: string, wanted: { string }): { string }
	local text = read(rel)
	local out: { string } = {}
	for _, phrase in wanted do
		if not string.find(text, phrase, 1, true) then
			table.insert(out, phrase)
		end
	end
	return out
end
-- the phrases of `gone` that `rel` still holds
local function holds(rel: string, gone: { string }): { string }
	local text = read(rel)
	local out: { string } = {}
	for _, phrase in gone do
		if string.find(text, phrase, 1, true) then
			table.insert(out, phrase)
		end
	end
	return out
end

return t.spec("c0369 the texts", function(it)
	it("zz-rules' approve row states the placement, the publish and the retry", function()
		t.expect(lacks("z-nile/skills/zz-rules/SKILL.md", {
			"| approve | `./zn approve <issue-id> [--check\\|--publish]` | one command, with a terminal on stdin,",
			"**It finds the design itself**, from the main checkout or any worktree",
			"the worktree of the issue's prep branch (`prep-<slug>`), or the worktree the command is run in",
			"with a contract of its own (not `origin/main`'s, not the one it branched from, not one `origin/main` held since) and no matching approval",
			"else `origin/main`, when the design is merged there with no matching approval",
			"No other worktree is read, so a prototype or a copy is approved only by running the command inside it",
			"It says where it acts, records there and makes the approval count in the same command",
			"is published (`approval.md` and the approved row, one commit), any other is pushed on its branch and counts when its pull request merges",
			"a detached worktree the command makes at `.worktree/.approve-<id>` and removes once published",
			"the main checkout is never written",
			"is published as it is, never recorded twice",
			"When the publish or push fails, or publishing is off, the record stays, the command fails saying it does not count yet",
			"`./zn approve <id> --publish` retries it from anywhere",
			"`--check` reads the checkout it runs in",
		})).toEqual({})
		t.expect(holds("z-nile/skills/zz-rules/SKILL.md", { "in the worktree where the design is" }))
			.toEqual({})
	end)

	it("z-design, z-ready and AGENTS.md send the person to one command, from anywhere", function()
		t.expect(lacks("z-nile/skills/z-design/SKILL.md", {
			"in a terminal of their own, from anywhere in the checkout: it finds this worktree, records the approval and pushes the branch",
		})).toEqual({})
		t.expect(holds("z-nile/skills/z-design/SKILL.md", { "in a terminal of their own in this worktree" }))
			.toEqual({})
		t.expect(lacks("z-nile/skills/z-ready/SKILL.md", {
			"run by the human in a terminal, from anywhere in the checkout",
		})).toEqual({})
		t.expect(lacks("AGENTS.md", {
			"run in their own terminal, from anywhere in the checkout (it finds the design, records the approval and publishes it)",
		})).toEqual({})
		t.expect(holds("AGENTS.md", { "in the prep worktree; it is refused" })).toEqual({})
	end)

	it(
		"no refusal or hint the tooling prints names a worktree to run in or a second command to run",
		function()
			local gone = {
				"from the worktree that holds the design",
				"then ./zn approve {id} --publish",
				"Publish it to origin/main from this worktree",
				"in a terminal, in this worktree",
				"in your own terminal, in this worktree",
				"From this worktree run: git push origin HEAD",
				"inside the one you mean",
				"has no approval in this worktree",
			}
			t.expect(holds("z-nile/engine/approval.luau", gone)).toEqual({})
			t.expect(holds("z-nile/engine/main.luau", gone)).toEqual({})
			t.expect(holds("zn", gone)).toEqual({})
			t.expect(holds("z-nile/engine/approveplace.luau", gone)).toEqual({})
			t.expect(holds("z-nile/tests/lib/seal.luau", { "refuses in the fixture's main checkout" }))
				.toEqual({})
			t.expect(lacks("z-nile/engine/approval.luau", {
				"run ./zn approve {id} in a terminal, from anywhere in the checkout. This is a one-time step for an item prepared before approval.",
			})).toEqual({})
		end
	)
end)
