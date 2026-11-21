--!strict
-- f0421 slice 2, step 7 (C), AC26: the skills and AGENTS.md say that every activity runs on the model `./zn model <activity>
-- --for <id>` prints (a subagent with its subagent word and effort in Claude Code; the session itself, only when it is that
-- model, on a CLI with no subagents), and what to do on exit 1 and exit 2. None of them still names a role of .models.toml
-- as the one that reviews, or pins the subagents to `model: "sonnet"`.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

local function read(rel: string): string
	return fs.readFile(`{TOP}/{rel}`)
end
local function skill(name: string): string
	return read(`z-nile/skills/{name}/SKILL.md`)
end
local function has(text: string, needle: string, where: string)
	if string.find(text, needle, 1, true) == nil then
		error(`{where} lacks: {needle}`, 2)
	end
end
local function absent(text: string, needle: string, where: string)
	if string.find(text, needle, 1, true) ~= nil then
		error(`{where} still contains: {needle}`, 2)
	end
end

return t.spec("f0421 step 7: the model of an activity is the one ./zn model names", function(it)
	it(
		"AGENTS.md: the Subagents paragraph names ./zn model, keeps no fork subagents, and says what each exit means",
		function()
			local text = read("AGENTS.md")
			has(
				text,
				"**Subagents:** don't use `fork` subagents. An activity (a design, a review, a layer) runs on the model `./zn model <activity> --for <id>` prints",
				"AGENTS.md"
			)
			has(
				text,
				"start one plain subagent (general-purpose) for that activity, in Claude Code with its `subagent=` word as `model`",
				"AGENTS.md"
			)
			has(text, "Any other subagent uses `./zn model light`", "AGENTS.md")
			has(text, "On exit 1 don't do the activity", "AGENTS.md")
			has(text, "waiting for a worker with", "AGENTS.md")
			has(text, "on exit 2 stop and show the error", "AGENTS.md")
			has(
				text,
				"a CLI with no subagent mechanism runs it in the session, and only when the line's model is the session's own",
				"AGENTS.md"
			)
			absent(text, 'model: "sonnet"', "AGENTS.md")
			absent(text, "Opus 5.5", "AGENTS.md")
		end
	)

	it("z-work rule 3 points every action that needs a model at ./zn model", function()
		local text = skill("z-work")
		has(text, "Do that one action and nothing past it. An action that needs a model", "z-work")
		has(
			text,
			"runs on the one `./zn model <activity> --for <id>` prints: in Claude Code a subagent with its `subagent=` word and `effort=`",
			"z-work"
		)
		has(
			text,
			"on a CLI with no subagents, this session, and only when that model is this session's own",
			"z-work"
		)
		has(
			text,
			"When it exits 1, or the model is not yours, don't do it: say its line and release it (until f0420 lands, stop)",
			"z-work"
		)
	end)

	it("z-design and z-raft start the writer and the reviewer on the model ./zn model prints", function()
		local design = skill("z-design")
		has(design, "run `./zn model design --for <id>`", "z-design")
		has(design, "on the model `./zn model design-review --for <id>` prints", "z-design")
		has(design, "starts it on that model", "z-design")
		has(design, "with that line, and never on another model", "z-design")
		local raft = skill("z-raft")
		has(raft, "on the model `./zn model raft-review --for <R-id>` prints", "z-raft")
	end)

	it("zz-review and zz-execute say which model the reviewer and the builder run on", function()
		local review = skill("zz-review")
		has(
			review,
			"A review runs on the model `./zn model <activity> --for <id>` prints: design-review for design, raft-review for a raft, code-review for code and stream, final-review for the final review.",
			"zz-review"
		)
		has(
			review,
			"A reviewer never runs on the model that wrote the text: the configuration refuses a pair on one model, and the reviewer is refused on the writer's recorded model.",
			"zz-review"
		)
		has(review, "on the model `./zn model final-review --for <R-id>` prints", "zz-review")
		local execute = skill("zz-execute")
		has(execute, "run `./zn model code --for <R-id>`", "zz-execute")
		has(execute, "on the model `./zn model code-review --for <R-id>` prints", "zz-execute")
		has(execute, "starts it on that model", "zz-execute")
		has(execute, "start the reviewer subagent with that line", "zz-execute")
		has(
			execute,
			"or a fresh subagent on the model `./zn model final-review --for <R-id>` prints, in final mode",
			"zz-execute"
		)
	end)

	it(
		"no skill and no AGENTS.md still names a role as the reviewer or pins the subagents to Sonnet",
		function()
			local files = { "AGENTS.md" }
			for _, name in fs.readDir(`{TOP}/z-nile/skills`) do
				if fs.isFile(`{TOP}/z-nile/skills/{name}/SKILL.md`) then
					table.insert(files, `z-nile/skills/{name}/SKILL.md`)
				end
			end
			for _, rel in files do
				local text = read(rel)
				for _, gone in
					{
						'model: "sonnet"',
						"design-challenge role",
						"code-review role",
						"raft role",
						"the review model of the CLI",
					}
				do
					absent(text, gone, rel)
				end
			end
		end
	)
end)
