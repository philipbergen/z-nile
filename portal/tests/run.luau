--!strict
-- portal's spec runner (c0184): the repository's one runner, z-nile/tests/run.luau, run from this project's home, so
-- its specs, their fixtures (portal/.cache) and the paths they name are portal's. From portal/:
--   lune run tests/run [-- <spec files relative to portal/>]
return require("../../z-nile/tests/run")
