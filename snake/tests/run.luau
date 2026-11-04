--!strict
-- snake's spec runner (c0184): the repository's one runner, z-nile/tests/run.luau, run from this project's home, so
-- its specs, their fixtures (snake/.cache) and the paths they name are snake's. From snake/:
--   lune run tests/run [-- <spec files relative to snake/>]
return require("../../z-nile/tests/run")
