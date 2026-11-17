--!strict
-- c0369 AC6: every text that restates where and how a design is approved says the one command from anywhere, and
-- none still sends the person to a worktree or to a second command. AC7's text half: the approve tooling specs walk
-- the one command and answer the explainer page (c0368's outcome, carried by c0369).
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
			"| approve | `./zn approve <issue-id> [--check\\|--publish]` | one command, with a terminal on stdin, and not while `ZN_DISPATCH` is set.",
			"**It finds the design itself**, from the main checkout or any worktree",
			"the worktree of the issue's prep branch (`prep-<slug>`), or the worktree the command is run in",
			"with a contract of its own (not `origin/main`'s, not the one it branched from, not one `origin/main` held since) and no matching approval",
			"else `origin/main`, when the design is merged there with no matching approval",
			"For an issue in `active/` on `origin/main` it also reads its raft's worktree (`.worktree/<R-id>`), where a contract changed on the raft's branch is approved.",
			"No other worktree is read, so a prototype or a copy is approved only by running the command inside it",
			"It says where it acts, records there and makes the approval count in the same command",
			"is published (this row appended to `origin/main`'s `approval.md`, one commit), any other is pushed on its branch and counts when its pull request merges",
			"a detached worktree the command makes at `.worktree/.approve-<id>` and removes once published",
			"the main checkout is never written",
			"is published as it is, never recorded twice",
			"When the publish or push fails, or publishing is off, the record stays, the command fails saying it does not count yet",
			"`./zn approve <id> --publish` retries it from anywhere",
			"`--check` reads the checkout it runs in",
			"Only the prep branch, or a branch already on origin, is pushed, and never forced",
			"on a raft's layer branch nothing is pushed: the record counts for `./zn finish` in that worktree, and for `./zn done` once the layer is finished and pushed again",
			"An `approval.md` on `origin/main` that does not parse is replaced by the approval (its rows cannot be read); a worktree on no branch is refused before anything is recorded.",
			"While a worktree it reads holds a design of its own, `origin/main`'s older design is not approved behind it.",
		})).toEqual({})
		t.expect(holds("z-nile/skills/zz-rules/SKILL.md", { "in the worktree where the design is" }))
			.toEqual({})
	end)

	it("z-design and z-ready send the person to one command, from anywhere", function()
		t.expect(lacks("z-nile/skills/z-design/SKILL.md", {
			"in a terminal of their own, from anywhere in the checkout: it finds this worktree, records the approval and pushes the branch",
		})).toEqual({})
		t.expect(holds("z-nile/skills/z-design/SKILL.md", { "in a terminal in this worktree" })).toEqual({})
		t.expect(lacks("z-nile/skills/z-ready/SKILL.md", {
			"run by the human in a terminal, from anywhere in the checkout",
		})).toEqual({})
		t.expect(holds("z-nile/skills/z-ready/SKILL.md", { "run by the human in the prep worktree" }))
			.toEqual({})
	end)

	it(
		"no refusal or hint the tooling prints names a worktree to run in or a second command to run",
		function()
			local gone = {
				"from the worktree that holds the design",
				"then ./zn approve {id} --publish",
				"Publish it to origin/main from this worktree",
				"in a terminal, in this worktree",
				"in your own terminal, in this worktree", -- c0283's refusal as it is designed today: its re-prep says it without a worktree
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
				"run ./zn approve {id} in a terminal, from anywhere in the checkout.",
				"Run ./zn approve {id} again.`",
			})).toEqual({})
		end
	)

	it("the approve tooling specs approve with one command and answer the explainer page", function()
		for _, rel in
			{ "z-nile/tests/tooling/approve.spec.luau", "z-nile/tests/tooling/approve-publish.spec.luau" }
		do
			t.expect(lacks(rel, {
				"explainer.html",
				'<meta name="zn-contract" content="',
				"contract.hash(",
				'{ "open", "xdg-open" }',
				"yes y | script -q /dev/null sh -c './zn approve ",
				"published {ID} to origin/main: it counts now",
			})).toEqual({})
			-- no approve that records runs without the answering terminal: neither the old `script ... ./zn approve`
			-- form nor a second command
			t.expect(holds(rel, {
				'"approve", ID, "--publish"',
				"has(recorded.stdout, `./zn approve {ID} --publish`)",
				'"/dev/null", "./zn", "approve"',
				"'./zn approve {ID} --publish",
			})).toEqual({})
			-- one helper runs every approve that records: the answering line appears once
			local _, helpers = string.gsub(read(rel), "yes y | script %-q /dev/null sh %-c", "")
			t.expect(helpers).toBe(1)
		end
	end)
end)
