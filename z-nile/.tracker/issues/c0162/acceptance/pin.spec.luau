--!strict
-- c0162 AC1: the pure reader of the Lune the runner must run on (z-nile/tests/lib/lunepin.luau). It reads rokit.toml's
-- [tools] lune pin and refuses an ambiguous file (a second pin, a pin outside [tools], a value that is not
-- "lune-org/lune@x.y.z", no pin); it reads the running version from _VERSION and a `lune --version` line; it lists
-- where rokit.toml is looked for (the runner's repository root, then each folder above it); and its check passes only
-- the pinned version, refusing anything else (an unknown version, an unreadable pin) with both versions and the fix.
local lunepin = require("@tests/lib/lunepin")
local t = require("@tests/lib/t")

local function has(text: string?, needle: string): boolean
	return text ~= nil and string.find(text, needle, 1, true) ~= nil
end

local REAL = table.concat({
	"# This file lists tools managed by Rokit",
	"",
	"[tools]",
	'rojo = "rojo-rbx/rojo@7.7.0"',
	'lune = "lune-org/lune@0.10.5"  # pinned',
	"",
}, "\n")

return t.spec("c0162 lunepin", function(it)
	it("reads the [tools] lune pin, comments and spacing aside, other tools ignored", function()
		t.expect((lunepin.pinned(REAL))).toBe("0.10.5")
		t.expect((lunepin.pinned('[tools]\n  lune="lune-org/lune@1.2.3"\n'))).toBe("1.2.3")
		t.expect((lunepin.pinned('[tools]\nlune = "lune-org/lune@0.10.5"'))).toBe("0.10.5") -- no final newline
	end)

	it("refuses an ambiguous or missing pin, naming the line or the rule", function()
		local cases: { { string } } = {
			{ REAL .. 'lune = "lune-org/lune@0.11.1"\n', "twice" },
			{ '[other]\nlune = "lune-org/lune@0.10.5"\n', "outside [tools]" },
			{ 'lune = "lune-org/lune@0.10.5"\n[tools]\n', "outside [tools]" },
			{ '[tools]\nlune = "lune-org/lune@latest"\n', 'not "lune-org/lune@<x.y.z>"' },
			{ '[tools]\nlune = "someone/lune@0.10.5"\n', 'not "lune-org/lune@<x.y.z>"' },
			{ '[tools]\nlune = "lune-org/lune@0.10"\n', 'not "lune-org/lune@<x.y.z>"' },
			{ '[tools]\nrojo = "rojo-rbx/rojo@7.7.0"\n', "pins no lune" },
			{ "", "pins no lune" },
		}
		for _, c in cases do
			local pin, problem = lunepin.pinned(c[1])
			t.expect(pin).toBe(nil)
			t.expect(has(problem, c[2])).toBe(true)
		end
		local _, twice = lunepin.pinned(REAL .. 'lune = "lune-org/lune@0.11.1"\n')
		t.expect(has(twice, "line 6")).toBe(true)
	end)

	it("reads the running version from _VERSION and a --version line, and nothing else", function()
		t.expect(lunepin.running("Lune 0.10.5+709")).toBe("0.10.5")
		t.expect(lunepin.running("Lune 0.11.1+740")).toBe("0.11.1")
		t.expect(lunepin.running("Lune 0.10.5")).toBe("0.10.5")
		t.expect(lunepin.running("Luau 0.10.5")).toBe(nil)
		t.expect(lunepin.running("Lune 0.10")).toBe(nil)
		t.expect(lunepin.running(nil)).toBe(nil)
		t.expect(lunepin.reported("lune 0.10.5")).toBe("0.10.5")
		t.expect(lunepin.reported("lune 0.10.5\n")).toBe("0.10.5")
		t.expect(lunepin.reported("error: no lune")).toBe(nil)
		t.expect(lunepin.reported(nil)).toBe(nil)
	end)

	it("looks for rokit.toml at the root, then in each folder above it, nearest first", function()
		t.expect(lunepin.places("/a/b/c"))
			.toEqual({ "/a/b/c/rokit.toml", "/a/b/rokit.toml", "/a/rokit.toml", "/rokit.toml" })
		t.expect(lunepin.places("/a/")).toEqual({ "/a/rokit.toml", "/rokit.toml" })
	end)

	it("passes only the pinned version; refuses another, an unknown one or no pin, with the fix", function()
		t.expect(lunepin.check("0.10.5", nil, "0.10.5", "/r/rokit.toml")).toBe(nil)
		local other = lunepin.check("0.10.5", nil, "0.11.1", "/r/rokit.toml")
		t.expect(has(other, "0.11.1")).toBe(true)
		t.expect(has(other, "0.10.5")).toBe(true)
		t.expect(has(other, "/r/rokit.toml")).toBe(true)
		t.expect(has(other, 'PATH="$HOME/.rokit/bin:$PATH"')).toBe(true)
		t.expect(has(other, "./zn")).toBe(true)
		local unknown = lunepin.check("0.10.5", nil, nil, "/r/rokit.toml")
		t.expect(unknown ~= nil).toBe(true)
		t.expect(has(unknown, "0.10.5")).toBe(true)
		local none = lunepin.check(nil, "rokit.toml pins no lune in [tools]", "0.10.5", "/r/rokit.toml")
		t.expect(has(none, "pins no lune")).toBe(true)
		t.expect(has(none, "refusing")).toBe(true)
	end)
end)
