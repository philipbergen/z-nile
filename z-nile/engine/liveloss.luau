--!strict
-- f0420 step 4c: a worker whose claim expired (it was silent) or ended is told, in plain words, when it runs a zn command
-- again. The daemon keeps the marker (a Loss); this module only turns it into the notice, the answer of `./zn work next`
-- and the carrier rows an expiry frees. Pure: it reads nothing and starts nothing.
local liveview = require("./liveview")

local liveloss = {}

export type Loss = {
	worker: string,
	unit: string,
	activity: string,
	at: number,
	since: number?,
	reason: string?,
	holder: string?, -- who holds the unit now
	session: string?, -- the lost worker's session, which names its carrier rows
	told: boolean?,
}

-- The losses of a daemon reply (`losses` of beat, register or the losses op), checked field by field.
function liveloss.parse(raw: any): { Loss }
	local out: { Loss } = {}
	if type(raw) ~= "table" then
		return out
	end
	for _, l in raw :: { any } do
		if
			type(l) == "table"
			and type(l.unit) == "string"
			and type(l.worker) == "string"
			and type(l.at) == "number"
		then
			table.insert(out, {
				worker = l.worker,
				unit = l.unit,
				activity = if type(l.activity) == "string" then l.activity else "",
				at = l.at,
				since = if type(l.since) == "number" then l.since else nil,
				reason = if type(l.reason) == "string" then l.reason else nil,
				holder = if type(l.holder) == "string" and l.holder ~= "" then l.holder else nil,
				session = if type(l.session) == "string" and l.session ~= "" then l.session else nil,
				told = l.noticed_at ~= nil and l.noticed_at ~= 0,
			})
		end
	end
	return out
end

-- One loss as a notice: which unit and activity, when, who holds it now, and what to do.
function liveloss.notice(l: Loss, now: number?): string
	local who = if l.holder then `{l.holder} holds it now` else "nobody holds it now"
	local why = if l.reason then ` ({l.reason})` else ""
	return `LOST CLAIM: {l.worker} lost {l.unit} ({l.activity}) at {liveview.pacific(l.at, now)}{why}; {who}. Stop work on {l.unit}, do not push its branch for it, and run ./zn work next.`
end

-- `./zn work next` for a worker that has losses it was not told of: the loss is the answer, nothing is claimed.
function liveloss.answer(
	losses: { Loss },
	now: number?
): { raft: string, layer: string, ticket: string, action: string, why: string }
	local lines: { string } = {}
	for _, l in losses do
		table.insert(lines, liveloss.notice(l, now))
	end
	return { raft = "", layer = "", ticket = "", action = "wait", why = table.concat(lines, "\n") }
end

-- The carrier rows (item -> { session, age }) without the ones the lost workers' sessions hold on their lost units, so the
-- walk of the next worker resumes that unit at once. The input is not changed; the file is not touched.
function liveloss.freeCarriers(
	carriers: { [string]: { session: string, age: number } },
	losses: { Loss }
): { [string]: { session: string, age: number } }
	local out = table.clone(carriers)
	for _, l in losses do
		local row = out[l.unit]
		if row ~= nil and l.session ~= nil and row.session == l.session then
			out[l.unit] = nil
		end
	end
	return out
end

return liveloss
