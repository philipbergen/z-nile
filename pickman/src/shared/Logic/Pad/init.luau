--!strict
-- Pad: the gamepad (f0146), engine-free. The buttons map to the same actions as the keys; the left stick folds into
-- turn intents relative to the heading, one a push; the right stick looks at a rate, in View.look's units.
local Movement = require("./Movement")
local View = require("./View")

export type Steer = { held: Movement.Intent? } -- the sector the left stick is engaged in, nil when released

local BUTTONS: { [string]: View.Action } = {
	ButtonA = "Jump", -- the bottom face button: PlayStation's cross, Xbox's A
	ButtonR2 = "Fire",
	ButtonR3 = "Snap",
	DPadUp = "Forward",
	DPadDown = "Back",
	DPadLeft = "Left",
	DPadRight = "Right",
}

local Pad = {}
Pad.BUTTONS = table.freeze(BUTTONS)
Pad.CONTINUE = "ButtonA" -- continues on the overlay at the end of a run
Pad.STEER_ON = 0.6 -- stick tilt that engages a sector
Pad.STEER_OFF = 0.4 -- tilt below which the stick is released
Pad.STEER_MARGIN = 15 -- degrees past the diagonal an engaged stick must turn to change sector
Pad.LOOK_DEAD = 0.15 -- radial dead zone of the right stick
Pad.LOOK_YAW = 3 -- radians a second at full tilt, left and right
Pad.LOOK_PITCH = 2 -- radians a second at full tilt, up and down
Pad.INVERT = false -- pushing up looks up

local function finite(v: any): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

function Pad.action(keyName: string): View.Action?
	return BUTTONS[keyName]
end

function Pad.isPad(inputType: string): boolean
	local n = tonumber(string.match(inputType, "^Gamepad(%d)$"))
	return n ~= nil and n >= 1 and n <= 8
end

-- The controller that drives now (decided with the user, 2026-10-25: the most recently used): an input from a
-- gamepad of `magnitude` (1 for a button, the tilt for a stick) takes over when it is at least STEER_OFF, so an idle
-- pad's drift never does; any other input keeps the one before.
function Pad.track(active: string?, inputType: string, magnitude: number): string?
	if Pad.isPad(inputType) and finite(magnitude) and magnitude >= Pad.STEER_OFF then
		return inputType
	end
	return active
end

local AXIS: { [string]: number } = { Forward = 90, Back = -90, Left = 180, Right = 0 }

-- degrees between the tilt's direction and a sector's axis, 0..180
local function off(x: number, y: number, held: Movement.Intent): number
	local deg = math.deg(math.atan2(y, x))
	local d = math.abs(deg - AXIS[held]) % 360
	return if d > 180 then 360 - d else d
end

function Pad.steerStart(): Steer
	return { held = nil }
end

-- the sector of a tilt: the dominant axis, a tie going vertical (x right, y up)
local function sector(x: number, y: number): Movement.Intent
	local up: Movement.Intent, down: Movement.Intent = "Forward", "Back"
	local right: Movement.Intent, left: Movement.Intent = "Right", "Left"
	if math.abs(y) >= math.abs(x) then
		return if y >= 0 then up else down
	end
	return if x > 0 then right else left
end

-- One reading of the left stick: the new state and the turn intent to send, if any.
function Pad.steer(s: Steer, x: number, y: number): (Steer, Movement.Intent?)
	if not finite(x) or not finite(y) then
		return { held = nil }, nil
	end
	local r = math.sqrt(x * x + y * y)
	local held: Movement.Intent? = s.held
	if held == nil then
		if r >= Pad.STEER_ON then
			local now: Movement.Intent = sector(x, y)
			return { held = now }, now
		end
		return { held = nil }, nil
	end
	if r < Pad.STEER_OFF then
		return { held = nil }, nil
	end
	-- engaged: another sector only past the diagonal by the margin, so a wobble on it never flips
	if r >= Pad.STEER_ON and off(x, y, held :: Movement.Intent) > 45 + Pad.STEER_MARGIN + 1e-9 then
		local now: Movement.Intent = sector(x, y)
		return { held = now }, now
	end
	local keep: Steer = { held = held }
	return keep, nil
end

-- One reading of the right stick over `dt` seconds: the dx, dy that View.look turns by.
function Pad.look(x: number, y: number, dt: number): (number, number)
	if not finite(x) or not finite(y) or not finite(dt) or dt <= 0 then
		return 0, 0
	end
	local r = math.sqrt(x * x + y * y)
	if r < Pad.LOOK_DEAD then
		return 0, 0
	end
	local scaled = (math.min(r, 1) - Pad.LOOK_DEAD) / (1 - Pad.LOOK_DEAD)
	local a = scaled * scaled
	local k = View.MOUSE_RADIANS_PER_PIXEL
	local dx = a * (x / r) * Pad.LOOK_YAW * dt / k
	local dy = a * (y / r) * Pad.LOOK_PITCH * dt / k
	return dx, if Pad.INVERT then dy else -dy
end

return Pad
