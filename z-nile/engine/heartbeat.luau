--!strict
-- The part of c0265's work heartbeat (R0100/3/c0275 e417120b7, `engine/heartbeat.luau`) that the dispatcher's claimBeat
-- needs (c0275): the interval, the spec-run setting, the due test, the stamp and the outcome of its beat child. The prototype
-- copies only these six; c0265 owns the whole file (verdicts, takeover, the branch reads).
local heartbeat = {}

heartbeat.INTERVAL = 300
heartbeat.SKEW = 300

-- A tuning setting (ZN_BEAT_EVERY, ZN_NET_SECONDS): honoured only inside a spec run, and only a positive whole number.
function heartbeat.setting(
	env: { [string]: string? },
	name: string,
	default: number,
	specRun: boolean
): number
	local raw = env[name]
	local n = if raw ~= nil then tonumber(raw) else nil
	if specRun and n ~= nil and n >= 1 and n == math.floor(n) then
		return n
	end
	return default
end

-- Whether a beat is due: never made, a full `every` old, or dated past the skew allowance (a clock that went back).
function heartbeat.due(last: number?, now: number, every: number): boolean
	return last == nil or now - last >= every or last > now + heartbeat.SKEW
end

-- The dispatcher's stamp for a step's item: the claim its step worktree remembers (a step that made its own claim), else
-- the stamp main showed when the step started.
function heartbeat.dispatchStamp(started: string?, remembered: string?): string?
	if remembered ~= nil and remembered ~= "" then
		return remembered
	end
	return started
end

-- What the dispatcher does with the answer of its `zn beat <id> --adopt --stamp <S>` child: "beat" (landed), "lost" (the
-- claim was taken over or ended mid-step: stop beating and say so once), "none" (no claim yet: the step has not made its
-- own: ignored) or "failed" (written once per step to the run's stderr).
function heartbeat.dispatchOutcome(ok: boolean, stderr: string): string
	if ok then
		return "beat"
	elseif
		string.find(stderr, "claim was taken over", 1, true) or string.find(stderr, "claim ended", 1, true)
	then
		return "lost"
	elseif string.find(stderr, "no claim to beat", 1, true) then
		return "none"
	end
	return "failed"
end

-- The claim stamp in a document's status field, nil for anything that is not a live claim (preparing-… or active-…).
function heartbeat.stampIn(status: string?): string?
	local kind = if status then string.match(status, "^(%a+)%-%a+%-%a+%-%a+$") else nil
	return if kind == "preparing" or kind == "active" then status else nil
end

-- Whom a claim stamp belongs to (copied verbatim from R0100/5/c0277 acf480f21, `heartbeat.holds`; c0254 reads it for the push
-- rule): "held" (the same), "unheld" (this checkout remembers none), "taken" (origin shows another stamp), "ended" (origin shows
-- no claim).
function heartbeat.holds(remembered: string?, originStamp: string?): string
	if remembered == nil or remembered == "" then
		return "unheld"
	elseif originStamp == nil then
		return "ended"
	elseif originStamp == remembered then
		return "held"
	end
	return "taken"
end

return heartbeat
