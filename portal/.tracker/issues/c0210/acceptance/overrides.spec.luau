--!strict
-- c0210 AC12 (design review 001 F1): the promoted specs this chore rewrites are exactly the reviewed text, and every
-- other file of the promoted folders it touches is exactly as reviewed. Each overridden spec equals its golden
-- (override-<n>.txt beside this spec, the prototype's text after the design review), every other file its digest
-- here, and no file is added to or removed from those folders; watch files aside (`./zn commit` rewrites them). Texts
-- are masked as c0172's narrowed.spec masks them: item ids become ID and CRLF becomes LF. The executor recomputes
-- nothing: a byte beyond the reviewed text is an escalation.
local fs = require("@lune/fs")
local process = require("@lune/process")
local renamed = require("@tests/lib/renamed")
local serde = require("@lune/serde")
local t = require("@tests/lib/t")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
-- this spec's own folder (its issue folder's acceptance/ before done, tests/acceptance/<id>/ after)
local HERE = string.match(string.gsub(debug.info(1, "s"), "^@", ""), "^(.*)/[^/]+$") or "."

local function exact(text: string): string
	local out = string.gsub(text, "\r\n", "\n")
	out = string.gsub(out, "%f[%w_][fdcR]%d+%f[^%w_]", "ID")
	return out
end

local function rel(home: string, item: string, name: string): string
	return `{home}/tests/acceptance/{renamed.id(item)}/{name}`
end

-- home, item, file, golden
local GOLDEN = {
	{ "pickman", "c0003", "runner.spec.luau", "01.txt" },
	{ "pickman", "c0003", "runner-e2e.spec.luau", "02.txt" },
	{ "pickman", "c0015", "deploy-cli.spec.luau", "03.txt" },
	{ "pickman", "c0015", "deploy-e2e.spec.luau", "04.txt" },
	{ "pickman", "c0015", "workflow.spec.luau", "05.txt" },
	{ "pickman", "c0064", "plan.spec.luau", "06.txt" },
	{ "pickman", "c0064", "deploy.spec.luau", "07.txt" },
	{ "pickman", "c0064", "runtime.spec.luau", "08.txt" },
	{ "pickman", "c0064", "docs.spec.luau", "09.txt" },
	{ "pickman", "c0064", "workflow.spec.luau", "10.txt" },
	{ "z-nile", "c0120", "ci.spec.luau", "11.txt" },
	{ "z-nile", "c0120", "layout.spec.luau", "12.txt" },
	{ "z-nile", "c0120", "docs.spec.luau", "13.txt" },
	{ "z-nile", "c0172", "cicd.spec.luau", "14.txt" },
	{ "z-nile", "c0172", "merge.spec.luau", "15.txt" },
	{ "z-nile", "c0172", "narrowed.spec.luau", "16.txt" },
	{ "z-nile", "c0194", "callers.spec.luau", "17.txt" },
}

