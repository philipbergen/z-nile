--!strict
-- The exchange of a dispatched run (c0256): the messages between the user and the run's steps, kept in the run's
-- state folder as `exchange/NNN-<kind>.md`, one file per message, so a re-run step reads the whole conversation with
-- its dates instead of only the latest question. Pure over names and texts; the dispatcher reads and writes the files.
--
--   001-ask.md       the user's own request (`dispatch new "<words>"`), dated from the first message
--   002-question.md  what a step stopped to ask, copied from its questions.md (a restatement is a question)
--   003-answer.md    the user's reply (an approval or a correction) from `dispatch retry`
--
-- A file is `date: <UTC time>`, for a question a `step: <the step that asked>` line, one blank line, then the message
-- exactly as it was written (no escaping, no newline added). The order is the number: an ask only first, a question
-- after an ask or an answer, an answer after a question, no gap and no repeat; any other name in the folder is an
-- error, never skipped. The dispatcher also keeps a seal of what it wrote (the sha256 of each file, in state.json),
-- so a step that rewrote the record is noticed.
local serde = require("@lune/serde")

local exchange = {}

export type Kind = "ask" | "question" | "answer"
export type Entry = { n: number, kind: Kind, date: string, step: string?, body: string }

exchange.DIR = "exchange"
exchange.MAX = 999
exchange.LIMIT = 65536 -- the most bytes of one answer
exchange.NO_REPLY = "(no reply: the user ran retry without an answer)"
exchange.WITHDRAWN = "(no reply: questions.md was removed without an answer)"
exchange.UNKNOWN_REPLY =
	"(the question was copied when the user retried, so any answer they wrote is inside it)"

-- the kind a word names (a plain function, so the type checker sees a Kind and not a string)
local function kindOf(word: string): Kind?
	if word == "ask" then
		return "ask"
	elseif word == "question" then
		return "question"
	elseif word == "answer" then
		return "answer"
	end
	return nil
end

type Named = { n: number, kind: Kind }

-- Kind comparison through a function: the checker widens a refined union after an earlier branch of a chain
local function same(a: Kind?, b: Kind): boolean
	return a == b
end

local function named(name: string): Named?
	local num, word = string.match(name, "^(%d%d%d)%-([a-z]+)%.md$")
	if num == nil or word == nil then
		return nil
	end
	local kind: Kind? = kindOf(word :: string)
	if kind == nil then
		return nil
	end
	return { n = tonumber(num :: string) :: number, kind = kind :: Kind }
end

function exchange.name(n: number, kind: Kind): string
	return string.format("%03d-%s.md", n, kind)
end

-- The number and kind a file name says, or nil.
function exchange.parseName(name: string): (number?, Kind?)
	local got = named(name)
	if got == nil then
		return nil, nil
	end
	return got.n, got.kind
end

-- `step` is the step that asked, for a question only.
function exchange.render(date: string, body: string, step: string?): string
	return `date: {date}\n{if step then `step: {step}\n` else ""}\n{body}`
end

-- The entry a file holds, or nil and why.
function exchange.parse(name: string, text: string): (Entry?, string?)
	local got = named(name)
	if got == nil then
		return nil, `{name} is not an exchange file (NNN-ask|question|answer.md)`
	end
	local date, rest = string.match(text, "^date: (%d%d%d%d%-%d%d%-%d%dT%d%d:%d%d:%d%dZ)\n(.*)$")
	if date == nil or rest == nil then
		return nil, `{name} does not start with "date: <UTC time>"`
	end
	if same(got.kind, "question") then
		local step, body = string.match(rest :: string, "^step: ([a-z][a-z0-9%-]*)\n\n(.*)$")
		if step == nil or body == nil then
			return nil,
				`{name} is a question and must say "step: <the step that asked>" and then a blank line`
		end
		return {
			n = got.n,
			kind = got.kind,
			date = date :: string,
			step = step :: string,
			body = body :: string,
		},
			nil
	end
	local body = string.match(rest :: string, "^\n(.*)$")
	if body == nil then
		return nil, `{name} must have a blank line after its date line (only a question has a step line)`
	end
	return { n = got.n, kind = got.kind, date = date :: string, step = nil, body = body :: string }, nil
