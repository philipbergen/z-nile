--!strict
-- c0181 E4: do the scores consolidate.spec expects for its planted lessons follow from the rule the Design pins?
-- Same formula as E1, over the six planted lessons; prints each pair's score in hundredths. Pure; reads nothing.
--   lune run z-nile/.tracker/issues/c0181/experiments/E4-planted-scores
local STOP: { [string]: boolean } = {}
for w in
	string.gmatch(
		"the and for are but not you all can had her was one our out has have this that with from into than then does each every any its when what which who how would could should these those they them their there been being were also only same such both between through during before after above below until while about against over under again more most other some very just onto",
		"%a+"
	)
do
	STOP[w] = true
end

type Set = { [string]: boolean }
local function words(s: string): Set
	local out: Set = {}
	for w in string.gmatch(string.lower(s), "[a-z][a-z0-9%-]*") do
		if #w >= 3 and not STOP[w] then
			out[w] = true
		end
	end
	return out
end
local function tags(s: string): Set
	local out: Set = {}
	for tag in string.gmatch(s, "[^,%s]+") do
		out[tag] = true
	end
	return out
end
local function jaccard(a: Set, b: Set): number
	local inter, union = 0, 0
	for w in a do
		if b[w] then
			inter += 1
		end
		union += 1
	end
	for w in b do
		if not a[w] then
			union += 1
		end
	end
	return if union == 0 then 0 else inter / union
end
local function similar(a: { text: string, tags: string }, b: { text: string, tags: string }): number
	local raw = 0.65 * jaccard(words(a.text), words(b.text)) + 0.35 * jaccard(tags(a.tags), tags(b.tags))
	return math.floor(raw * 100 + 0.5) / 100
end

local A = { text = "alpha beta Gamma delta epsilon zeta?", tags = "x, y" }
local cases = {
	{
		"same (stop words differ)",
		{ text = "the alpha beta Does this gamma delta epsilon zeta?", tags = "x, y" },
		1,
	},
	{ "tags only", { text = "kappa lambda Mu nu xi omicron?", tags = "x, y" }, 0.35 },
	{ "two of three tags", { text = "kappa lambda Mu nu xi omicron?", tags = "x, y, z" }, 0.23 },
	{ "words only", { text = "alpha beta Gamma delta epsilon zeta?", tags = "p" }, 0.65 },
	{ "far", { text = "pi rho Sigma tau?", tags = "q" }, 0 },
}
local bad = 0
for _, c in cases do
	local got = similar(A, c[2] :: any)
	print(
		string.format(
			"%-28s %.2f (expected %.2f)%s",
			c[1] :: string,
			got,
			c[3] :: number,
			if got == c[3] then "" else "  MISMATCH"
		)
	)
	if got ~= c[3] then
		bad += 1
	end
end
print(if bad == 0 then "all planted scores agree" else `{bad} disagree`)
