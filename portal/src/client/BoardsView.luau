--!strict
-- Portal client adapter (f0206): fills each card's Boards slot (CarouselView, f0205) with the title's hiscores: three
-- tabs (ALL-TIME, TODAY, THIS WEEK), a header naming the title's progress figure, ten rows (rank, name, score, the
-- figure and the revives used, "—" for none) and the "your best" line under every tab. One tab is chosen for every
-- card: a tap on a tab, or W/S, Up/Down and the triggers, through one ContextActionService binding between the default
-- controls' priority and the test purchase screen's; nothing on the board is gamepad-selectable (f0208: ButtonA stays
-- the carousel's PLAY). It asks the server for every card's board on the chosen tab (Board.wants), each again every
-- Board.REASK seconds (Board.WAIT_RETRY after a wait or while the player's best is pending); everything it shows is
-- Board's view of the answers, read through Board.parse.
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Board = require("@game/ReplicatedStorage/Shared/Logic/Board")
local Card = require("@game/ReplicatedStorage/Shared/Logic/Card")
local CarouselView = require("./CarouselView")
local Games = require("@game/ReplicatedStorage/Shared/Games")
local HiscoreGames = require("@game/ReplicatedStorage/Arcade/HiscoreGames")

type Line = { frame: Frame, cells: { TextLabel } }
type Parts = {
	slot: Frame,
	tabs: { [string]: TextButton },
	header: { TextLabel },
	rows: ScrollingFrame,
	lines: { Line },
	note: TextLabel,
	best: Line,
}

local BoardsView = {}

local started = false
local tab: Board.Id = "all"
local names: { [string]: boolean } = {}
local order: { string } = {}
local held: { [string]: { [string]: Board.Answer } } = {}
local mine: { [string]: Board.Mine } = {}
local parts: { [string]: Parts } = {}
local asked: { [string]: Board.Asked } = {} -- by "<title>|<board id>"
local remote: RemoteEvent? = nil

local ALIGN: { [string]: Enum.TextXAlignment } = {
	Left = Enum.TextXAlignment.Left,
	Right = Enum.TextXAlignment.Right,
}

local function text(parent: Instance, name: string): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.TextColor3 = Color3.new(1, 1, 1)
	l.Font = Enum.Font.GothamBold
	l.TextScaled = false -- one size for the board (Board.layout), so a long name is cut, never shrunk
	l.TextTruncate = Enum.TextTruncate.AtEnd
	l.Text = ""
	l.Parent = parent
	return l
end

-- one Frame of five column labels, named by Board.COLUMNS
local function columns(parent: Instance, name: string): (Frame, { TextLabel })
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundTransparency = 1
	f.BackgroundColor3 = Color3.fromRGB(255, 221, 0)
	f.Parent = parent
	local cells: { TextLabel } = {}
	for _, c in Board.COLUMNS do
		local l = text(f, c.name)
		l.Position = UDim2.fromScale(c.x, 0)
		l.Size = UDim2.fromScale(c.width, 1)
		l.TextXAlignment = ALIGN[c.align]
		table.insert(cells, l)
	end
	return f, cells
end

local function place(p: Parts)
	local layout = Board.layout(p.slot.AbsoluteSize.X, p.slot.AbsoluteSize.Y, Card.GLYPH)
	local header = p.header[1].Parent :: Frame
	header.Position = UDim2.fromOffset(0, layout.tabs)
	header.Size = UDim2.new(1, 0, 0, layout.line)
	p.rows.Position = UDim2.fromOffset(0, layout.tabs + layout.line)
	p.rows.Size = UDim2.new(1, 0, 0, layout.view)
	p.rows.CanvasSize = UDim2.fromOffset(0, layout.canvas)
	p.rows.ScrollingEnabled = layout.canvas > layout.view
	for i, line in p.lines do
		line.frame.Position = UDim2.fromOffset(0, (i - 1) * layout.line)
		line.frame.Size = UDim2.new(1, 0, 0, layout.line)
	end
	p.note.Position = UDim2.fromOffset(0, layout.tabs + layout.line)
	p.note.Size = UDim2.new(1, 0, 0, math.min(layout.view, 2 * layout.line))
	p.best.frame.Position = UDim2.new(0, 0, 1, -layout.line)
	p.best.frame.Size = UDim2.new(1, 0, 0, layout.line)
	for _, button in p.tabs do
		button.TextSize = layout.text
	end
	p.note.TextSize = layout.text
	for _, cells in { p.header, p.best.cells } do
		for _, cell in cells do
			cell.TextSize = layout.text
		end
	end
	for _, line in p.lines do
		for _, cell in line.cells do
			cell.TextSize = layout.text
		end
	end
end

local function draw(name: string)
	local p = parts[name]
	if p == nil then
		return
	end
	local hiscores = (HiscoreGames :: any)[name]
	local progress = if hiscores ~= nil then hiscores.progress else ""
	local view = Board.view(held[name][tab], progress, mine[name])
	for id, button in p.tabs do
		button.BackgroundTransparency = if id == tab then 0 else 0.6
	end
	for i, cell in p.header do
		cell.Text = view.header[i]
	end
	for i, line in p.lines do
		local shown = view.lines[i]
		line.frame.Visible = shown ~= nil
		line.frame.BackgroundTransparency = if shown ~= nil and shown.mine then 0.5 else 1
		for c, cell in line.cells do
			cell.Text = if shown ~= nil then shown.cells[c] else ""
		end
	end
	p.note.Text = view.note
	local best = view.best
	p.best.frame.Visible = best ~= nil
	for c, cell in p.best.cells do
		cell.Text = if best ~= nil then best[c] else ""
	end
end

local function drawAll()
	for _, entry in Games.LIST do
		draw(entry.name)
	end
end

local function choose(id: Board.Id)
	tab = id
	drawAll()
end

local function build(name: string, slot: Frame)
	local tabs: { [string]: TextButton } = {}
	local bar = Instance.new("Frame")
	bar.Name = "Tabs"
	bar.BackgroundTransparency = 1
	bar.Size = UDim2.new(1, 0, 0, Board.TAB_PX)
	bar.Parent = slot
	for i, id in Board.TABS do
		local b = Instance.new("TextButton")
		b.Name = id
		b.Position = UDim2.fromScale((i - 1) / #Board.TABS, 0)
		b.Size = UDim2.fromScale(1 / #Board.TABS, 1)
		b.BackgroundColor3 = Color3.fromRGB(255, 221, 0)
		b.TextColor3 = Color3.new(0, 0, 0)
		b.Font = Enum.Font.GothamBold
		b.TextScaled = false
		b.Text = (Board.TAB_TEXT :: any)[id]
		b.Selectable = false -- never gamepad-selected, so ButtonA stays the carousel's PLAY (f0208)
		b.Parent = bar
		b.Activated:Connect(function()
			choose(id)
		end)
		tabs[id] = b
	end
	local _, header = columns(slot, "Header")
	local rows = Instance.new("ScrollingFrame")
	rows.Name = "Rows"
	rows.BackgroundTransparency = 1
	rows.BorderSizePixel = 0
	rows.ScrollBarThickness = 4
	rows.ScrollingDirection = Enum.ScrollingDirection.Y
	rows.Selectable = false
	rows.Parent = slot
	local lines: { Line } = {}
	for i = 1, Board.N do
		local frame, cells = columns(rows, `Row{i}`)
		table.insert(lines, { frame = frame, cells = cells })
	end
	local note = text(slot, "Note")
	note.TextWrapped = true
	local bestFrame, bestCells = columns(slot, "Best")
	-- YOUR BEST takes the rank's column too, from the rank's left edge to the name's right one
	local rank, named = Board.COLUMNS[1], Board.COLUMNS[2]
	bestCells[2].Position = UDim2.fromScale(rank.x, 0)
	bestCells[2].Size = UDim2.fromScale(named.x + named.width - rank.x, 1)
	local best: Line = { frame = bestFrame, cells = bestCells }
	local p: Parts =
		{ slot = slot, tabs = tabs, header = header, rows = rows, lines = lines, note = note, best = best }
	parts[name] = p
	place(p)
	slot:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		place(p)
	end)
end

-- Fills every card's Boards slot, binds the tab keys and asks for every card's board. Once; returns at once.
function BoardsView.start()
	if started then
		return
	end
	started = true
	CarouselView.start()
	for _, entry in Games.LIST do
		names[entry.name] = true
		table.insert(order, entry.name)
		held[entry.name] = {}
		local card = CarouselView.card(entry.name)
		local slot = if card ~= nil then card:FindFirstChild("Boards") else nil
		if slot ~= nil and slot:IsA("Frame") then
			build(entry.name, slot)
		end
	end
	drawAll()

	local keys: { any } = {}
	for key in Board.KEYS do
		table.insert(keys, (Enum.KeyCode :: any)[key])
	end
	ContextActionService:BindActionAtPriority(
		Board.ACTION,
		function(_: string, state: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
			if UserInputService:GetFocusedTextBox() ~= nil then
				return Enum.ContextActionResult.Pass -- typing (the chat box): the keys are the text's
			end
			if state == Enum.UserInputState.Begin then
				local step = Board.step(input.KeyCode.Name)
				if step ~= nil then
					choose(Board.tab(tab, step))
				end
			end
			return Enum.ContextActionResult.Sink
		end,
		false,
		Board.PRIORITY,
		table.unpack(keys)
	)

	RunService.Heartbeat:Connect(function()
		local r = remote
		if r == nil then
			return
		end
		local now = os.clock()
		for _, want in Board.wants(tab, order, mine) do
			local key = `{want.name}|{want.id}`
			if Board.askDue(asked[key], now) then
				asked[key] = { at = now, wait = false }
				r:FireServer(want.name, want.id)
			end
		end
	end)

	task.spawn(function()
		local found = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Boards") :: RemoteEvent
		found.OnClientEvent:Connect(function(...: any)
			local answer = Board.parse(names, ...)
			if answer == nil then
				return
			end
			held[answer.name][answer.id] = answer
			mine[answer.name] = Board.learn(mine[answer.name], answer)
			local last = asked[`{answer.name}|{answer.id}`]
			if last ~= nil then
				last.wait = answer.status == "wait" or answer.pending
			end
			draw(answer.name)
		end)
		remote = found
	end)
end

return BoardsView
