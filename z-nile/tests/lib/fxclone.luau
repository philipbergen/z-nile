--!strict
-- c0178: the one place that copies a fixture tree. On macOS one clonefileat(2) of the whole tree (APFS makes one directory
-- entry for it, about two file events however large the tree, where a copy costs one or more per entry); where the call is
-- refused because the volume cannot clone (ENOTSUP) or the two paths are on two volumes (EXDEV), a copy; on Linux one
-- `cp -a --reflink=auto` (a reflink where the file system has one); elsewhere `cp -Rp`. `man 2 clonefile` discourages cloning
-- folders with that call; what was checked is in c0178's E11. The syscall number 462 is macOS's: it is called only when both
-- Lune and perl say the system is macOS, never elsewhere, where 462 is another call.
local fs = require("@lune/fs")
local process = require("@lune/process")

local fxclone = {}

export type Options = { copy: boolean?, simulate: string? }

-- exit 0 cloned; 2 not macOS (nothing done); 3 the source is a link or no folder; 4 the destination exists; 5 the call failed
-- (stderr: "<ERRNO NAME> <text>"). With a simulated errno the call is not made: see the seam below.
local CLONE = [[
use strict; use POSIX ();
exit 2 unless $^O eq "darwin";
my ($src, $dst, $sim) = @ARGV;
exit 3 if -l $src || !-d $src;
exit 4 if -e $dst || -l $dst;
my %name = (POSIX::ENOTSUP() => "ENOTSUP", POSIX::EXDEV() => "EXDEV", POSIX::ENOSPC() => "ENOSPC", POSIX::EEXIST() => "EEXIST", POSIX::EPERM() => "EPERM", POSIX::EACCES() => "EACCES");
my %num = reverse %name;
if (defined $sim && $sim ne "") {
  # the seam stands for a call that failed: EEXIST as if another process made the destination after the checks (it is
  # theirs), any other errno as if the call made part of the destination before it failed (it is this call's)
  mkdir($dst) or die "fxclone: cannot make $dst: $!\n";
  my $f = $sim eq "EEXIST" ? "$dst/theirs" : "$dst/partial";
  open(my $o, ">", $f) or die "$!\n"; print $o ($sim eq "EEXIST" ? "made by another process\n" : "part\n"); close $o;
  $! = $num{$sim} // POSIX::EIO(); print STDERR "$sim $!\n"; exit 5
}
my $r = syscall(462, -2, $src, -2, $dst, 0);
exit 0 if $r == 0;
my $e = $! + 0;
print STDERR (($name{$e} // "errno $e") . " $!\n");
exit 5;
]]

local function physicalExists(path: string): boolean
	return process.exec("test", { "-e", path }).ok or process.exec("test", { "-L", path }).ok
end

local function removePartial(dst: string)
	if process.exec("test", { "-d", dst }).ok and not process.exec("test", { "-L", dst }).ok then
		pcall(fs.removeDir, dst)
	end
end

local function copy(src: string, dst: string)
	local args = if process.os == "linux" then { "-a", "--reflink=auto", src, dst } else { "-Rp", src, dst }
	local r = process.exec("cp", args)
	if not r.ok then
		removePartial(dst)
		error(`fxclone: copying {src} to {dst} failed: {r.stderr}`, 3)
	end
end

-- Copies the folder `src` to `dst`, which must not exist (its parent must). Returns "clone" or "copy" and, for a copy that
-- stood in for a refused clone on macOS, the reason ("EXDEV Cross-device link"). Raises naming the paths for a source that is a
-- link or no folder, a destination that exists, and a clone that failed for any other reason (after removing what it left).
function fxclone.tree(given: string, target: string, opts: Options?): (string, string?)
	local o: Options = opts or {}
	-- a trailing slash makes `test -L` and perl's -l look through a link (code review 001 F6)
	local src = if given == "/" then given else (string.gsub(given, "/+$", ""))
	local dst = if target == "/" then target else (string.gsub(target, "/+$", ""))
	if process.exec("test", { "-L", src }).ok then
		error(`fxclone: {src} is a link: refusing to clone through it`, 2)
	end
	if not process.exec("test", { "-d", src }).ok then
		error(`fxclone: {src} is no folder`, 2)
	end
	if physicalExists(dst) then
		error(`fxclone: {dst} exists: refusing to clone into it`, 2)
	end
	if o.copy or process.os ~= "macos" then
		copy(src, dst)
		return "copy", nil
	end
	local r = process.exec("perl", { "-e", CLONE, src, dst, o.simulate or "" })
	if r.code == 0 then
		return "clone", nil
	end
	local reason = (string.gsub(r.stderr, "%s+$", ""))
	if r.code == 2 then
		error(`fxclone: perl says this is not macOS ({process.os}): refusing the macOS call`, 2)
	end
	if r.code == 3 then
		error(`fxclone: {src} is a link or no folder: refusing to clone through it`, 2)
	end
	-- only what this call made is removed: never a destination that existed (exit 4) or that another process made (EEXIST)
	if r.code == 4 or (r.code == 5 and string.sub(reason, 1, 6) == "EEXIST") then
		error(`fxclone: {dst} exists: refusing to clone into it ({reason})`, 2)
	end
	if r.code == 5 then
		removePartial(dst)
		if string.sub(reason, 1, 7) == "ENOTSUP" or string.sub(reason, 1, 5) == "EXDEV" then
			copy(src, dst)
			return "copy", reason
		end
	end
	error(`fxclone: clonefileat {src} {dst} failed (exit {r.code}): {reason}`, 2)
end

return fxclone
