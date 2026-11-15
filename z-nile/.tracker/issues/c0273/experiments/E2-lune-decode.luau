local fs = require("@lune/fs")
local serde = require("@lune/serde")
for _, f in { ".cache/c0273-probe/h1/x.project.jsonc", ".cache/c0273-probe/h2/default.project.jsonc" } do
	local ok, v = pcall(serde.decode, "json" :: "json", fs.readFile(f))
	print(f, ok, if ok then type(v) else tostring(v))
end
