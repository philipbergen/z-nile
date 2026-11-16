-- c0210 E1: in a copy of this folder outside the checkout: cp p.project.json.txt p.project.json; ./zn run --time 60 -- rojo build p.project.json -o out.rbxl; then ./zn run --time 30 -- lune run read.luau
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local game = roblox.deserializePlace(fs.readFile("out.rbxl"))
local sss = game:GetService("ServerScriptService")
for k, v in sss:GetAttributes() do
	print(k, typeof(v), string.format("%s", tostring(v)))
end
print(string.format("%.0f", sss:GetAttribute("PickmanPlaceId")))
