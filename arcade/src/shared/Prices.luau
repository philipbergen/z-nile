--!strict
-- The price badge's text (f0201), the one config table every screen prints: "5 R$" struck through, then "1 R$ SALE".
-- It also holds a revive's price (f0395), "1 R$" with nothing struck, which the test purchase screen prints.
-- The charge itself is the Developer Products' (PaidPlay.PRICE R$); this table only says it. Change the words here,
-- never in a screen.
return table.freeze({
	struck = "5 R$", -- shown struck through
	price = "1 R$", -- what is charged
	sale = "SALE",
	revive = "1 R$", -- a revive's price (f0395): its own, nothing struck
})
