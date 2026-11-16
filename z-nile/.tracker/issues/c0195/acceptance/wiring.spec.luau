--!strict
-- c0195 AC6: where the fence sets the ref guard's hooks, it puts their folder (with the fence's git, git-hooks/git)
-- first on the PATH, once, even when a nested fence runs or the folder is already there under another spelling, and
-- the real git it found first on the PATH stands behind it. Under the jail (where no hooks are set) the fence's git is
-- not on the PATH, not even one an outer fence put there.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local h = require("./harness")
local t = require("@tests/lib/t")

local base = h.fresh("wiring")

return t.spec("c0195 the fence puts its git first on the PATH where it sets the hooks", function(it)
	it("AC6: the fence's git is first on the PATH once, with the real git behind it", function()
		local g = h.GITS[1]
		h.makeRepo(`{base}/a`, g)
		h.makeRepo(`{base}/b`, g)
		-- a nested fence, with the hooks' folder put first on the PATH again under another spelling in between: its git
		-- is not taken for the real one, and it does not stay on the PATH beside the fence's entry
		local script = table.concat({
			'. "$1" || exit 90',
			'PATH="$2:$PATH"',
			'pickman_fence "$3/a" >/dev/null || exit 91',
			'PATH="$5:$PATH"',
			'pickman_fence "$3/b" >/dev/null || exit 92',
			'echo "first=$(type -P git)"',
			'n=0; old=$IFS; IFS=:; for e in $PATH; do [ "$e" -ef "$4" ] && n=$((n + 1)); done; IFS=$old',
			'echo "times=$n"',
			'echo "version=$(git --version)"',
		}, "\n")
		local respelled = string.gsub(h.HOOKS, "/git%-hooks$", "/./git-hooks")
		local r =
			fixture.exec(`{base}/a`, "bash", { "-c", script, "_", h.FENCE, g.dir, base, h.HOOKS, respelled })
		if not r.ok then
			error(r.stderr .. r.stdout)
		end
		t.expect(h.has(r.stdout, `first={h.HOOKS}/git\n`)).toBe(true)
		t.expect(h.has(r.stdout, "times=1\n")).toBe(true)
		t.expect(h.has(r.stdout, `version={g.version}\n`)).toBe(true)
	end)

	it(
		"AC6: under the jail the fence's git is not on the PATH, even when an outer fence put it there",
		function()
			local g = h.GITS[1]
			h.makeRepo(`{base}/c`, g)
			h.makeRepo(`{base}/d`, g)
			local script = table.concat({
				'. "$1" || exit 90',
				'PATH="$2:$PATH"',
				'pickman_fence "$3/c" >/dev/null || exit 91',
				'echo "outer=$(type -P git)"',
				-- a spec run's own fence under the jail (what tests/lib/fence.luau starts on macOS)
				'pickman_fence "$3/d" specs sandbox-exec >/dev/null || exit 92',
				'echo "inner=$(type -P git)"',
			}, "\n")
			local r = fixture.exec(`{base}/c`, "bash", { "-c", script, "_", h.FENCE, g.dir, base })
			if not r.ok then
				error(r.stderr .. r.stdout)
			end
			-- the outer fence did put it there, so the jail's fence is what took it away
			t.expect(h.has(r.stdout, `outer={h.HOOKS}/git\n`)).toBe(true)
			t.expect(h.has(r.stdout, "inner=/")).toBe(true)
			t.expect(h.has(r.stdout, "/git-hooks/git\n")).toBe(true) -- the outer line only
			t.expect(h.has(r.stdout, `inner={h.HOOKS}/git`)).toBe(false)
		end
	)

	it("cleans up", function()
		h.remove(base)
		t.expect(fs.isDir(base)).toBe(false)
	end)
end)
