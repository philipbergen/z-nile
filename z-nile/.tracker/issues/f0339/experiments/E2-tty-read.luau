--!strict
local process = require("@lune/process")
local stdio = require("@lune/stdio")
stdio.write("approve? [y/N] ")
local r = process.exec(
	"perl",
	{ "-e", "open(my $f, q{<}, q{/dev/tty}) or exit 2; my $l = <$f>; print(defined $l ? $l : q{}); exit 0" }
)
print("\nrc=" .. tostring(r.code) .. " line=[" .. r.stdout .. "]")
