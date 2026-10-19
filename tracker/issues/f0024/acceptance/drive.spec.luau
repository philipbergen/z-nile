--!strict
-- f0024 AC5: retry, backoff and budget are a pure policy. Writes go through commit and an ordered
-- max, so a later lower score cannot replace a higher one. A zero list budget still reads the top.
local Hiscores = require("@logic/Hiscores")
local t = require("@tests/lib/t")

local FRI = 1792108800

local function attempt(userId: string, score: number, level: number, name: string?): any
	return { userId = userId, score = score, level = level, name = if name == nil then "Ada" else name }
end

return t.spec("f0024 drive policy", function(it)
	it("the default delays are 0, 0.25 and 0.5, and a cap holds", function()
		local delays = Hiscores.attemptDelays(Hiscores.RETRY)
		t.expect(Hiscores.RETRY.attempts).toBe(3)
		t.expect(Hiscores.RETRY.base).toBe(0.25)
		t.expect(Hiscores.RETRY.cap).toBe(1)
		t.expect(#delays).toBe(3)
		t.expect(delays[1]).toBe(0)
		t.expect(delays[2]).toBe(0.25)
		t.expect(delays[3]).toBe(0.5)
		t.expect(Hiscores.retryDelay(Hiscores.RETRY, 0)).toBe(nil)
		t.expect(Hiscores.retryDelay(Hiscores.RETRY, 4)).toBe(nil)
		local capped = Hiscores.attemptDelays({ attempts = 5, base = 10, cap = 12 })
		t.expect(capped[1]).toBe(0)
		t.expect(capped[2]).toBe(10)
		t.expect(capped[3]).toBe(12)
		t.expect(capped[4]).toBe(12)
		t.expect(capped[5]).toBe(12)
	end)

	it("a budget below the cost is refused and the remainder stays", function()
		local ok, left = Hiscores.spend(0, 1)
		t.expect(ok).toBe(false)
		t.expect(left).toBe(0)
		local spent, rest = Hiscores.spend(2, 1)
		t.expect(spent).toBe(true)
		t.expect(rest).toBe(1)
	end)

	it("a lower score commits nothing, and a better score copies a new row", function()
		local stored = { name = "Ada", userId = "7", level = 2, score = 50 }
		t.expect(Hiscores.commit(stored, attempt("7", 10, 9, "Nope"))).toBe(nil)
		t.expect(stored.name).toBe("Ada")
		t.expect(stored.score).toBe(50)
		local better = Hiscores.commit(stored, attempt("7", 80, 2, "Bea"))
		t.expect(better.name).toBe("Bea")
		t.expect(better.score).toBe(80)
		t.expect(stored.name).toBe("Ada")
	end)

	it("a first-try success writes every board, waits nothing, and ranks", function()
		local entries: { [string]: any } = {}
		local waits: { number } = {}
		local function slot(board: any, key: string): string
			return board.id .. ":" .. (board.period or "") .. ":" .. key
		end
		local io = {
			get = function(board: any, key: string): (any, string?)
				return entries[slot(board, key)], nil
			end,
			updateEntry = function(board: any, key: string, transform: (any) -> any): (any, string?)
				local nextEntry = transform(entries[slot(board, key)])
				if nextEntry == nil then
					return nil, nil
				end
				entries[slot(board, key)] = nextEntry
				return nextEntry, nil
			end,
			updateScore = function(board: any, key: string, packed: number): (number?, string?)
				local id = slot(board, key)
				local kept = math.max(entries[id .. ":packed"] or 0, packed)
				entries[id .. ":packed"] = kept
				return kept, nil
			end,
			top = function(board: any): (any, string?)
				local id = slot(board, "7")
				local row = entries[id]
				if row == nil then
					return { {} }, nil
				end
				return { { { key = "7", score = row.score } } }, nil
			end,
			budget = function(_op: string): number
				return 5
			end,
			wait = function(seconds: number)
				table.insert(waits, seconds)
			end,
		}
		local result = Hiscores.drive(io, attempt("7", 80, 3, "Zed"), FRI, Hiscores.RETRY)
		t.expect(result.wrote.all).toBe(true)
		t.expect(result.wrote.day).toBe(true)
		t.expect(result.wrote.week).toBe(true)
		t.expect(result.rank).toBe(1)
		t.expect(#waits).toBe(0)
		local allKey = slot(Hiscores.board("all", FRI), "7")
		t.expect(entries[allKey .. ":packed"]).toBe(Hiscores.pack(80, 3))
		local lower = Hiscores.drive(io, attempt("7", 10, 9, "Nope"), FRI, Hiscores.RETRY)
		t.expect(lower.wrote.all).toBe(false)
		t.expect(entries[allKey].name).toBe("Zed")
		t.expect(entries[allKey .. ":packed"]).toBe(Hiscores.pack(80, 3))
		local bump = Hiscores.drive(io, attempt("7", 80, 5, "Zed2"), FRI, Hiscores.RETRY)
		t.expect(bump.wrote.all).toBe(true)
		t.expect(entries[allKey].name).toBe("Zed2")
		t.expect(entries[allKey .. ":packed"]).toBe(Hiscores.pack(80, 5))
	end)

	it("a zero read budget never updates, still waits, and still calls top", function()
		local updates = 0
		local tops = 0
		local waits: { number } = {}
		local io = {
			get = function(_board: any, _key: string): (any, string?)
				updates += 1
				return nil, "down"
			end,
			updateEntry = function(_board: any, _key: string, _transform: (any) -> any): (any, string?)
				updates += 1
				return nil, "down"
			end,
			updateScore = function(_board: any, _key: string, _packed: number): (number?, string?)
				updates += 1
				return nil, "down"
			end,
			top = function(_board: any): (any, string?)
				tops += 1
				return { { { key = "1", score = 10 } } }, nil
			end,
			budget = function(op: string): number
				if op == "get" or op == "sorted" then
					return 0
				end
				return 5
			end,
			wait = function(seconds: number)
				table.insert(waits, seconds)
			end,
		}
		local result = Hiscores.drive(io, attempt("1", 10, 1), FRI, Hiscores.RETRY)
		t.expect(updates).toBe(0)
		t.expect(result.wrote.all).toBe(false)
		t.expect(waits[1]).toBe(0.25)
		t.expect(waits[2]).toBe(0.5)
		t.expect(#waits).toBe(6)
		t.expect(tops).toBe(1)
		t.expect(result.rank).toBe(nil)
	end)

	it("a write budget of zero skips the update even when the read budget is open", function()
		local updates = 0
		local io = {
			get = function(_board: any, _key: string): (any, string?)
				return nil, nil
			end,
			updateEntry = function(_board: any, _key: string, _transform: (any) -> any): (any, string?)
				updates += 1
				return nil, nil
			end,
			updateScore = function(_board: any, _key: string, _packed: number): (number?, string?)
				updates += 1
				return nil, nil
			end,
			top = function(_board: any): (any, string?)
				return { {} }, nil
			end,
			budget = function(op: string): number
				if op == "set" or op == "setSorted" then
					return 0
				end
				return 5
			end,
			wait = function(_seconds: number) end,
		}
		local result = Hiscores.drive(io, attempt("1", 10, 1), FRI, Hiscores.RETRY)
		t.expect(updates).toBe(0)
		t.expect(result.wrote.all).toBe(false)
	end)

	it("a zero list budget still reads the top and can rank", function()
		local tops = 0
		local io = {
			get = function(_board: any, _key: string): (any, string?)
				return { name = "A", userId = "1", level = 2, score = 10 }, nil
			end,
			updateEntry = function(_board: any, _key: string, transform: (any) -> any): (any, string?)
				return transform(nil), nil
			end,
			updateScore = function(_board: any, _key: string, packed: number): (number?, string?)
				return packed, nil
			end,
			top = function(_board: any): (any, string?)
				tops += 1
				return { { { key = "1", score = 20 } } }, nil
			end,
			budget = function(op: string): number
				if op == "sorted" then
					return 0
				end
				return 5
			end,
			wait = function(_seconds: number) end,
		}
		local result = Hiscores.drive(io, attempt("1", 20, 2, "A"), FRI, Hiscores.RETRY)
		t.expect(tops).toBe(1)
		t.expect(result.rank).toBe(1)
		t.expect(result.wrote.all).toBe(true)
	end)

	it("a failed read is retried, and a row that does not qualify is not written or retried", function()
		local failed: { [string]: boolean } = {}
		local waits: { number } = {}
		local scores = 0
		local io = {
			get = function(_board: any, _key: string): (any, string?)
				return nil, nil
			end,
			updateEntry = function(board: any, _key: string, transform: (any) -> any): (any, string?)
				if board.id == "all" and failed.all ~= true then
					failed.all = true
					return nil, "down"
				end
				local nextEntry = transform(nil)
				if nextEntry == nil then
					return nil, nil
				end
				return nextEntry, nil
			end,
			updateScore = function(_board: any, _key: string, _packed: number): (number?, string?)
				scores += 1
				return 1, nil
			end,
			top = function(_board: any): (any, string?)
				return { {} }, nil
			end,
			budget = function(_op: string): number
				return 5
			end,
			wait = function(seconds: number)
				table.insert(waits, seconds)
			end,
		}
		local result = Hiscores.drive(io, attempt("1", 10, 1), FRI, Hiscores.RETRY)
		t.expect(result.wrote.all).toBe(true)
		t.expect(result.wrote.day).toBe(true)
		t.expect(#waits).toBe(1)
		t.expect(waits[1]).toBe(0.25)
		t.expect(scores).toBe(3)
		local blockedWrites = 0
		local blockedWaits: { number } = {}
		local blocked = {
			get = function(_board: any, _key: string): (any, string?)
				return { name = "Old", userId = "1", level = 5, score = 100 }, nil
			end,
			updateEntry = function(_board: any, _key: string, transform: (any) -> any): (any, string?)
				local nextEntry = transform({ name = "Old", userId = "1", level = 5, score = 100 })
				if nextEntry == nil then
					return nil, nil
				end
				blockedWrites += 1
				return nextEntry, nil
			end,
			updateScore = function(_board: any, _key: string, _packed: number): (number?, string?)
				blockedWrites += 1
				return 1, nil
			end,
			top = function(_board: any): (any, string?)
				return { {} }, nil
			end,
			budget = function(_op: string): number
				return 5
			end,
			wait = function(seconds: number)
				table.insert(blockedWaits, seconds)
			end,
		}
		local lower = Hiscores.drive(blocked, attempt("1", 10, 9, "Nope"), FRI, Hiscores.RETRY)
		t.expect(lower.wrote.all).toBe(false)
		t.expect(blockedWrites).toBe(0)
		t.expect(#blockedWaits).toBe(0)
	end)

	it("one board's failure does not stop the others, and an invalid attempt writes nothing", function()
		local scores = 0
		local tops = 0
		local io = {
			get = function(_board: any, _key: string): (any, string?)
				return nil, nil
			end,
			updateEntry = function(board: any, _key: string, transform: (any) -> any): (any, string?)
				if board.id == "all" then
					return nil, "down"
				end
				return transform(nil), nil
			end,
			updateScore = function(board: any, _key: string, _packed: number): (number?, string?)
				if board.id ~= "all" then
					scores += 1
				end
				return 1, nil
			end,
			top = function(_board: any): (any, string?)
				tops += 1
				return { {} }, nil
			end,
			budget = function(_op: string): number
				return 5
			end,
			wait = function(_seconds: number) end,
		}
		local result = Hiscores.drive(io, attempt("1", 10, 1), FRI, Hiscores.RETRY)
		t.expect(result.wrote.all).toBe(false)
		t.expect(result.wrote.day).toBe(true)
		t.expect(result.wrote.week).toBe(true)
		t.expect(scores).toBe(2)
		local updates = 0
		local invalidTops = 0
		local invalid = {
			get = function(_board: any, _key: string): (any, string?)
				updates += 1
				return nil, nil
			end,
			updateEntry = function(_board: any, _key: string, _transform: (any) -> any): (any, string?)
				updates += 1
				return nil, nil
			end,
			updateScore = function(_board: any, _key: string, _packed: number): (number?, string?)
				updates += 1
				return nil, nil
			end,
			top = function(_board: any): (any, string?)
				invalidTops += 1
				return { {} }, nil
			end,
			budget = function(_op: string): number
				return 5
			end,
			wait = function(_seconds: number) end,
		}
		local bad = Hiscores.drive(invalid, attempt("nope", 10, 1), FRI, Hiscores.RETRY)
		t.expect(bad.wrote.all).toBe(false)
		t.expect(updates).toBe(0)
		t.expect(invalidTops).toBe(1)
		t.expect(tops).toBe(1)
	end)

	it("overlapping drives keep 5000, and a failed ordered write retries that score", function()
		local entry: any = nil
		local packedSeen: { number } = {}
		local nested = false
		local io: any
		io = {
			get = function(_board: any, _key: string): (any, string?)
				return entry, nil
			end,
			updateEntry = function(_board: any, _key: string, transform: (any) -> any): (any, string?)
				local nextEntry = transform(entry)
				if nextEntry == nil then
					return nil, nil
				end
				entry = nextEntry
				if not nested then
					nested = true
					Hiscores.drive(io, attempt("7", 100, 1, "Low"), FRI, Hiscores.RETRY)
				end
				return nextEntry, nil
			end,
			updateScore = function(_board: any, _key: string, packed: number): (number?, string?)
				table.insert(packedSeen, packed)
				return packed, nil
			end,
			top = function(_board: any): (any, string?)
				return { {} }, nil
			end,
			budget = function(_op: string): number
				return 5
			end,
			wait = function(_seconds: number) end,
		}
		Hiscores.drive(io, attempt("7", 5000, 2, "High"), FRI, Hiscores.RETRY)
		t.expect(entry.name).toBe("High")
		t.expect(entry.score).toBe(5000)
		t.expect(#packedSeen > 0).toBe(true)
		for _, packed in packedSeen do
			t.expect(packed).toBe(Hiscores.pack(5000, 2))
		end

		local commits = 0
		local retried: { number } = {}
		local scoreFails = 0
		local retryIo = {
			get = function(_board: any, _key: string): (any, string?)
				return nil, nil
			end,
			updateEntry = function(_board: any, _key: string, transform: (any) -> any): (any, string?)
				commits += 1
				return transform(nil), nil
			end,
			updateScore = function(_board: any, _key: string, packed: number): (number?, string?)
				scoreFails += 1
				if scoreFails == 1 then
					return nil, "down"
				end
				table.insert(retried, packed)
				return packed, nil
			end,
			top = function(_board: any): (any, string?)
				return { {} }, nil
			end,
			budget = function(_op: string): number
				return 5
			end,
			wait = function(_seconds: number) end,
		}
		local result = Hiscores.drive(retryIo, attempt("1", 5000, 4, "Ada"), FRI, Hiscores.RETRY)
		t.expect(result.wrote.all).toBe(true)
		t.expect(commits).toBe(3)
		t.expect(#retried > 0).toBe(true)
		for _, packed in retried do
			t.expect(packed).toBe(Hiscores.pack(5000, 4))
			t.expect(packed ~= 100).toBe(true)
			t.expect(packed ~= 5000).toBe(true)
		end
	end)
end)
