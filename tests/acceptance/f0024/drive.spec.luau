--!strict
-- f0024 AC5: retry, backoff and budget are a pure policy. Both writes are transforms the store applies to the
-- row it actually holds: commit for the companion, a max of the packed score for the ordered key. The doubles
-- here store whatever the transform returns and never do the policy themselves. A zero list budget still
-- reads the top.
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
		local better: any = Hiscores.commit(stored, attempt("7", 80, 2, "Bea"))
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
			updateScore = function(
				board: any,
				key: string,
				transform: (number?) -> number?
			): (number?, string?)
				local id = slot(board, key) .. ":packed"
				local nextValue = transform(entries[id])
				if nextValue ~= nil then
					entries[id] = nextValue
				end
				return nextValue, nil
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
			updateScore = function(
				_board: any,
				_key: string,
				_transform: (number?) -> number?
			): (number?, string?)
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
			updateScore = function(
				_board: any,
				_key: string,
				_transform: (number?) -> number?
			): (number?, string?)
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

	it(
		"a zero ordered read budget skips only the ordered update, and the companion is still written",
		function()
			local entryWrites = 0
			local scoreWrites = 0
			local io = {
				get = function(_board: any, _key: string): (any, string?)
					return nil, nil
				end,
				updateEntry = function(_board: any, _key: string, transform: (any) -> any): (any, string?)
					entryWrites += 1
					return transform(nil), nil
				end,
				updateScore = function(
					_board: any,
					_key: string,
					transform: (number?) -> number?
				): (number?, string?)
					scoreWrites += 1
					return transform(nil), nil
				end,
				top = function(_board: any): (any, string?)
					return { {} }, nil
				end,
				budget = function(op: string): number
					if op == "getSorted" then
						return 0
					end
					return 5
				end,
				wait = function(_seconds: number) end,
			}
			local result = Hiscores.drive(io, attempt("1", 10, 1), FRI, Hiscores.RETRY)
			t.expect(entryWrites).toBe(3)
			t.expect(scoreWrites).toBe(0)
			t.expect(result.wrote.all).toBe(false)
		end
	)

	it("a zero list budget still reads the top and can rank", function()
		local tops = 0
		local io = {
			get = function(_board: any, _key: string): (any, string?)
				return { name = "A", userId = "1", level = 2, score = 10 }, nil
			end,
			updateEntry = function(_board: any, _key: string, transform: (any) -> any): (any, string?)
				return transform(nil), nil
			end,
			updateScore = function(
				_board: any,
				_key: string,
				transform: (number?) -> number?
			): (number?, string?)
				return transform(nil), nil
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

	it("a failed read is retried, and a row that does not qualify is not rewritten or retried", function()
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
			updateScore = function(
				_board: any,
				_key: string,
				_transform: (number?) -> number?
			): (number?, string?)
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
		local entryWrites = 0
		local stored: { number } = {}
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
				entryWrites += 1
				return nextEntry, nil
			end,
			updateScore = function(
				_board: any,
				_key: string,
				transform: (number?) -> number?
			): (number?, string?)
				local nextValue = transform(nil)
				table.insert(stored, nextValue :: number)
				return nextValue, nil
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
		t.expect(lower.wrote.day).toBe(false)
		t.expect(entryWrites).toBe(0)
		t.expect(#blockedWaits).toBe(0)
		-- the row stands, and its ordered key is brought up to the row actually stored, never to the attempt
		t.expect(#stored).toBe(3)
		for _, value in stored do
			t.expect(value).toBe(Hiscores.pack(100, 5))
		end
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
			updateScore = function(
				board: any,
				_key: string,
				_transform: (number?) -> number?
			): (number?, string?)
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
			updateScore = function(
				_board: any,
				_key: string,
				_transform: (number?) -> number?
			): (number?, string?)
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

	it(
		"overlapping drives keep 5000: the loser's transform sees the live row, not the snapshot get returned",
		function()
			local entry: any = nil
			local ordered: number? = nil
			local storedOrdered: { number } = {}
			local nested = false
			local io: any
			io = {
				-- the snapshot from before either drive: a drive that commits from it publishes a stale row
				get = function(_board: any, _key: string): (any, string?)
					return nil, nil
				end,
				updateEntry = function(board: any, _key: string, transform: (any) -> any): (any, string?)
					if board.id ~= "all" then
						return transform(nil), nil
					end
					local nextEntry = transform(entry)
					if nextEntry ~= nil then
						entry = nextEntry
					end
					if not nested then
						nested = true
						Hiscores.drive(io, attempt("7", 100, 1, "Low"), FRI, Hiscores.RETRY)
					end
					return nextEntry, nil
				end,
				updateScore = function(
					board: any,
					_key: string,
					transform: (number?) -> number?
				): (number?, string?)
					if board.id ~= "all" then
						return transform(nil), nil
					end
					local nextValue = transform(ordered)
					if nextValue ~= nil then
						ordered = nextValue
						table.insert(storedOrdered, nextValue)
					end
					return nextValue, nil
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
			t.expect(ordered).toBe(Hiscores.pack(5000, 2))
			t.expect(#storedOrdered >= 2).toBe(true)
			for _, value in storedOrdered do
				t.expect(value).toBe(Hiscores.pack(5000, 2))
			end
		end
	)

	it("a retried ordered write keeps a higher value another drive stored, and does not recommit", function()
		local commits = 0
		local ordered: { [string]: number } = {}
		local failedOnce = false
		local retryIo = {
			get = function(_board: any, _key: string): (any, string?)
				return nil, nil
			end,
			updateEntry = function(_board: any, _key: string, transform: (any) -> any): (any, string?)
				commits += 1
				return transform(nil), nil
			end,
			updateScore = function(
				board: any,
				_key: string,
				transform: (number?) -> number?
			): (number?, string?)
				if board.id == "all" and not failedOnce then
					failedOnce = true
					-- the write failed, and meanwhile a better run on another server stored its score
					ordered.all = Hiscores.pack(8000, 1)
					return nil, "down"
				end
				local nextValue = transform(ordered[board.id])
				if nextValue ~= nil then
					ordered[board.id] = nextValue
				end
				return nextValue, nil
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
		t.expect(ordered.all).toBe(Hiscores.pack(8000, 1))
		t.expect(ordered.day).toBe(Hiscores.pack(5000, 4))
		t.expect(ordered.week).toBe(Hiscores.pack(5000, 4))
	end)

	it(
		"an ordered key every retry missed is repaired by the next attempt, even one that does not qualify",
		function()
			local entries: { [string]: any } = {}
			local ordered: { [string]: number } = {}
			local down = true
			local io = {
				get = function(_board: any, _key: string): (any, string?)
					return nil, nil
				end,
				updateEntry = function(board: any, _key: string, transform: (any) -> any): (any, string?)
					local nextEntry = transform(entries[board.id])
					if nextEntry ~= nil then
						entries[board.id] = nextEntry
					end
					return nextEntry, nil
				end,
				updateScore = function(
					board: any,
					_key: string,
					transform: (number?) -> number?
				): (number?, string?)
					if down then
						return nil, "down"
					end
					local nextValue = transform(ordered[board.id])
					if nextValue ~= nil then
						ordered[board.id] = nextValue
					end
					return nextValue, nil
				end,
				top = function(_board: any): (any, string?)
					return { {} }, nil
				end,
				budget = function(_op: string): number
					return 5
				end,
				wait = function(_seconds: number) end,
			}
			local first = Hiscores.drive(io, attempt("1", 5000, 4, "Ada"), FRI, Hiscores.RETRY)
			t.expect(first.wrote.all).toBe(false)
			t.expect(entries.all.score).toBe(5000)
			t.expect(ordered.all).toBe(nil)
			down = false
			local second = Hiscores.drive(io, attempt("1", 100, 1, "Ada"), FRI, Hiscores.RETRY)
			t.expect(second.wrote.all).toBe(false)
			t.expect(entries.all.score).toBe(5000)
			t.expect(ordered.all).toBe(Hiscores.pack(5000, 4))
			t.expect(ordered.day).toBe(Hiscores.pack(5000, 4))
		end
	)

	it("a companion read that fails on the page gives no rank, rather than a better one", function()
		local gets = 0
		local topped = false
		local function io(failKey: string?, getBudget: () -> number): any
			return {
				get = function(_board: any, key: string): (any, string?)
					gets += 1
					if key == failKey then
						return nil, "throttled"
					end
					if key == "2" then
						return { name = "Bea", userId = "2", level = 3, score = 80 }, nil
					end
					return { name = "Ada", userId = "7", level = 2, score = 50 }, nil
				end,
				updateEntry = function(_board: any, _key: string, transform: (any) -> any): (any, string?)
					return transform(nil), nil
				end,
				updateScore = function(
					_board: any,
					_key: string,
					transform: (number?) -> number?
				): (number?, string?)
					return transform(nil), nil
				end,
				top = function(_board: any): (any, string?)
					topped = true
					return { { { key = "2", score = 80 }, { key = "7", score = 50 } } }, nil
				end,
				budget = function(op: string): number
					if op == "get" then
						return getBudget()
					end
					return 5
				end,
				wait = function(_seconds: number) end,
			}
		end
		local healthy = Hiscores.drive(
			io(nil, function(): number
				return 5
			end),
			attempt("7", 50, 2),
			FRI,
			Hiscores.RETRY
		)
		t.expect(healthy.rank).toBe(2)
		local failed = Hiscores.drive(
			io("2", function(): number
				return 5
			end),
			attempt("7", 50, 2),
			FRI,
			Hiscores.RETRY
		)
		t.expect(failed.rank).toBe(nil)
		t.expect(failed.wrote.all).toBe(true)
		-- the read budget refuses the page's first key, the row above the player: no rank, not rank 1
		gets = 0
		topped = false
		local afterTop = 0
		local short = Hiscores.drive(
			io(nil, function(): number
				if not topped then
					return 5
				end
				afterTop += 1
				return if afterTop == 1 then 0 else 5
			end),
			attempt("7", 50, 2),
			FRI,
			Hiscores.RETRY
		)
		t.expect(short.wrote.all).toBe(true)
		t.expect(gets <= 1).toBe(true)
		t.expect(short.rank).toBe(nil)
	end)
end)
