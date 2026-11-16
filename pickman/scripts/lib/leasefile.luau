--!strict
-- The token file for the CICD lease (c0172). Mode 600. The command deletes it after a release.
local fs = require("@lune/fs")
local process = require("@lune/process")

local LeaseFile = {}

function LeaseFile.read(path: string): string?
	if not fs.isFile(path) then
		return nil
	end
	local text = fs.readFile(path)
	local token = string.match(text, "^([0-9a-f]+)\n?$")
	if token == nil or token == "" then
		return nil
	end
	return token
end

function LeaseFile.write(path: string, token: string)
	local dir = string.match(path, "^(.*)/[^/]+$")
	if dir ~= nil and dir ~= "" and not fs.isDir(dir) then
		fs.writeDir(dir)
	end
	fs.writeFile(path, token .. "\n")
	local chmod = process.exec("chmod", { "600", path })
	if not chmod.ok then
		error(`cicd: chmod of the lease file failed: {chmod.stderr}`, 0)
	end
end

function LeaseFile.remove(path: string)
	if fs.isFile(path) then
		fs.removeFile(path)
	end
end

return LeaseFile
