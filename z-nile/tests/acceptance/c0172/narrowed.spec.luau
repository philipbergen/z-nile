--!strict
-- c0172 AC3: each promoted spec this issue narrows is pinned whole. The digest is SHA-256 of the exact text
-- with item ids masked and CRLF made LF. No other whitespace is tolerated: a newline ends a line comment, and
-- spaces inside a string are part of what a string.find asserts.
local fs = require("@lune/fs")
local process = require("@lune/process")
local renamed = require("@tests/lib/renamed")
local serde = require("@lune/serde")
local t = require("@tests/lib/t")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

local function exact(rel: string): string
	local text = string.gsub(fs.readFile(`{TOP}/{rel}`), "\r\n", "\n")
	text = string.gsub(text, "%f[%w_][fdcR]%d+%f[^%w_]", "ID")
	return text
end

-- project, the item id the file was filed under, the file name, the digest of the narrowed text
local PINNED = {
	{
		"z-nile",
		"c0001",
		"ci-workflow.spec.luau",
		"623dc492a354457644dc074f59e01a9c8d03c11e685120054fa0ab16d1b79666",
	},
	{
		"z-nile",
		"c0048",
		"board-docs.spec.luau",
		"bf36490d668bce63cf9996961582cb87c77da8437762d059f2bece0d27655251",
	},
	{
		"z-nile",
		"c0048",
		"board-workflow.spec.luau",
		"ba99d371d772d32d1b9afc6ddebe47c0f5ade8c7535bb372e96a41fb5113c181",
	},
	{
		"z-nile",
		"c0057",
		"open.spec.luau",
		"5cb202e2b16fbdfb63585208c596caa82883952726c70fc883c67275639f1db3",
	},
	{
		"z-nile",
		"c0058",
		"fence.spec.luau",
		"9be55ce26f03978bf0fe475497317c7204ea8eb2048cdd810eb58c24dab66465",
	},
	{
		"z-nile",
		"c0073",
		"board-stats.spec.luau",
		"3b9025758da801a150aeb69f440372731a1b6930956992cd0d8ffad11d9c57fc",
	},
	{
		"z-nile",
		"c0107",
		"keep.spec.luau",
		"9711d49620ba326c5c850f955eef8463704cf6409d214eae13162fec0f9a8972",
	},
	{
		"z-nile",
		"c0114",
		"gate-cover.spec.luau",
		"d50ac08c74e5d094a718c26addee52bd9afc7152938fd34a279a45f197028982",
	},
	{
		"z-nile",
		"c0114",
		"layout.spec.luau",
		"455f35da75608dbc6818cd2ffc96f5a79e97c3fa5fef2c491aefaede866818d7",
	},
	{ "z-nile", "c0120", "ci.spec.luau", "1711d589ef60d2776edacb0a097a5acc02e7baa192a2afc9f7ae2361b5fb0015" },
	{
		"z-nile",
		"c0120",
		"docs.spec.luau",
		"b7292c462c91fcb3273c73defa54c1e03687cf3c722e67d8d6890eb51ed36fa4",
	},
	{
		"pickman",
		"c0003",
		"pipeline.spec.luau",
		"9cd8f9c28e2beb6312e06c9d85469cc1afa7272e33e4c86dfbfde3caf9736e76",
	},
	{
		"pickman",
		"c0015",
		"docs.spec.luau",
		"7a1c3047d499dccf4b80603e136691012e15422531940cb97216a4c79f04a225",
	},
	{
		"pickman",
		"c0015",
		"workflow.spec.luau",
		"8107ba9fb712fad54191c941a1842833082f90e83684858f11a9b463b176fc8f",
	},
	{
		"pickman",
		"c0064",
		"workflow.spec.luau",
		"866a9a28c2a6e8d44a9761551a5925ef6c8f1505433444ed9203b74e58133144",
	},
}

return t.spec("c0172 narrowed specs pinned whole", function(it)
	it("each narrowed spec is exactly the narrowed text", function()
		for _, row in PINNED do
			local rel = `{row[1]}/tests/acceptance/{renamed.id(row[2])}/{row[3]}`
			t.expect(fs.isFile(`{TOP}/{rel}`)).toBe(true)
			t.expect(serde.hash("sha256", exact(rel))).toBe(row[4])
		end
	end)
end)
