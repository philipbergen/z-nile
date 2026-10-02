--!strict
-- Client adapter: one ball per pellet slot, shown or hidden from each frame's pellets code, with the
-- power pellets pulsing. Where and how big is View's; what is eaten is the server's.
local RunService = game:GetService("RunService")

local Maze = require("@game/ReplicatedStorage/Shared/Logic/Maze")
local Pellets = require("@game/ReplicatedStorage/Shared/Logic/Pellets")
local View = require("@game/ReplicatedStorage/Shared/Logic/View")

local COLOR = Color3.fromRGB(255, 184, 174)

export type Handle = { maze: Maze.Maze, parts: { BasePart }, power: { BasePart }, code: string? }

local PelletView = {}

local current: Handle? = nil -- the pellets being pulsed: the latest built

function PelletView.build(m: Maze.Maze, parent: Instance): Handle
	local model = Instance.new("Model")
	model.Name = "Pellets"
	local h: Handle = { maze = m, parts = {}, power = {}, code = nil }
	for i, slot in Pellets.slots(m) do
		local spot = View.pellet(slot)
		local p = Instance.new("Part")
		p.Name = slot.kind
		p.Shape = Enum.PartType.Ball
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Material = Enum.Material.Neon
		p.Color = COLOR
		p.Size = Vector3.one * spot.diameter
		p.Position = Vector3.new(spot.x, spot.y, spot.z)
		p.Parent = model
		h.parts[i] = p
		if slot.kind == "power" then
			table.insert(h.power, p)
		end
	end
	model.Parent = parent
	current = h
	return h
end

-- Shows exactly the pellets the code says are left; a repeat of the last code costs nothing.
function PelletView.show(h: Handle, code: string)
	if code == h.code then
		return
	end
	for i, present in Pellets.decode(h.maze, code) do
		h.parts[i].Transparency = if present then 0 else 1
	end
	h.code = code
end

function PelletView.start()
	local started = os.clock()
	RunService.RenderStepped:Connect(function()
		local h = current
		if h == nil then
			return
		end
		local size = Vector3.one * (View.PELLET.power * View.pulse("power", os.clock() - started))
		for _, p in h.power do
			p.Size = size
		end
	end)
end

return PelletView
