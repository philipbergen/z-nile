--!strict
-- f0339 AC1: the explainer page's shape (explainer.check) and the answer that approves (explainer.accepts).
-- Pure: texts in, problems out.
local explainer = require("@znile/engine/explainer")
local t = require("@tests/lib/t")

local HASH = string.rep("ab", 32)
local OTHER = string.rep("cd", 32)
local PATH = "z-nile/.tracker/issues/c0001/explainer.html"
local TOUCHED = { "z-nile/engine/hold.luau", "z-nile/tests/tooling/hold.spec.luau" }

type Opts = {
	meta: string?,
	before: string?,
	after: string?,
	changes: string?,
	choices: string?,
	extra: string?,
	order: { string }?,
}

local function page(o: Opts?): string
	local opts: Opts = o or {}
	local bodies: { [string]: string } = {
		idea = "<h2>The idea</h2><p>The person reads a plain page before saying yes.</p>",
		before = opts.before or '<h2>Before</h2><svg viewBox="0 0 10 10"><rect width="4" height="4"/></svg>',
		changes = opts.changes
			or "<ul><li><code>z-nile/engine/hold.luau</code>: hold()</li><li><code>z-nile/tests/tooling/hold.spec.luau</code></li></ul>",
		after = opts.after or '<h2>After</h2><svg viewBox="0 0 10 10"><circle r="3"/></svg>',
		choices = opts.choices
			or '<div class="choice"><h3>One file</h3><ul class="pros"><li>simple</li></ul><ul class="cons"><li>long</li></ul></div>',
	}
	local chunks = {}
	for _, name in opts.order or explainer.SECTIONS do
		table.insert(chunks, `<section id="{name}">{bodies[name]}</section>`)
	end
	local meta = opts.meta or `<meta name="zn-contract" content="{HASH}">`
	return `<!doctype html><html><head><meta charset="utf-8">{meta}<title>c0001</title>{opts.extra or ""}</head><body>{table.concat(
		chunks,
		"\n"
	)}</body></html>`
end

local function problems(html: string, touched: { string }?): { string }
	return explainer.check(PATH, html, HASH, touched or TOUCHED)
end

