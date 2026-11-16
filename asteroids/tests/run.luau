--!strict
-- asteroids's spec runner (c0184): the repository's one runner, z-nile/tests/run.luau, run from this project's home, so
-- its specs, their fixtures (asteroids/.cache) and the paths they name are asteroids's. From asteroids/:
--   lune run tests/run [-- <spec files relative to asteroids/>]
return require("../../z-nile/tests/run")