-- home, item, file, SHA-256 of the masked text
local UNCHANGED = {
	{
		"pickman",
		"c0003",
		"execute.spec.luau",
		"82334073f6b49c98e8f24119f1f5a5c5b114215fe5703e94a19a3081804a2ab0",
	},
	{
		"pickman",
		"c0003",
		"pipeline.spec.luau",
		"9cd8f9c28e2beb6312e06c9d85469cc1afa7272e33e4c86dfbfde3caf9736e76",
	},
	{
		"pickman",
		"c0003",
		"scripts.spec.luau",
		"1f366829ef8f6a672b8017d84a7acb0962741e5abb152a9167deabec8d694c12",
	},
	{
		"pickman",
		"c0003",
		"suite.spec.luau",
		"937e7093fa06b276cea6c13b1568e4385540eee09c91e6c7917712fc77d82bd2",
	},
	{
		"pickman",
		"c0015",
		"config.spec.luau",
		"2e03b758c8e0d724fa071ae792fd83a6bdcdefbe539b4180757ac8accfd59ea6",
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
		"publish.spec.luau",
		"6a8d40de2a70b62aecaea8fff7956d0662242955f6493086fd04964d1646a520",
	},
	{
		"pickman",
		"c0015",
		"tools.spec.luau",
		"e0e14eb9e6673fdcf44e80da540e791a8c9fa6222dfaa190ee7678047d2f6200",
	},
	{
		"pickman",
		"c0051",
		"bounds.spec.luau",
		"33050b463f835a28944d7074daa5914ae40cc91a370f0a361501f04b03ae0c61",
	},
	{
		"pickman",
		"c0051",
		"classify.spec.luau",
		"1b4f069ce52ade95930ccc8e36d07cffa6e500dcd4ff53a1a531d31543f4d584",
	},
	{
		"pickman",
		"c0051",
		"final.spec.luau",
		"171a2cedc74d039cfa877dfb222bca194b68daa82335df435289e5e5e51d5e49",
	},
	{
		"pickman",
		"c0051",
		"key.spec.luau",
		"698c491465be03d1686a0ab1ef6eeaa2a6dafb0990aa939ac8b83ae8cda46237",
	},
	{
		"pickman",
		"c0051",
		"pauses.spec.luau",
		"dec09b5797bcc8a1f3b1b55aa4c8049a87102a90148acb122915864fc5d0b50a",
	},
	{
		"pickman",
		"c0051",
		"publish.spec.luau",
		"1cfeb60777fe6a5f674c306dbc107af49caf7619b2563fdbbc26d882b70f77d7",
	},
	{
		"pickman",
		"c0051",
		"retry.spec.luau",
		"d2f2c0320fac967fc2a460fc432b17ceda78825fb50d50210a74cd52d92b95cc",
	},
	{
		"pickman",
		"c0064",
		"project.spec.luau",
		"dd218a551272a3df19b76385074fb997dec4a5386a5c79b37ed1f79b4e299a32",
	},
	{
		"z-nile",
		"c0120",
		"check-paths.spec.luau",
		"162c26be2dbdadbf667a0c393346b8802c2201e5dd0c31a4aebcb029bd16341c",
	},
	{
		"z-nile",
		"c0120",
		"checkpaths.luau",
		"61b35fa76e190f9271a42555b0a88574a4cd55da3818c638e429b0c9f56dc883",
	},
	{
		"z-nile",
		"c0120",
		"finished.luau",
		"4f988db4c118bfdff35cd0876745be5183603f1f75c6c6ca7898a071c8c38ccd",
	},
	{
		"z-nile",
		"c0120",
		"finished.spec.luau",
		"f25f36b6ac6fd08d70df35a20c4de0e60e035c1e35a1c6cc43e9edeec10f2453",
	},
	{
		"z-nile",
		"c0120",
		"freeze.spec.luau",
		"6c3ae4115a1b71b4591ad70e2208b53b4e8a908a6254bd592c97f1451bef7f87",
	},
	{
		"z-nile",
		"c0120",
		"gate-homes.spec.luau",
		"1dda9a9912eb003229627a0d58d2657f909dc65dbcd7fe426425e32cb4cad346",
	},
	{
		"z-nile",
		"c0120",
		"graph-homes.spec.luau",
		"57454053c5c1bf147eac3aa64d7e40d57fa9b928b70eac599759809807873afd",
	},
	{
		"z-nile",
		"c0120",
		"homes.spec.luau",
		"da1890e98e1552c56d71741d2bc653b0b4ee72df25a6401ad7931165366427fe",
	},
	{
		"z-nile",
		"c0120",
		"old-roots.spec.luau",
		"ece585b0602eb7c65fdad14ecdc3708069d207e3898aa8d9af4746c05221a8d6",
	},
	{
		"z-nile",
		"c0120",
		"override-markers.luau",
		"156754afb2781833d4ef00340ab5f096f9482b3ed58dd84c707db9538bb499fb",
	},
	{
		"z-nile",
		"c0120",
		"promote-home.spec.luau",
		"09f5692ddba1baf55c7c2de0554418be3c6f9c52f6a02bc85dee32ac7734c9df",
	},
	{
		"z-nile",
		"c0120",
		"registry-home.spec.luau",
		"e48f1c69745267d85339775b1a3220e4e0a9beada65da8d59b1e1e65285ad590",
	},
	{
		"z-nile",
		"c0120",
		"rewrites.luau",
		"c83a8f80046bafb4ded41941510369419c85cc7ea7a2bfec2f2a65b36b57daf5",
	},
	{
		"z-nile",
		"c0120",
		"runner-home.spec.luau",
		"137161f0492d8a9a7a4f26d7b28b4697ab90e488b43fe197d33c7768602388f9",
	},
	{
		"z-nile",
		"c0120",
		"trail-home.spec.luau",
		"3a8015bba5ba97c3b9c08e2fe244cd3f677d0872c9af3a1b732ef3079b46a6dc",
	},
	{
		"z-nile",
		"c0172",
		"deploy.spec.luau",
		"381e410137ad201727b7ed6ab8d05543774ed6cb2e9fc783359f3f55679b0bd3",
	},
	{
		"z-nile",
		"c0193",
		"docs.spec.luau",
		"ad30870243758761eff434e3abaa2afa677b242832d0205e2569d3ae185951ef",
	},
	{
		"z-nile",
		"c0193",
		"finishes.spec.luau",
		"259f76b0fecfc757dea811cca20dc9836f76fb9eeae63efb0c33f4ae25566779",
	},
	{
		"z-nile",
		"c0193",
		"loops.spec.luau",
		"a98475d371ffa2df60072bafbeec63f9ece78bd3c9e59ac1f367deb8ddd4e5ad",
	},
	{
		"z-nile",
		"c0193",
		"problems.spec.luau",
		"c5e7c085b49846b2400272a83fe85c5869300e48446163052f7d3e0a99c468b6",
	},
	{
		"z-nile",
		"c0193",
		"scan.spec.luau",
		"fa22a009b68f24756c76882fad40ad86ffed6e385d498a2af21654872f755752",
	},
	{
		"z-nile",
		"c0193",
		"scanners.spec.luau",
		"1fe16aba8a2ff3f09b82dfe0357ccf8abbbefb869c0bfafbb9569ece0c407711",
	},
	{
		"z-nile",
		"c0193",
		"texts.spec.luau",
		"b33137ef39239552756474a2af4e7ad5bfcd93f00611bee0fcec74544fe2eae1",
	},
	{
		"z-nile",
		"c0193",
		"tree.spec.luau",
		"2841216cf6c73a6831924894abe700bf9a9273214900eedae70ec48d27a875cc",
	},
	{
		"z-nile",
		"c0194",
		"docs.spec.luau",
		"4d2077b256fac37828f5ce808083160417ef6b6eb2a72ec095965389f7f0eb6b",
	},
	{
		"z-nile",
		"c0194",
		"runner.spec.luau",
		"a0e4bec869bd1757fe2ed6bc063dad15705d25148ce01971faa952f400284869",
	},
	{
		"z-nile",
		"c0194",
		"shim.spec.luau",
		"717a018a222e1eda76feb9661079e2ef85619de72d5d3daeeb96b10ee2c6b357",
	},
	{
		"z-nile",
		"c0194",
		"tmp.spec.luau",
		"80d2b40e44370684b9add3198f7133347a3ff605eab56a5f44347eabdd96d1dc",
	},
}

