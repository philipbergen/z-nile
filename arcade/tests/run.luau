--!strict
-- arcade's spec runner (c0184): the repository's one runner, z-nile/tests/run.luau, run from this project's home, so
-- its specs, their fixtures (arcade/.cache) and the paths they name are arcade's. From arcade/:
--   lune run tests/run [-- <spec files relative to arcade/>]
return require("../../z-nile/tests/run")
