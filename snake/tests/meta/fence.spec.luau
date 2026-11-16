--!strict
-- snake's specs run from snake/, jailed to snake/.cache (c0184): the repository-fence spec, run here too, proves in snake's own
-- gate that this run is guarded and can write nothing outside its .cache.
return require("../../../z-nile/tests/tooling/repo-fence.spec")
