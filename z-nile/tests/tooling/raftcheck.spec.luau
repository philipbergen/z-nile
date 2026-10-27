--!strict
-- R0052 code review 003 F2: a new raft's check.sh as the rafting gate judges it (engine/raftcheck.luau, pure). The
-- rendered template's RC0 lines byte for byte, then only `check "RCn: …"` lines whose words are inert, and `finish`.
local fs = require("@lune/fs")
local process = require("@lune/process")
local raftcheck = require("@znile/engine/raftcheck")
local t = require("@tests/lib/t")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local rendered = raftcheck.render(
	fs.readFile(`{TOP}/z-nile/templates/raft/check.sh`),
	{ ID = "R0050", PROJECT = "pickman" }
)
local head = raftcheck.head(rendered) :: string

return t.spec("c0117 a new raft's check.sh (R0052 code review 003 F2)", function(it)
	it("renders the template for the raft and keeps its RC0 lines as the head", function()
		t.expect(string.find(rendered, "{{", 1, true)).toBe(nil)
		t.expect(string.find(head, "promote-check R0050", 1, true) ~= nil).toBe(true)
		t.expect(string.find(head, "finish", 1, true)).toBe(nil)
	end)

	it("passes the template, and RCn checks after its RC0 lines", function()
		for name, text in
			{
				template = rendered,
				rc1 = head .. "\ncheck \"RC1: x\" bash -c 'true'\n\nfinish\n",
				multiline = head .. "\ncheck \"RC1: x\" bash -c '\n  exit 0\n'\nfinish\n",
				continued = head .. '\ncheck "RC1: x" "$ZN_ROOT/zn" \\\n  promote-check R0050\nfinish\n',
				comments = head .. '\n# RC1 below\ncheck "RC1: x" true\n\n# done\nfinish\n',
			}
		do
			local why = raftcheck.judge(text, rendered)
			if why then
				error(`{name}: {why}`)
			end
		end
	end)

	it("refuses an RC0 line changed, and anything after them that could change the result", function()
		for name, text in
			{
				exit0 = "exit 0\n",
				tampered = (string.gsub(rendered, "%-%-full", "--quick")),
				semicolon = head .. '\ncheck "RC1: x" true; exit 0\nfinish\n',
				bare = head .. "\nexit 0\nfinish\n",
				reset = head .. "\n_ac_failed=0\nfinish\n",
				substitution = head .. '\ncheck "RC1: x" true $(_ac_failed=0)\nfinish\n',
				brace = head .. '\ncheck "RC1: x" true ${_ac_failed:=0}\nfinish\n',
				backquote = head .. '\ncheck "RC1: x" true `x`\nfinish\n',
				redirect = head .. '\ncheck "RC1: x" true > /dev/null\nfinish\n',
				andand = head .. '\ncheck "RC1: x" true && exit 0\nfinish\n',
				func = head .. '\nf() { true; }\ncheck "RC1: x" f\nfinish\n',
				rc0 = head .. '\ncheck "RC0: again" true\nfinish\n',
				nocommand = head .. '\ncheck "RC1: x"\nfinish\n',
				nofinish = head .. '\ncheck "RC1: x" true\n',
				after = rendered .. "exit 0\n",
			}
		do
			t.expect({ name, raftcheck.judge(text, rendered) ~= nil }).toEqual({ name, true })
		end
	end)
end)
