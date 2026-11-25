--!strict
-- A process's start id: the kernel's own record of when it started, read through perl (no setuid tool: a jail refuses
-- /bin/ps). The watch net's lock (engine/watchcmd) reads it. The spec runner's lock keeps its own copy of the script in
-- tests/lib/fence (its promoted specs, c0127, copy the runner's files and read that one); a case in
-- watch-net-lock.spec pins the two texts equal.
local process = require("@lune/process")

local procstart = {}

local function trim(s: string): string
	return (string.gsub(string.gsub(s, "^%s+", ""), "%s+$", ""))
end

-- Prints a process's start id, or exits 1: the start the kernel recorded for it, as exact as the kernel keeps it, and
-- never derived from the clock, so the same process always prints the same id and a later process with the same pid
-- prints another. Perl, so no setuid tool is needed (the jail and any sandbox refuse the setuid /bin/ps).
-- macOS: sysctl kern.proc.pid.<pid>, a kinfo_proc that starts with the start time (a timeval: "<sec>.<usec>").
-- Linux: /proc/sys/kernel/random/boot_id and /proc/<pid>/stat field 22, the start in clock ticks after boot.
procstart.STARTED = table.concat({
	"my $pid = shift; exit 2 unless defined $pid && $pid =~ /^\\d+$/;",
	"if ($^O eq 'darwin') { my $mib = pack('i4', 1, 14, 1, $pid); my $buf = \"\\0\" x 4096;",
	"my $len = pack('Q', length $buf); exit 2 unless syscall(202, $mib, 4, $buf, $len, 0, 0) == 0;",
	"exit 1 unless unpack('Q', $len) > 0; my ($sec, $usec) = unpack('q l', $buf); exit 1 unless $sec > 0;",
	'print "$sec.$usec\\n"; exit 0 }',
	"if ($^O eq 'linux') { open(my $b, '<', '/proc/sys/kernel/random/boot_id') or exit 2; my $boot = <$b>;",
	"close $b; chomp $boot; open(my $st, '<', \"/proc/$pid/stat\") or exit 1; my $line = <$st>; close $st;",
	"$line =~ s/^.*\\)\\s+//s or exit 2; my $ticks = (split /\\s+/, $line)[19];",
	"exit 2 unless $boot ne '' && defined $ticks && $ticks =~ /^\\d+$/; print \"$boot:$ticks\\n\"; exit 0 }",
	"exit 2;",
}, " ")

-- A process's start id (see STARTED), or nil when it can't be read (not a pid, an exited process, another system).
function procstart.startOf(pid: string): string?
	if string.match(pid, "^%d+$") == nil then
		return nil
	end
	local ok, r = pcall(process.exec, "perl", { "-e", procstart.STARTED, pid })
	if not ok or not r.ok then
		return nil
	end
	local id = trim(r.stdout)
	return if id ~= "" then id else nil
end

return procstart
