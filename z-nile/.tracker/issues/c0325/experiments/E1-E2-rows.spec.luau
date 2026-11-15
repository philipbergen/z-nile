--!strict
-- c0325 E1 and E2 (experiment, not promoted): where do the rows of an authored step land?
--   E1a  ./zn spend <R-id> --phase prep --model X     (a raft in rafting, two members)
--   E1b  ./zn commit -m ... --model Y                 (a started raft of two members, no --issue)
--   E2   ./zn commit -m ... --issue <member> --model Z (a stream/layer commit with --issue)
-- Prints, per item folder, the phase and model cell of every spend.d row.
local engine = require("@tests/lib/engine")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local seal = require("@tests/lib/seal")
local t = require("@tests/lib/t")

local function trim(s: string): string
	return (string.gsub(string.gsub(s, "^%s+", ""), "%s+$", ""))
end
local TOP = trim(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout)
local TR = "pickman/.tracker"
local TERMINAL: { [string]: string } = {
	CLAUDECODE = "",
	AI_AGENT = "",
	CLAUDE_EFFORT = "",
	ZN_DISPATCH = "",
	ZN_HEADLESS = "",
	ZN_MODEL = "",
	GIT_AUTHOR_NAME = "x",
	GIT_AUTHOR_EMAIL = "x@example.invalid",
	GIT_COMMITTER_NAME = "x",
	GIT_COMMITTER_EMAIL = "x@example.invalid",
}
local dir = ""
local function run(cmd: string, args: { string }, extra: { [string]: string }?): fixture.Result
	local e = table.clone(TERMINAL)
	for k, v in extra or {} do
		e[k] = v
	end
	return fixture.exec(dir, cmd, args, { env = e })
end
local function must(r: fixture.Result, what: string): string
	if not r.ok then
		error(`{what} failed ({r.code}): {r.stderr}{r.stdout}`, 2)
	end
	return trim(r.stdout)
end
local function write(path: string, text: string)
	local full = `{dir}/{path}`
	fs.writeDir(string.match(full, "^(.*)/[^/]+$") :: string)
	fs.writeFile(full, text)
end
local function rowsOf(root: string): string
	local out = ""
	local function walk(d: string)
		for _, name in fs.readDir(d) do
			local p = `{d}/{name}`
			if fs.isDir(p) then
				if name == "spend.d" then
					for _, f in fs.readDir(p) do
						for line in string.gmatch(fs.readFile(`{p}/{f}`), "[^\n]+") do
							local c = string.split(line, "\t")
							if c[5] ~= "phase" then
								out ..= `    {string.sub(p, #root + 2)}: phase={c[5]} model={c[7] or ""}\n`
							end
						end
					end
				else
					walk(p)
				end
			end
		end
	end
	walk(root)
	return out
end

return t.spec("c0325 E1 E2: where the rows of an authored step land", function(it)
	it("E1b and E2: commits in a started raft of two members", function()
		local base = `{trim(process.exec("pwd", { "-P" }).stdout)}/.cache`
		dir = `{base}/c0325-E1b`
		if fs.isDir(dir) then
			fs.removeDir(dir)
		end
		fs.writeDir(dir)
		process.exec("git", { "init", "-q", "-b", "main", dir })
		for _, p in { ".claude", ".luaurc", ".gitignore", "rokit.toml" } do
			process.exec("cp", { "-R", `{TOP}/{p}`, `{dir}/{p}` })
		end
		fs.writeDir(`{dir}/pickman/.tracker`)
		engine.copy(TOP, dir)
		for _, d in { "issues/active", "issues/done", "rafts/active", "rafts/done" } do
			write(`{TR}/{d}/.gitkeep`, "")
		end
		must(run("git", { "add", "-A" }), "add")
		must(run("git", { "commit", "-q", "-m", "seed" }), "seed")
		local ids = {}
		for _, slug in { "alpha", "beta" } do
			table.insert(
				ids,
				string.match(
					must(run("./zn", { "new", "issue", "f", slug, "--project", "pickman" }), "new"),
					"(f%d%d%d%d)"
				) :: string
			)
		end
		local raft = string.match(
			must(
				run("./zn", { "new", "raft", "feature", "demo", ids[1], ids[2], "--project", "pickman" }),
				"new raft"
			),
			"(R%d%d%d%d)"
		) :: string
		for _, id in ids do
			local doc = `{TR}/issues/{id}/{id}.md`
			local text = fs.readFile(`{dir}/{doc}`)
			text = string.gsub(text, "design: draft", "design: ready", 1)
			text = string.gsub(text, "### Touched modules\n", `### Touched modules\n- \`notes/{id}\`\n`, 1)
			write(doc, text)
			write(
				`{TR}/issues/{id}/check.sh`,
				'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"\ncheck "RC1: fixture" true\nfinish\n'
			)
		end
		local rdoc = `{TR}/rafts/{raft}/{raft}.md`
		write(rdoc, (string.gsub(fs.readFile(`{dir}/{rdoc}`), "design: draft", "design: ready", 1)))
		write(
			`{TR}/rafts/{raft}/check.sh`,
			'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"\ncheck "RC1: fixture" true\nfinish\n'
		)
		seal.prep(dir)
		must(run("git", { "add", "-A" }), "add")
		must(run("git", { "commit", "-q", "-m", "prep ready" }), "prep")
		must(run("./zn", { "start", raft }), "start")
		write(`notes/{ids[1]}/a.txt`, "1\n2\n3\n")
		write(`notes/{ids[2]}/b.txt`, "1\n2\n")
		must(
			run("./zn", { "commit", "-m", "raft-level commit, no --issue", "--model", "model-raft-level" }),
			"commit"
		)
		print("E1b raft-level build commit (--model model-raft-level), two members:")
		print(rowsOf(`{dir}/{TR}`))
		write(`notes/{ids[1]}/a.txt`, "1\n2\n3\n4\n5\n")
		must(
			run("./zn", { "commit", "-m", "layer commit", "--issue", ids[1], "--model", "model-issue-one" }),
			"commit"
		)
		print(`E2 commit --issue {ids[1]} (--model model-issue-one):`)
		print(rowsOf(`{dir}/{TR}`))
		-- a dispatched layer: ZN_MODEL, no --issue, no focus
		write(`notes/{ids[2]}/b.txt`, "1\n2\n3\n4\n")
		must(run("./zn", { "commit", "-m", "env commit" }, { ZN_MODEL = "model-from-env" }), "commit")
		print("E1b again with ZN_MODEL=model-from-env:")
		print(rowsOf(`{dir}/{TR}`))
		t.expect(true).toBe(true)
	end)
end)
