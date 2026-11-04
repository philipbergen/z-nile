--!strict
-- asteroids's specs run from asteroids/, jailed to asteroids/.cache (c0184): the repository-fence spec, run here too, proves in asteroids's own
-- gate that this run is guarded and can write nothing outside its .cache.
return require("../../../z-nile/tests/tooling/repo-fence.spec")
