--!strict
-- c0251: which model line reviews, away from the one that wrote the text. Pure: a role's tries, the family table, the
-- text's writers and the previous round's reviewers in, the tries in the order to run them out. Whether a CLI is
-- installed or out of quota stays the dispatcher's loop.
--
-- Three tiers over the tries (a stable partition, the role's order inside each):
--   1  the model line differs from every writer and from the previous round's reviewers
--   2  it differs from the writers only (the previous round's line, or a line the table does not name)
--   3  it is the writers' line: the flagged fallback, the writer's exact model last
-- A review never blocks: a tier 3 try is kept, last. An unknown family is never "different": it is tier 2 when a writer's
-- line is known, tier 1 when no writer's line is (there is nothing to differ from, and no flag).
local family = require("./family")
local models = require("./models")

local reviewpool = {}

export type Tier = number -- 1, 2 or 3
export type Pick = { spec: models.Spec, tier: Tier, exact: boolean, family: string? }
export type Plan = {
	picks: { Pick },
	authors: { string }, -- bare model ids of the writers
	authorFamilies: { string },
	priors: { string }, -- bare model ids of the previous round's reviewers
	priorFamilies: { string },
	provenance: string, -- authorship.Provenance, or "none" when the role does not rotate
	via: string, -- where the writers came from (authorship.Authorship.via)
	families: family.Families,
	rotate: boolean,
	walk: string?, -- "main" (the pinned walk) or "checkout" (the working tree's .models.toml files)
}

local function bare(id: string): string
	return (string.gsub(id, "%[[^%[%]]*%]$", ""))
end

local function familiesOf(ids: { string }, f: family.Families): { string }
	local out: { string } = {}
	for _, id in ids do
		local fam = family.of(id, f)
		if fam ~= nil and not table.find(out, fam) then
			table.insert(out, fam)
		end
	end
	return out
end

-- The tries in tier order, each with its tier. `authors` and `priors` are model ids (a context marker is ignored).
function reviewpool.order(
	tries: { models.Spec },
	families: family.Families,
	authors: { string },
	priors: { string }
): { Pick }
	local authorIds: { string } = {}
	for _, a in authors do
		table.insert(authorIds, bare(a))
	end
	local authorFams = familiesOf(authors, families)
	local priorFams = familiesOf(priors, families)
	local groups: { { Pick } } = { {}, {}, {}, {} } -- tier 1, tier 2, tier 3 (not exact), tier 3 exact
	for _, spec in tries do
		local fam = family.of(spec.model, families)
		local exact = table.find(authorIds, bare(spec.model)) ~= nil
		local tier: Tier = 1
		if exact or (fam ~= nil and table.find(authorFams, fam) ~= nil) then
			tier = 3
		elseif (#authorFams > 0 and fam == nil) or (fam ~= nil and table.find(priorFams, fam) ~= nil) then
			tier = 2
		else
			tier = 1
		end
		local group = if tier == 3 and exact then 4 else tier
		table.insert(groups[group], { spec = spec, tier = tier, exact = exact, family = fam })
	end
	local out: { Pick } = {}
	for _, group in groups do
		for _, pick in group do
			table.insert(out, pick)
		end
	end
	return out
end

local function cut(text: string): string
	return if #text > 120 then string.sub(text, 1, 117) .. "..." else text
end

-- Why a tier 3 pick is a fallback, in one short line for the `Fallback:` stamp; nil for any other tier. `provenance` and
-- `via` say how sure the tool is of the writer: when it only assumed or did not know, the reason says so.
function reviewpool.fallbackReason(p: Pick, provenance: string, via: string): string?
	if p.tier ~= 3 then
		return nil
	end
	local model = bare(p.spec.model)
	local what = if p.exact
		then `the model that wrote the text ran the review ({model})`
		else `the writer's model line ({p.family or "?"}) ran the review ({model})`
	if provenance == "assumed" or provenance == "unknown" then
		what ..= `; author {provenance} via {via}`
	end
	return cut(what)
end

-- Whether an interactive review on `ran` (the model id the lead typed) is a fallback: it is the writers' line, or the
-- pool's first pick was not a Claude model and a different one ran (the lead stayed on a Claude subagent). nil when not.
function reviewpool.interactiveReason(plan: Plan, ran: string): string?
	local model = bare(ran)
	local fam = family.of(model, plan.families)
	local walked = if plan.walk == "checkout" then "; plan from the checkout's .models.toml" else ""
	local exact = table.find(plan.authors, model) ~= nil
	if exact or (fam ~= nil and table.find(plan.authorFamilies, fam) ~= nil) then
		local what = if exact
			then `the model that wrote the text ran the review ({model})`
			else `the writer's model line ({fam or "?"}) ran the review ({model})`
		if plan.provenance == "assumed" or plan.provenance == "unknown" then
			what ..= `; author {plan.provenance} via {plan.via}`
		end
		return cut(what .. walked)
	end
	local first = plan.picks[1]
	if first ~= nil then
		local pick = bare(first.spec.model)
		if string.sub(pick, 1, 7) ~= "claude-" and pick ~= model then
			return cut(`the pool picked {pick}; {model} ran the review instead{walked}`)
		end
	end
	return nil
end

return reviewpool