end

-- The names in order, or nil and why: every name is an exchange file, numbered 1, 2, 3 without a gap or a repeat, and
-- the kinds alternate as the header says. Names that start with a dot (a file being written) are not part of it.
function exchange.order(names: { string }): ({ string }?, string?)
	local byN: { [number]: string } = {}
	local kinds: { [number]: Kind } = {}
	local top = 0
	for _, name in names do
		if string.sub(name, 1, 1) ~= "." then
			local got = named(name)
			if got == nil then
				return nil, `{name} is not an exchange file (NNN-ask|question|answer.md)`
			end
			if byN[got.n] ~= nil then
				return nil, `{name} repeats number {got.n} ({byN[got.n]})`
			end
			byN[got.n], kinds[got.n] = name, got.kind
			top = math.max(top, got.n)
		end
	end
	local out: { string } = {}
	local before: Kind? = nil
	for n = 1, top do
		local name = byN[n]
		local kind: Kind = kinds[n] :: any
		if name == nil then
			return nil, `the exchange has no file number {n} (it has {top})`
		end
		if same(kind, "ask") and n ~= 1 then
			return nil, `{name}: an ask can only be the first message`
		elseif same(kind, "question") and same(before, "question") then
			return nil, `{name}: a question cannot follow a question`
		elseif same(kind, "answer") and not same(before, "question") then
			return nil, `{name}: an answer must follow a question`
		end
		before = kind
		table.insert(out, name)
	end
	return out, nil
end

-- The number of the next file for `kind`, or nil and why that kind may not follow.
function exchange.next(names: { string }, kind: Kind): (number?, string?)
	local ordered, why = exchange.order(names)
	if ordered == nil then
		return nil, why
	end
	local n = #ordered + 1
	if n > exchange.MAX then
		return nil, `the exchange is full ({exchange.MAX} messages)`
	end
	local lastNamed = named(ordered[#ordered] or "")
	local last: Kind? = if lastNamed then lastNamed.kind else nil
	if same(kind, "ask") and n ~= 1 then
		return nil, "an ask can only be the first message"
	elseif same(kind, "question") and same(last, "question") then
		return nil, "a question cannot follow a question"
	elseif same(kind, "answer") and not same(last, "question") then
		return nil, "an answer must follow a question"
	end
	return n, nil
end

-- What the dispatcher wrote: the sha256 of each file's text, by name.
function exchange.seal(texts: { [string]: string }): { [string]: string }
	local out: { [string]: string } = {}
	for name, text in texts do
		out[name] = serde.hash("sha256", text)
	end
	return out
end

-- The first difference between the seal and the files as they are now ("added X", "changed X", "removed X"), or nil.
-- No seal means nothing was written, so any file is an addition.
function exchange.changed(sealed: { [string]: string }?, texts: { [string]: string }): string?
	local seal: { [string]: string } = sealed or {}
	local now = exchange.seal(texts)
	local names: { string } = {}
	for name in now do
		table.insert(names, name)
	end
	for name in seal do
		if now[name] == nil then
			table.insert(names, name)
		end
	end
	table.sort(names)
	for _, name in names do
		if seal[name] == nil then
			return `added {name}`
		elseif now[name] == nil then
			return `removed {name}`
		elseif now[name] ~= seal[name] then
			return `changed {name}`
		end
	end
	return nil
end

-- Why a message (`what`: "the answer", "the question") is refused (blank, too large, binary), or nil.
function exchange.answerRefusal(text: string, what: string?): string?
	local name = what or "the answer"
	if string.find(text, "^%s*$") then
		return `{name} is empty`
	elseif #text > exchange.LIMIT then
		return `{name} is {#text} bytes; the most is {exchange.LIMIT}`
	elseif string.find(text, "\0", 1, true) then
		return `{name} holds a NUL byte (a binary file?)`
	end
	return nil
end

-- A text compared as an editor leaves it: line ends and trailing whitespace do not count.
function exchange.normal(text: string): string
	local lf = string.gsub(text, "\r\n", "\n")
	local lines = string.gsub(lf, "[ \t]+\n", "\n")
	return (string.gsub(lines, "%s+$", ""))
end

return exchange
