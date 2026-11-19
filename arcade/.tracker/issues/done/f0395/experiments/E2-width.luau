--!strict
-- f0395 E2 (prep only, never run as a spec): does a four-field Prices (the library's, with `revive`) type-check where a
-- three-field type is expected (f0205's Card.Prices, c0202's Lobby.Price)? Pass: luau-lsp reports only line 13 (the
-- deliberate wrong assignment, the control), not line 12.
-- Run from the repository root: ./zn run --time 60 -- luau-lsp analyze --platform=standard <this file>
type Three = { struck: string, price: string, sale: string }
local Prices = table.freeze({ struck = "5 R$", price = "1 R$", sale = "SALE", revive = "1 R$" })
local function badge(p: Three): string
	return p.struck .. p.price .. p.sale
end

print(badge(Prices))
local _control: number = badge(Prices)
