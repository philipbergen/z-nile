--!strict
-- c0285 AC3: zz-rules keeps a capture's commit when a pull request carries one: Merging's paragraph (after the squash
-- command it qualifies) and Landing a change step 3's pointer to it. Each phrase appears verbatim inside its section.
-- Read from the checkout's top. The lessons' own words are checked by check.sh, not here: c0181 may cut or merge a
-- lesson, and a promoted spec must not pin its text.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local root = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local RULES = "z-nile/skills/zz-rules/SKILL.md"

-- a level-2 section: from its heading to the next level-2 heading
local function section(heading: string): string
	local text = fs.readFile(`{root}/{RULES}`)
	local from = string.find(text, `\n## {heading}\n`, 1, true)
	if from == nil then
		error(`{RULES} has no {heading} section`)
	end
	local to = string.find(text, "\n## ", from + 1, true)
	return string.sub(text, from, if to then to - 1 else #text)
end

local function at(s: string, where: string, phrase: string): number
	local i = string.find(s, phrase, 1, true)
	if i == nil then
		error(`{RULES} {where} does not say: {phrase}`)
	end
	return i
end

local function unsays(s: string, where: string, phrase: string)
	if string.find(s, phrase, 1, true) ~= nil then
		error(`{RULES} {where} still says: {phrase}`)
	end
end

return t.spec("c0285 the merge keeps a capture", function(it)
	it(
		"AC3: Merging keeps a capture's subject with every id, and lands a PR that edits it later by a merge commit",
		function()
			local m, w = section("Merging"), "Merging"
			local squash = at(m, w, "Then `gh pr merge <pr> --squash --subject")
			local rule = at(m, w, "The squash subject keeps a capture.")
			t.expect(rule > squash).toBe(true)
			at(
				m,
				w,
				"`./zn capture` finds a capture by its subject, `tracker: new <ids> <title>`, and prints the item document at that commit"
			)
			at(m, w, [[`gh pr view <pr> --json commits --jq '.commits[] | "\(.oid) \(.messageHeadline)"'`]])
			at(m, w, "`git fetch origin pull/<pr>/head`")
			at(
				m,
				w,
				"Their documents are the item documents each capture commit changed (`git show --name-only --format= <capture sha>`, without `spend.md`, reviews or other files)"
			)
			at(m, w, "`git log <capture sha>..<head> -- <their documents>` prints nothing")
			at(m, w, "the squash subject is `tracker: new <every id they list> <title> (#<pr>)`")
			at(m, w, "which for one capture commit is its headline and ` (#<pr>)`")
			at(
				m,
				w,
				'land the pull request with a merge commit instead: `gh pr merge <pr> --merge --subject "<title> (#<pr>)"`, which brings every capture commit to `main` whole'
			)
			at(
				m,
				w,
				"Afterwards `./zn capture <id>` names the capture commit for each id, with no `(no capture commit: …)` marker."
			)
			unsays(m, w, "into the first pull request")
			unsays(m, w, "cherry-pick the capture commits")
		end
	)

	it(
		"AC3: Merging says a step the dispatcher merges must carry no capture commit, and names the lesson",
		function()
			local m, w = section("Merging"), "Merging"
			at(
				m,
				w,
				"The dispatcher's squash takes GitHub's default subject, so a step it merges (a prep, a rafting) must carry no capture commit: its captures land on `main` first (by `./zn land`, or a challenged idea's pull request)"
			)
			at(m, w, "(lesson zz-rules/squash-keeps-the-capture-commit)")
		end
	)

	it("AC3: Landing a change step 3 points a PR that carries a capture commit at Merging", function()
		local l, w = section("Landing a change"), "Landing a change"
		local step3 = string.match(l, "\n3%. %*%*Merge%*%*[^\n]*") or ""
		at(
			step3,
			`{w} step 3`,
			"Any other PR is merged with `gh pr merge --squash`. A pull request that carries a capture commit keeps it, by its squash subject or a merge commit (Merging)."
		)
	end)
end)
