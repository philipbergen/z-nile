--!strict
-- pickman's specs run from pickman/, jailed to pickman/.cache (c0120): the repository-fence spec, run here too, proves
-- in pickman's own gate that this run is guarded and can write nothing outside its .cache.
return require("../../../tests/tooling/repo-fence.spec")