local function one(html: string, needle: string, touched: { string }?)
	local got = problems(html, touched)
	if #got ~= 1 or not string.find(got[1], needle, 1, true) then
		error(`expected one problem with "{needle}", got:\n{table.concat(got, "\n")}`, 2)
	end
	if string.sub(got[1], 1, #PATH + 2) ~= `{PATH}: ` then
		error(`the problem does not name the page: {got[1]}`, 2)
	end
end

return t.spec("f0339 the explainer page's shape and the approving answer", function(it)
	it("AC1: a page of the shape has no problem, and the file is explainer.html", function()
		t.expect(explainer.FILE).toBe("explainer.html")
		t.expect(table.concat(explainer.SECTIONS, ",")).toBe("idea,before,changes,after,choices")
		t.expect(#problems(page())).toBe(0)
		-- single quotes and upper case are the same page
		local loud = string.upper(string.gsub(page(), '"', "'") :: string)
		t.expect(#explainer.check(PATH, loud, HASH, TOUCHED)).toBe(0)
	end)

	it("AC1: the page names the current contract, once", function()
		one(page({ meta = "" }), 'has no <meta name="zn-contract"')
		one(
			page({ meta = `<meta name="zn-contract" content="{OTHER}">` }),
			`explains contract {string.sub(OTHER, 1, 12)}`
		)
		one(page({ meta = `<meta name="zn-contract" content="{OTHER}">` }), HASH)
		one(page({ meta = '<meta name="zn-contract" content="TODO">' }), "is not a sha256")
		one(
			page({
				meta = `<meta name="zn-contract" content="{HASH}"><meta name="zn-contract" content="{HASH}">`,
			}),
			"2 zn-contract meta tags"
		)
		-- another meta tag is not the contract
		one(page({ meta = `<meta name="description" content="{HASH}">` }), 'has no <meta name="zn-contract"')
	end)

	it("AC1: the five sections, each once and in order", function()
		for _, name in explainer.SECTIONS do
			local order = {}
			for _, other in explainer.SECTIONS do
				if other ~= name then
					table.insert(order, other)
				end
			end
			local got = problems(page({ order = order }), {})
			local found = false
			for _, p in got do
				if string.find(p, `has no <section id="{name}">`, 1, true) then
					found = true
				end
			end
			if not found then
				error(`a page without {name} was not refused: {table.concat(got, "\n")}`)
			end
		end
		one(
			page({ order = { "idea", "before", "changes", "after", "choices", "idea" } }),
			'2 <section id="idea">'
		)
		one(page({ order = { "idea", "after", "changes", "before", "choices" } }), "out of order")
	end)

	it("AC1: before and after each hold an inline svg diagram", function()
		one(
			page({ before = "<h2>Before</h2><p>no picture</p>" }),
			'<section id="before"> has no inline <svg>'
		)
		one(
			page({ after = '<h2>After</h2><img alt="x" src="data:image/png;base64,AA">' }),
			'<section id="after"> has no inline <svg>'
		)
		-- a diagram in another section does not count for before
		one(
			page({ before = "<h2>Before</h2>", changes = "<code>z-nile/engine/hold.luau</code><svg></svg>" }),
			'<section id="before"> has no inline <svg>',
			{ "z-nile/engine/hold.luau" }
		)
	end)

	it("AC1: what changes where names every Touched module", function()
		one(
			page({ changes = "<ul><li><code>z-nile/engine/hold.luau</code></li></ul>" }),
			"does not name z-nile/tests/tooling/hold.spec.luau"
		)
		-- a path named only outside the changes section does not count
		one(
			page({
				changes = "<ul><li><code>z-nile/engine/hold.luau</code></li></ul>",
				choices = '<div class="choice"><p>z-nile/tests/tooling/hold.spec.luau</p><ul class="pros"></ul><ul class="cons"></ul></div>',
			}),
			"does not name z-nile/tests/tooling/hold.spec.luau"
		)
		t.expect(#problems(page({ changes = "<p>nothing</p>" }), {})).toBe(0)
	end)

	it("AC1: every choice has its pros and its cons", function()
		one(page({ choices = "<p>We chose one file.</p>" }), 'has no class="choice" block')
		one(
			page({ choices = '<div class="choice"><ul class="pros"><li>a</li></ul></div>' }),
			'choice 1 in <section id="choices"> has no class="cons"'
		)
		one(
			page({
				choices = '<div class="choice"><ul class="pros"></ul><ul class="cons"></ul></div><div class="choice"><ul class="cons"></ul></div>',
			}),
			'choice 2 in <section id="choices"> has no class="pros"'
		)
		-- "choices" and "prose" are other classes
		one(
			page({ choices = '<div class="choices"><ul class="prose"></ul><ul class="cons"></ul></div>' }),
			'has no class="choice" block'
		)
		t.expect(#problems(page({
			choices = '<div class="choice wide"><ul class="list pros"></ul><ul class="cons"></ul></div>',
		}))).toBe(0)
	end)

	it("AC1: the page fetches nothing and runs nothing", function()
		local refs = {
			'<link rel="stylesheet" href="style.css">',
			'<script src="https://cdn.example.invalid/mermaid.js"></script>',
			"<script>const n = 1;</script>",
			'<script type="module">import "https://cdn.example.invalid/m.mjs";</script>',
			"<img alt=x src=/tmp/a.png>",
			'<img alt="x" srcset="a.png 2x">',
			'<video poster="p.png"></video>',
			'<object data="d.svg"></object>',
			'<svg><image xlink:href="pic.png"/></svg>',
			'<form action="https://example.invalid/"></form>',
			'<button formaction="go"></button>',
			'<table background="bg.png"></table>',
			'<svg onload="go()"></svg>',
			'<div ONCLICK="go()"></div>',
			'<meta http-equiv="refresh" content="0;url=https://example.invalid/">',
			'<meta http-equiv="Refresh" content="0;url=next.html">',
			"<style>body { background: url(bg.png); }</style>",
			"<style>body { background: url( 'bg.png' ); }</style>",
			'<style>body { background-image: image-set("bg.png" 1x); }</style>',
			"<style>@import 'more.css';</style>",
			'<a href="https://github.com/">the PR</a>',
			"<p>see https://example.invalid/pr/1 for more</p>",
		}
		for _, ref in refs do
			local got = problems(page({ extra = ref }))
			local ok = #got >= 1
			for _, p in got do
				if not string.find(p, "the page is self-contained", 1, true) then
					ok = false
				end
			end
			if not ok then
				error(`{ref} was not refused as a fetch or a script: {table.concat(got, "\n")}`)
			end
		end
		local fine = {
			'<a href="#after">after</a>',
			'<img alt="x" src="data:image/png;base64,AA">',
			"<style>.a { background: url(#grad); } .b { background: url('data:image/png;base64,AA'); }</style>",
			'<style>.c { background-image: image-set("data:image/png;base64,AA" 1x); }</style>',
			'<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink"><use xlink:href="#box"/></svg>',
			'<div data-src="x.png" data-href="y"></div>',
			"<p>The onset = late, and the reason: none.</p>",
		}
		for _, ref in fine do
			local got = problems(page({ extra = ref }))
			if #got ~= 0 then
				error(`{ref} was refused: {table.concat(got, "\n")}`)
			end
		end
	end)

	it("AC1: a page still holding the template's placeholders, or one picture twice, is refused", function()
		one(page({ extra = '<p class="zn-fill">What is wrong today</p>' }), 'still holds the template\'s placeholder text (class="zn-fill")')
		one(page({ extra = '<p class="lead ZN-FILL">x</p><p class="zn-fill">y</p>' }), "placeholder")
		t.expect(#problems(page({ extra = '<p class="zn-filler">x</p><p>zn-fill is the marker</p>' }))).toBe(0)
		local svg = '<svg viewBox="0 0 10 10"><rect width="4" height="4"/></svg>'
		one(page({ before = `<h2>Before</h2>{svg}`, after = `<h2>After</h2>{svg}` }), "the before and after diagrams are the same picture")
		local spaced = '<svg viewBox="0 0 10 10">\n  <rect width="4"   height="4"/>\n</svg>'
		one(page({ before = `<h2>Before</h2>{svg}`, after = `<h2>After</h2>{spaced}` }), "the same picture")
	end)

	it("AC1: a section's id may stand anywhere in its tag", function()
		local html = page()
		local moved = string.gsub(html, '<section id="idea">', '<section class="card" id="idea">') :: string
		t.expect(#problems(moved)).toBe(0)
		local other = string.gsub(html, '<section id="idea">', '<section data-id="idea">') :: string
		one(other, 'has no <section id="idea">')
	end)

	it("AC1: only y or yes approves", function()
		for _, yes in { "y", "Y", "yes", "YES", " y\n", "Yes\r\n" } do
			if not explainer.accepts(yes) then
				error(`"{yes}" did not approve`)
			end
		end
		for _, no in { "n", "no", "", "\n", "yy", "ye", "yes please", "sure", "1" } do
			if explainer.accepts(no) then
				error(`"{no}" approved`)
			end
		end
		t.expect(explainer.accepts(nil)).toBe(false)
	end)
end)
