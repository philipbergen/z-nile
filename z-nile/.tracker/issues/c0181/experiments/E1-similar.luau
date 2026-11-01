--!strict
-- c0181 E1: how many lessons overlap? Scores every same-skill and cross-skill pair of lesson files with the rule the
-- Design pins (consolidate.similar): score = 0.65 * J(words of title + check) + 0.35 * J(tags), J = Jaccard over the
-- sets. Pure over the files; reads only. Run from the repository root:
--   perl -e 'alarm shift; exec @ARGV' 60 lune run z-nile/.tracker/issues/c0181/experiments/E1-similar .
local fs = require("@lune/fs")
local process = require("@lune/process")

local root = process.args[1] or "."
local STOP: { [string]: boolean } = {}
for w in
	string.gmatch(
		"the and for are but not you all can had her was one our out has have this that with from into than then does each every any its when what which who how would could should these those they them their there been being were also only same such both between through during before after above below until while about against over under again more most other some very just into onto its",
		"%a+"
	)
do
	STOP[w] = true
end

type Lesson = { id: string, words: { [string]: boolean }, tags: { [string]: boolean } }

local function words(s: string): { [string]: boolean }
	local out: { [string]: boolean } = {}
	for w in string.gmatch(string.lower(s), "[a-z][a-z0-9%-]*") do
		if #w >= 3 and not STOP[w] then
			out[w] = true
		end
	end
	return out
end

local function jaccard(a: { [string]: boolean }, b: { [string]: boolean }): number
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

local all: { Lesson } = {}
for _, base in { "z-nile/skills", "pickman/skills" } do
	for _, skill in fs.readDir(`{root}/{base}`) do
		local dir = `{root}/{base}/{skill}/lessons`
		if fs.isDir(dir) then
			for _, f in fs.readDir(dir) do
				if string.sub(f, -3) == ".md" then
					local text = fs.readFile(`{dir}/{f}`)
					local title = string.match(text, "\ntitle:%s*([^\n]*)") or ""
					local check = string.match(text, "\ncheck:%s*([^\n]*)") or ""
					local tags: { [string]: boolean } = {}
					for tag in string.gmatch(string.match(text, "\ntags:%s*%[([^\n]*)%]") or "", "[^,%s]+") do
						tags[tag] = true
					end
					table.insert(all, {
						id = `{skill}/{string.sub(f, 1, -4)}`,
						words = words(title .. " " .. check),
						tags = tags,
					})
				end
			end
		end
	end
end

local scored: { { jw: number, jt: number, score: number, a: string, b: string, same: boolean } } = {}
for i = 1, #all do
	for j = i + 1, #all do
		local a, b = all[i], all[j]
		local score = 0.65 * jaccard(a.words, b.words) + 0.35 * jaccard(a.tags, b.tags)
		table.insert(scored, {
			jw = jaccard(a.words, b.words),
			jt = jaccard(a.tags, b.tags),
			score = score,
			a = a.id,
			b = b.id,
			same = string.match(a.id, "^[^/]+") == string.match(b.id, "^[^/]+"),
		})
	end
end
table.sort(scored, function(x, y)
	return x.score > y.score
end)
local hard, soft = 0, 0
for _, s in scored do
	if s.same and s.score >= 0.40 then
		hard += 1
	end
	if s.same and s.score >= 0.20 then
		soft += 1
	end
end
print(`lessons {#all}, pairs {#scored}; same-skill pairs >= 0.40: {hard}, >= 0.20: {soft}`)
for k = 1, 14 do
	local s = scored[k]
	print(
		string.format(
			"%.2f (words %.2f, tags %.2f) %s %s <> %s",
			s.score,
			s.jw,
			s.jt,
			if s.same then "same " else "cross",
			s.a,
			s.b
		)
	)
end
