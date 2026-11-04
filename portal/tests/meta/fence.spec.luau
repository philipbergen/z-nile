--!strict
-- portal's specs run from portal/, jailed to portal/.cache (c0184): the repository-fence spec, run here too, proves in portal's own
-- gate that this run is guarded and can write nothing outside its .cache.
return require("../../../z-nile/tests/tooling/repo-fence.spec")