local FOLDERS = {
	{ "pickman", "c0003" },
	{ "pickman", "c0015" },
	{ "pickman", "c0051" },
	{ "pickman", "c0064" },
	{ "z-nile", "c0120" },
	{ "z-nile", "c0172" },
	{ "z-nile", "c0193" },
	{ "z-nile", "c0194" },
}

local function watchFile(name: string): boolean
	return name == "watch.txt" or string.sub(name, -10) == ".watch.txt"
end

return t.spec("c0210 the promoted specs it rewrites are the reviewed text", function(it)
	it("each overridden promoted spec is exactly its reviewed golden", function()
		for _, row in GOLDEN do
			local path = rel(row[1], row[2], row[3])
			local golden = fs.readFile(`{HERE}/override-{row[4]}`)
			t.expect(`{path}: {exact(fs.readFile(`{TOP}/{path}`)) == golden}`).toBe(`{path}: true`)
		end
	end)

	it("every other file of those folders is exactly as reviewed", function()
		for _, row in UNCHANGED do
			local path = rel(row[1], row[2], row[3])
			t.expect(`{path}: {serde.hash("sha256", exact(fs.readFile(`{TOP}/{path}`)))}`)
				.toBe(`{path}: {row[4]}`)
		end
	end)

	it("no file is added to or removed from those folders", function()
		local pinned: { [string]: boolean } = {}
		for _, list in { GOLDEN, UNCHANGED } :: { { { string } } } do
			for _, row in list do
				pinned[rel(row[1], row[2], row[3])] = true
			end
		end
		for _, folder in FOLDERS do
			local dir = `{folder[1]}/tests/acceptance/{renamed.id(folder[2])}`
			for _, name in fs.readDir(`{TOP}/{dir}`) do
				if not watchFile(name) then
					t.expect(`{dir}/{name}: {pinned[`{dir}/{name}`] == true}`).toBe(`{dir}/{name}: true`)
				end
			end
		end
		for path in pinned do
			t.expect(`{path}: {fs.isFile(`{TOP}/{path}`)}`).toBe(`{path}: true`)
		end
	end)
end)
