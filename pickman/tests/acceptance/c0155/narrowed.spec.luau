--!strict
-- Narrowed by c0182: dropped the f0110/buttons.spec Touch.buttons cases (d0149 replaces snap and hop with circles;
-- d0149/acceptance/fold.spec owns Touch.buttons). Keeps all f0146/pad.spec and Pad.BUTTONS own-action pins.
-- c0155 AC1: the two button-table cases that f0126 (and d0149, f0143 after it) extend pin each of today's entries
-- one by one, so an added button leaves them green and a moved or missing entry still turns them red. f0110's and
-- f0146's own preps already narrowed them (the user chose "verify only" for this chore on 2026-10-31), so this spec
-- checks the narrowing by behaviour: it runs each promoted case as it is, then against Touch and Pad with one more
-- button (must pass), then with each pinned entry moved or removed (must fail on an assertion). It does not pin
-- the two files' text (no whole-file digest, by the same decision), so d0149's chore may still narrow f0110's
-- other cases. It reaches the cases through the tables they read today (Touch.buttons, Pad.BUTTONS): a rewrite of
-- f0146's case to the same pins through Pad.action would turn this spec red with no defect, and needs a chore
-- (design review 003 F3). A button added to Pad.BUTTONS must have an action of its own (decided with the user,
-- 2026-10-31, as c0150 rules for the keys), which this spec checks on the real map. The two promoted files it runs:
--   tests/acceptance/f0110/buttons.spec.luau :: "Touch.buttons holds the snap, fire and hop rectangles (a later control may add a field)"
--   tests/acceptance/f0146/pad.spec.luau :: "the constants and the button map"
local Pad = require("@logic/Pad")
local fs = require("@lune/fs")
local padSpec = require("@tests/acceptance/f0146/pad.spec")
local t = require("@tests/lib/t")

local MAP_CASE = "the constants and the button map"

-- every entry f0146 pins today, with an action that is not its own (each a real View action, so a case that
-- checked only "some action" would still pass a swap)
local MAP: { [string]: string } = {
	ButtonA = "Jump",
	ButtonR2 = "Fire",
	ButtonR3 = "Snap",
	DPadUp = "Forward",
	DPadDown = "Back",
	DPadLeft = "Left",
	DPadRight = "Right",
}
local SWAP: { [string]: string } = {
	Jump = "Fire",
	Fire = "Snap",
	Snap = "Jump",
	Forward = "Back",
	Back = "Forward",
	Left = "Right",
	Right = "Left",
}

type Case = { name: string, fn: () -> () }

local function caseOf(spec: any, name: string): Case
	local found: Case? = nil
	local count = 0
	for _, c in spec.cases do
		if c.name == name then
			found = c
			count += 1
		end
	end
	t.expect(count).toBe(1)
	assert(found, "no case named " .. name)
	return found
end

-- runs fn and reports whether it passed; a failure that is not one of t's assertions is an error here. t raises
-- at its caller's line ("<file>:<line>: expected …"), which Luau's own errors ("table expected, got nil") never
-- start with (design review 001 F2).
local function passes(fn: () -> ()): boolean
	local ok, err = pcall(fn :: () -> any) -- a failing case raises; the cast gives the error a name
	if not ok then
		local text = tostring(err)
		if not string.find(text, "^[^\n]-:%d+: expected ") then
			error("not an assertion failure: " .. text, 2)
		end
	end
	return ok
end

local P = Pad :: any

-- runs the f0146 case with Pad.BUTTONS replaced by map, and puts the real one back
local function withMap(map: { [string]: string }): boolean
	local real = P.BUTTONS
	P.BUTTONS = table.freeze(map)
	local ok, result = pcall(passes, caseOf(padSpec, MAP_CASE).fn)
	P.BUTTONS = real
	if not ok then
		error(result, 0)
	end
	return result
end

local function copy(map: { [string]: any }): { [string]: any }
	return table.clone(map) -- not frozen, even when map is
end

-- Today's ids, as full tests/acceptance/<id> paths, which a compaction rewrites with the folders (here and in the
-- requires above); each item folder's id is taken from them. Not renamed.id, which is for ids written before a
-- compaction: z-nile/compaction.txt already maps an older f0110 (now f0012), so it would name the wrong item.
local PAD_DIR = "tests/acceptance/f0146"

-- whether the item's check.sh has a check line (one starting `check "`, not a comment) that runs the spec file
local function checkRuns(dir: string, file: string): boolean
	local id = string.match(dir, "[^/]+$")
	assert(id, "no id in " .. dir)
	local text = fs.readFile(".tracker/issues/done/" .. id .. "/check.sh")
	for line in string.gmatch(text, "[^\n]+") do
		if string.sub(line, 1, 7) == 'check "' and string.find(line, `"$A/{file}"`, 1, true) then
			return true
		end
	end
	return false
end

return t.spec("c0155 the button-table pins, narrowed", function(it)
	it("f0146's spec is still there, and f0146's check.sh still runs it", function()
		t.expect(fs.isFile(PAD_DIR .. "/pad.spec.luau")).toBe(true)
		t.expect(checkRuns(PAD_DIR, "pad.spec.luau")).toBe(true)
		caseOf(padSpec, MAP_CASE)
	end)

	it(
		"f0146's case passes on Pad as it is, and with more buttons (f0126's ButtonY, f0143's ButtonL3)",
		function()
			t.expect(withMap(copy(Pad.BUTTONS))).toBe(true)
			local more = copy(Pad.BUTTONS)
			more.ButtonY = "Pick"
			more.ButtonL3 = "Boost"
			t.expect(withMap(more)).toBe(true)
		end
	)

	it(
		"every pad button beyond today's seven has an action of its own: none of the seven's, and no other added button's",
		function()
			-- decided with the user, 2026-10-31 ("Own action, like keys"), as c0150 rules for the keys; f0146's case
			-- reads only the seven, so this spec holds the rule (design review 003 F2)
			local function ownActions(map: { [string]: string }): boolean
				local taken: { [string]: boolean } = {}
				for _, action in MAP do
					taken[action] = true
				end
				for key, action in map do
					if MAP[key] == nil then
						if taken[action] then
							return false
						end
						taken[action] = true
					end
				end
				return true
			end
			t.expect(ownActions(Pad.BUTTONS :: any)).toBe(true) -- the real map, as Controls binds it
			-- and each key does what the map says when Controls resolves it (design review 004 F1)
			for key, action in Pad.BUTTONS do
				t.expect(Pad.action(key)).toBe(action)
			end
			local planned = copy(MAP)
			planned.ButtonY = "Pick"
			planned.ButtonL3 = "Boost"
			t.expect(ownActions(planned)).toBe(true) -- f0126's and f0143's buttons
			for _, reused in { "Jump", "Fire", "Snap", "Forward", "Back", "Left", "Right" } do
				local bad = copy(planned)
				bad.ButtonB = reused
				t.expect(ownActions(bad)).toBe(false)
			end
			local twice = copy(planned)
			twice.ButtonX = "Pick"
			t.expect(ownActions(twice)).toBe(false)
		end
	)

	it("f0146's case still fails when any of today's seven entries changes action or is missing", function()
		t.expect(withMap(copy(MAP))).toBe(true) -- MAP is today's map, so each failure below is that one entry's
		for key, action in MAP do
			local swapped = copy(MAP)
			swapped[key] = SWAP[action]
			t.expect(withMap(swapped)).toBe(false)
			local missing = copy(MAP)
			missing[key] = nil
			t.expect(withMap(missing)).toBe(false)
		end
	end)
end)
