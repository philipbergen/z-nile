--!strict
-- invaders's specs run from invaders/, jailed to invaders/.cache (c0184): the repository-fence spec, run here too, proves in invaders's own
-- gate that this run is guarded and can write nothing outside its .cache.
return require("../../../z-nile/tests/tooling/repo-fence.spec")
