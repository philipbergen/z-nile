--!strict
-- c0325: authorship.of answers, per review mode, which models wrote the text and how sure the tool is; isAuthor
-- compares a challenger try with them, its effort ignored. Pure: rows, the live author and the toml's models go in.
local authorship = require("@znile/engine/authorship")
local t = require("@tests/lib/t")

-- the new module's exports are read through `any`: promote-check on main then fails on the missing require only
local A: any = authorship

local KNOWN = {
	"claude-fable-5-2",
	"claude-opus-5-5",
	"claude-sonnet-5-5",
	"grok-4.7",
	"kimi-code-k3.1-pro",
}

local function row(phase: string, model: string?, subject: string?): any
	return {
		when = "2026-11-15 08:00",
		subject = subject or phase,
		added = 0,
		removed = 0,
		minutes = 0,
		how = "measured",
		phase = phase,
		model = model,
	}
end

local function input(over: { [string]: any }): any
	local base: { [string]: any } = { rows = {}, firstChoice = {}, known = KNOWN }
	for k, v in over do
		base[k] = v
	end
	return base
end

local function spec(model: string, effort: string?): any
	return { cli = "claude", model = model, effort = effort, rank = 1, runtime = "claude-cli", maxTokens = 1 }
end

local function models_(a: any): { string }
	local out = {}
	for _, w in a.writers do
		table.insert(out, `{w.step}:{w.model}`)
	end
	return out
end

