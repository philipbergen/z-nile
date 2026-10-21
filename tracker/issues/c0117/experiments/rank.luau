--!strict
-- E1 prototype: a closer .models.toml replaces max_tokens and keeps model and rank.
-- Not the implementation. The acceptance spec pins scripts/tracker/models.luau. This file is a sketch of the merge rule, not a toml parser.

type Spec = { model: string, rank: number, runtime: string, maxTokens: number }

local function apply(base: Spec, over: { [string]: string }): Spec
	local out: Spec = {
		model = base.model,
		rank = base.rank,
		runtime = base.runtime,
		maxTokens = base.maxTokens,
	}
	if over.model then
		out.model = over.model
	end
	if over.rank then
		out.rank = tonumber(over.rank) :: number
	end
	if over.runtime then
		out.runtime = over.runtime
	end
	if over.max_tokens then
		out.maxTokens = tonumber(over.max_tokens) :: number
	end
	return out
end

local got = apply(
	{ model = "grok-4.7", rank = 2, runtime = "grok-cli", maxTokens = 300000 },
	{ max_tokens = "1000" }
)
if got.model ~= "grok-4.7" or got.rank ~= 2 or got.maxTokens ~= 1000 then
	error(`closer key did not keep the rest: {got.model} {got.rank} {got.maxTokens}`)
end
print("pass")
