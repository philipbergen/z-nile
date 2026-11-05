--!strict
-- arcade's specs run from arcade/, jailed to arcade/.cache (c0184): the repository-fence spec, run here too, proves in arcade's own
-- gate that this run is guarded and can write nothing outside its .cache.
return require("../../../z-nile/tests/tooling/repo-fence.spec")
