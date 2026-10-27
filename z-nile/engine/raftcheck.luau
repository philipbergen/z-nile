--!strict
-- A raft's check.sh as the rafting gate judges it (R0052 code review 003 F2): pure, over texts. A new raft's exit
-- criteria are the rendered template's RC0 lines byte for byte (the project gate, every member's check.sh,
-- promote-check), then only RCn checks and the template's `finish`. `check` (z-nile/lib/ac.sh) runs its command in a
-- subshell, so an appended check can neither exit the script nor change its counts; what could (a bare `exit`, `;`,
-- `&&`, a redirect, a function, `$(`, `${`) is refused, and that raft waits for a human.

local raftcheck = {}

-- The one renderer of the tracker's templates (`./zn new raft`, `./zn new issue`, and this gate): `{{NAME}}` replaced
-- by `vars[NAME]`, an unknown name left as it is.
function raftcheck.render(text: string, vars: { [string]: string }): string
	return (
		string.gsub(text, "{{([%w_]+)}}", function(k: string): string
			return vars[k] or "{{" .. k .. "}}"
		end)
	)
end

-- The rendered template's head: every line through its last `check "RC0` line (and that line's newline).
function raftcheck.head(rendered: string): string?
	local last: number? = nil
	local at = 1
	while true do
		local s, e = string.find(rendered, '\ncheck "RC0', at, true)
		if not s then
			break
		end
		local nl = string.find(rendered, "\n", (e :: number) + 1, true)
		last = if nl then nl else #rendered
		at = (e :: number) + 1
	end
	return if last then string.sub(rendered, 1, last :: number) else nil
end

local BARE = "^[%w%-%._/=:@+,%%]$"

-- One word of a `check` line from `i`: a single-quoted string (literal, any lines), a double-quoted string or a bare
-- word (a `$NAME` expansion allowed, never `$(`, `${` or a backquote). Returns the index after it, or nil and why.
local function word(text: string, i: number): (number?, string?)
	local c = string.sub(text, i, i)
	if c == "'" then
		local close = string.find(text, "'", i + 1, true)
		if not close then
			return nil, "an unterminated single quote"
		end
		return close + 1, nil
	end
	local quoted = c == '"'
	local j = if quoted then i + 1 else i
	while j <= #text do
		local ch = string.sub(text, j, j)
		if quoted and ch == '"' then
			return j + 1, nil
		end
		if not quoted and (ch == " " or ch == "\t" or ch == "\n" or ch == "\\") then
			return j, nil
		end
		if ch == "`" or ch == "\\" then
			return nil, `{ch} in a check's words`
		end
		if ch == "$" then
			local nxt = string.sub(text, j + 1, j + 1)
			if not string.match(nxt, "^[%a_]$") then
				return nil, `\${nxt} in a check's words (only a plain $NAME)`
			end
		elseif not quoted and not string.match(ch, BARE) and ch ~= "$" and ch ~= "'" then
			return nil, `{ch} outside quotes in a check's words`
		end
		if not quoted and ch == "'" then
			return nil, "a quote inside a bare word"
		end
		j += 1
	end
	if quoted then
		return nil, "an unterminated double quote"
	end
	return j, nil
end

-- Why `text` is not a new raft's check.sh as the gate accepts it, or nil. `rendered` is the template rendered for the
-- raft's id and project.
function raftcheck.judge(text: string, rendered: string): string?
	local head = raftcheck.head(rendered)
	if not head then
		return "the raft template has no RC0 lines"
	end
	if string.sub(text, 1, #head) ~= head then
		return "its RC0 lines are not the raft template's, byte for byte"
	end
	local i = #head + 1
	local finished = false
	while i <= #text do
		local c = string.sub(text, i, i)
		if c == " " or c == "\t" or c == "\n" then
			i += 1
		elseif c == "#" then
			local nl = string.find(text, "\n", i, true)
			i = if nl then nl + 1 else #text + 1
		elseif finished then
			return "something follows its finish"
		elseif string.match(text, "^finish[ \t]*\n", i) or string.match(text, "^finish[ \t]*$", i) then
			finished = true
			i += 6
		elseif string.match(text, '^check "RC[1-9]%d*: ', i) then
			-- the label, then at least one word, up to an unquoted, unescaped end of line
			local after, why = word(text, i + 6)
			if not after then
				return why
			end
			local words = 0
			local j = after :: number
			while j <= #text do
				local ch = string.sub(text, j, j)
				if ch == "\n" then
					break
				elseif ch == " " or ch == "\t" then
					j += 1
				elseif ch == "\\" and string.sub(text, j + 1, j + 1) == "\n" then
					j += 2
				else
					local nxt, err = word(text, j)
					if not nxt then
						return err
					end
					words += 1
					j = nxt :: number
				end
			end
			if words == 0 then
				return "an RC check with no command"
			end
			i = j
		else
			local line = string.match(text, "^[^\n]*", i) or ""
			return `after the RC0 lines only RCn checks and finish: {line}`
		end
	end
	if not finished then
		return "it does not end with the template's finish"
	end
	return nil
end

return raftcheck
