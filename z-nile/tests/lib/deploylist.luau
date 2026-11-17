--!strict
-- c0183: deploy.yml's push paths-ignore as the registry implies it: every project root `<root>/**`, in registry
-- order, an app project's whole home `<home>/**` instead (c0257: an app never publishes a place), then the
-- counter `z-nile/next`. The one copy of that list for the specs that pin it (c0114's gate-cover,
-- c0120's ci), so a new project needs its deploy.yml entry and no spec edit.
local projects = require("@znile/engine/projects")

local deploylist = {}

-- the list for the checkout whose top is `top`
function deploylist.ignored(top: string): { string }
	local out: { string } = {}
	local reg = projects.load(top)
	for _, p in reg.projects do
		table.insert(out, if table.find(reg.apps or {}, p.name) then `{p.home}/**` else `{p.root}/**`)
	end
	table.insert(out, "z-nile/next")
	return out
end

return deploylist