return t.spec("c0325: authorship reads who wrote the text, per review mode", function(it)
	it("AC3: each mode reads its own steps (idea, design, raft, code, stream, final)", function()
		t.expect(A.STEPS).toEqual({
			idea = { "idea" },
			design = { "design" },
			raft = { "raft" },
			code = { "build" },
			stream = { "build" },
			final = { "idea", "design", "build" },
		})
		t.expect(A.ROLES)
			.toEqual({ idea = "idea", design = "design", raft = "raft", build = "implementation" })
		local rows = {
			idea = { row("idea", "claude-fable-5-2-medium", "c0325 ok") },
			design = { row("prep", "claude-opus-5-5") },
			raft = { row("prep", "grok-4.7", "raft-prep") },
			build = { row("build", "claude-sonnet-5-5") },
		}
		local function of(mode: string): { string }
			return models_(A.of(mode, input({ rows = rows })))
		end
		t.expect(of("idea")).toEqual({ "idea:claude-fable-5-2" })
		t.expect(of("design")).toEqual({ "design:claude-opus-5-5" })
		t.expect(of("raft")).toEqual({ "raft:grok-4.7" })
		t.expect(of("code")).toEqual({ "build:claude-sonnet-5-5" })
		t.expect(of("stream")).toEqual({ "build:claude-sonnet-5-5" })
		t.expect(of("final")).toEqual({
			"idea:claude-fable-5-2",
			"design:claude-opus-5-5",
			"build:claude-sonnet-5-5",
		})
	end)

	it(
		"AC3: design-challenge with a design record, the raft role against its own try's id, and final-review with an implementation fallback's record are true",
		function()
			-- design-challenge has no `author` key, and neither has the raft role: the writing role is an input
			local design =
				A.of("design", input({ rows = { design = { row("prep", "claude-opus-5-5-high") } } }))
			t.expect(A.isAuthor(spec("claude-opus-5-5", "xhigh"), design)).toBe(true)
			t.expect(A.isAuthor(spec("claude-sonnet-5-5", "high"), design)).toBe(false)
			local raft = A.of(
				"raft",
				input({ rows = { raft = { row("prep", "kimi-code-k3.1-pro-high", "raft-prep") } } })
			)
			t.expect(A.isAuthor(spec("kimi-code-k3.1-pro", "low"), raft)).toBe(true)
			t.expect(A.isAuthor(spec("grok-4.7", "high"), raft)).toBe(false)
			-- with no record, the role's first choice stands in, for a role that has no `author` key too
			local bare = A.of("design", input({ firstChoice = { design = "claude-opus-5-5" } }))
			t.expect(A.isAuthor(spec("claude-opus-5-5", nil), bare)).toBe(true)
			t.expect(bare.provenance).toBe("assumed")
			local rbare = A.of("raft", input({ firstChoice = { raft = "claude-opus-5-5" } }))
			t.expect(A.isAuthor(spec("claude-opus-5-5", nil), rbare)).toBe(true)
			-- final-review: the idea, the design and the build all count, the build's a fallback of implementation
			local final = A.of(
				"final",
				input({
					rows = {
						idea = { row("idea", "claude-fable-5-2-medium", "c0325 ok") },
						design = { row("prep", "claude-opus-5-5-high") },
						build = { row("build", "kimi-code-k3.1-pro-high") },
					},
				})
			)
			t.expect(A.isAuthor(spec("kimi-code-k3.1-pro", "low"), final)).toBe(true)
			t.expect(A.isAuthor(spec("claude-fable-5-2", nil), final)).toBe(true)
			t.expect(A.isAuthor(spec("claude-opus-5-5", nil), final)).toBe(true)
			t.expect(A.isAuthor(spec("grok-4.7", "high"), final)).toBe(false)
		end
	)

	it(
		"AC3: precedence live over rows over `authorModel` over the role's first choice; empty record or empty `authorModel` is none",
		function()
			local rows = { idea = { row("idea", "claude-sonnet-5-5-high", "c0325 ok") } }
			local all = {
				live = "kimi-code-k3.1-pro",
				rows = rows,
				authorModel = "grok-4.7-high",
				firstChoice = { idea = "claude-fable-5-2" },
			}
			local function with(over: { [string]: any }): any
				local inp: { [string]: any } = table.clone(all)
				for k, v in over do
					inp[k] = v
				end
				return A.of("idea", input(inp))
			end
			local live = with({})
			t.expect(models_(live)).toEqual({ "idea:kimi-code-k3.1-pro" })
			t.expect(live.via).toBe("live")
			t.expect(live.provenance).toBe("recorded")
			local fromRows = with({ live = "" })
			t.expect(models_(fromRows)).toEqual({ "idea:claude-sonnet-5-5" })
			t.expect(fromRows.via).toBe("row")
			local fromModel = with({ live = "", rows = {} })
			t.expect(models_(fromModel)).toEqual({ "idea:grok-4.7" })
			t.expect(fromModel.via).toBe("authorModel")
			local fromRole = with({ live = "", rows = {}, authorModel = "" })
			t.expect(models_(fromRole)).toEqual({ "idea:claude-fable-5-2" })
			t.expect(fromRole.via).toBe("role")
			-- a row with an empty model, or of another phase, is no record
			local empty = with({
				live = "",
				rows = {
					idea = {
						row("idea", "", "c0325 ok"),
						row("idea", "grok-4.7", "c0325"),
						row("capture", "grok-4.7"),
					},
				},
				authorModel = "",
			})
			t.expect(models_(empty)).toEqual({ "idea:claude-fable-5-2" })
			t.expect(empty.via).toBe("role")
		end
	)

	it(
		"AC3: provenance is `recorded`, `assumed` or `unknown` as stated, and `final` is `assumed` when build alone is unrecorded",
		function()
			local idea = row("idea", "claude-fable-5-2-medium", "c0325 ok")
			local design = row("prep", "claude-opus-5-5-high")
			local recorded = A.of("code", input({ rows = { build = { row("build", "claude-sonnet-5-5") } } }))
			t.expect(recorded.provenance).toBe("recorded")
			local viaModel = A.of("code", input({ authorModel = "claude-sonnet-5-5-high" }))
			t.expect(viaModel.provenance).toBe("assumed")
			t.expect(viaModel.via).toBe("authorModel")
			local viaRole = A.of("code", input({ firstChoice = { build = "claude-sonnet-5-5" } }))
			t.expect(viaRole.provenance).toBe("assumed")
			local none = A.of("code", input({}))
			t.expect(none.provenance).toBe("unknown")
			t.expect(#none.writers).toBe(0)
			t.expect(A.isAuthor(spec("claude-sonnet-5-5", nil), none)).toBe(false)
			-- final: idea and design recorded, build not
			local final = A.of(
				"final",
				input({
					rows = { idea = { idea }, design = { design } },
					firstChoice = { build = "claude-sonnet-5-5" },
				})
			)
			t.expect(final.provenance).toBe("assumed")
			t.expect(models_(final)).toEqual({
				"idea:claude-fable-5-2",
				"design:claude-opus-5-5",
				"build:claude-sonnet-5-5",
			})
			-- every step recorded
			local all = A.of(
				"final",
				input({
					rows = { idea = { idea }, design = { design }, build = { row("build", "grok-4.7") } },
				})
			)
			t.expect(all.provenance).toBe("recorded")
			-- one step with no writer at all makes the whole unknown
			local gap = A.of("final", input({ rows = { idea = { idea }, design = { design } } }))
			t.expect(gap.provenance).toBe("unknown")
		end
	)

	it(
		"AC3: a member's design prep row and the `raft-prep` row in one folder are read by their own mode only",
		function()
			-- both rows sit in the same member folder, so the reader hands the same rows to both steps
			local both = {
				row("prep", "claude-opus-5-5-high", "prep"),
				row("prep", "grok-4.7-high", "raft-prep"),
				row("prep", "kimi-code-k3.1-pro", "raft-prep measured"),
			}
			local design = A.of("design", input({ rows = { design = both } }))
			t.expect(models_(design)).toEqual({ "design:claude-opus-5-5" })
			local raft = A.of("raft", input({ rows = { raft = both } }))
			t.expect(models_(raft)).toEqual({ "raft:grok-4.7", "raft:kimi-code-k3.1-pro" })
			t.expect(A.isAuthor(spec("claude-opus-5-5", nil), raft)).toBe(false)
			t.expect(A.isAuthor(spec("grok-4.7", nil), design)).toBe(false)
			t.expect(A.isAuthor(spec("grok-4.7", nil), raft)).toBe(true)
			-- final reads the design, not the raft
			local final = A.of("final", input({ rows = { idea = {}, design = both, build = {} } }))
			t.expect(models_(final)).toEqual({ "design:claude-opus-5-5" })
			t.expect(A.RAFT_NOTE).toBe("raft-prep")
		end
	)

	it(
		"AC4: a fallback attempt after a failed one, two layers on two models, and a draft and an answer on two models give every writer; a `code-review` or `deliver` row is no writer",
		function()
			-- layers on two models, one of them twice
			local build = A.of(
				"code",
				input({
					rows = {
						build = {
							row("build", "claude-sonnet-5-5"),
							row("build", "kimi-code-k3.1-pro-high"),
							row("build", "claude-sonnet-5-5-high"),
							row("code-review", "claude-opus-5-5"),
							row("deliver", "grok-4.7"),
							row("design-review", "grok-4.7"),
						},
					},
				})
			)
			t.expect(models_(build)).toEqual({ "build:claude-sonnet-5-5", "build:kimi-code-k3.1-pro" })
			t.expect(A.isAuthor(spec("kimi-code-k3.1-pro", "low"), build)).toBe(true)
			t.expect(A.isAuthor(spec("claude-sonnet-5-5", "low"), build)).toBe(true)
			t.expect(A.isAuthor(spec("claude-opus-5-5", "low"), build)).toBe(false)
			t.expect(A.isAuthor(spec("grok-4.7", "low"), build)).toBe(false)
			-- a draft and its answer on two models; the failed attempt (no ` ok`) is no writer
			local idea = A.of(
				"idea",
				input({
					rows = {
						idea = {
							row("idea", "claude-fable-5-2-medium", "c0325"),
							row("idea", "kimi-code-k3.1-pro-high", "c0325 ok"),
							row("idea", "grok-4.7-high", "c0325 ok"),
						},
					},
				})
			)
			t.expect(models_(idea)).toEqual({ "idea:kimi-code-k3.1-pro", "idea:grok-4.7" })
			t.expect(A.isAuthor(spec("claude-fable-5-2", nil), idea)).toBe(false)
			-- several layers of a design (prep rows) count
			local design = A.of(
				"design",
				input({
					rows = {
						design = { row("prep", "claude-opus-5-5"), row("prep", "claude-fable-5-2-high") },
					},
				})
			)
			t.expect(models_(design)).toEqual({ "design:claude-opus-5-5", "design:claude-fable-5-2" })
		end
	)
end)
