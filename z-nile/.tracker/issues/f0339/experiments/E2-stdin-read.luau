--!strict
local stdio = require("@lune/stdio")
stdio.write("approve? [y/N] ")
local ok, line = pcall(function()
	return stdio.readLine()
end)
print("\nok=" .. tostring(ok) .. " line=[" .. tostring(line) .. "]")
