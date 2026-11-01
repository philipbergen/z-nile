--!strict
local process = require("@lune/process")
local trackerfix = require("@tests/lib/trackerfix")
local w0 = os.clock()
local f = trackerfix.new("exp-base")
local r = process.exec("sh", { "-c", `echo files-all; find {f.base} | wc -l; echo files-origin; find {f.base}/origin.git -type f | wc -l; echo files-main-worktree; find {f.main} -type f -not -path '*/.git/*' | wc -l; du -sk {f.base}; echo procs; sort $SHIM_LOG | uniq -c | sort -rn; wc -l < $SHIM_LOG` })
print(r.stdout)
