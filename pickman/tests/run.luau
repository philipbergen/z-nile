--!strict
-- pickman's spec runner (c0120): the repository's runner, tests/run.luau at the root, run from this project's home,
-- so its specs, their fixtures (pickman/.cache) and the paths they name are pickman's. From pickman/:
--   lune run tests/run [-- <spec files relative to pickman/>]
return require("../../tests/run")
