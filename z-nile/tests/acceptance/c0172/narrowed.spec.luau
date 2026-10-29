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
		"3f845366862fa5466ad7e944cc88f64fe2daac41914d6ece981a1d4fc5e46783",
	},
	{
		"z-nile",
		"c0114",
		"gate-cover.spec.luau",
		"16ca93e1df7a5f138a04eda4cbd31c1f755c15df2cf66f3058fcd3e0fc1f11ef",
	},
	{
		"z-nile",
		"c0114",
		"layout.spec.luau",
		"455f35da75608dbc6818cd2ffc96f5a79e97c3fa5fef2c491aefaede866818d7",
	},
	{ "z-nile", "c0120", "ci.spec.luau", "d67676e90d2a6f23f7ca77ae225f168f11f5f8b5b5223c92f148457c865b5565" },
	{
		"z-nile",
		"c0120",
		"docs.spec.luau",
		"ed6221c0c4d2f6f5d815ad93361e0f2c163d9165847c6b0f807ca53e993242c1",
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
		"62e46f54027dab1ec70866abfb4fe21e4f5878ee1fc2ff119d83f93950b2509b",
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
