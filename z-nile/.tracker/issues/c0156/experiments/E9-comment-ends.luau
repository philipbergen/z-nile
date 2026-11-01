-- c0156 E9: which characters end a Luau `--` comment? Pass: LF, CR and CRLF do (n = 1); VT and FF do not (the code after them
-- is swallowed, n stays nil). The pin rule treats CR as a line break and keeps VT and FF as they are. Fallback if a future Luau changes it:
-- change the CR step of pin.normalise and the vf-* mutants. Run: lune run experiments/E9-comment-ends.luau (2026-11-01: as above).
local luau = require("@lune/luau")
for name, sep in { LF = "\n", CR = "\r", VT = "\v", FF = "\f", CRLF = "\r\n" } do
	local ok, f = pcall(luau.load, "local n = 0 -- c" .. sep .. "n = 1 return n")
	local r = if ok then (f :: any)() else "load error"
	print(name, r)
end
