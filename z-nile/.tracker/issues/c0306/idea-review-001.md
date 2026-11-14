# Idea review 001

## Findings

- F1: Every Problem and Solution sentence turns on "a model of a final-review kind for its CLI", and the idea never says what a kind is or where one is read from. The roles table names exact ids, not kinds (`.models.toml` `[roles.final-review]`: `claude-opus-5-5` on `claude`, with fallbacks `kimi-code-k3.1-pro`, `grok-4.7` and `claude-opus-5-5` on `cursor-cli`). So a reader can't tell whether `claude-opus-4-1`, `claude-opus-5-5[1m]`, `kimi-code-k3.2` or `grok-4.7` at `high` effort passes or is refused. That leaves the sentences that depend on it, including "whatever its exact id … does not lock out an item in flight", impossible to judge true or false. The captured decision this comes from ("any Opus, any kimi-k3, any grok-...-xhigh") also makes a kind depend on effort for some CLIs, and the idea doesn't say that. Problem 3 adds two more words for the same idea ("cheap model", "the expensive model") that the Solution never maps to "final-review kind".

## Verdict

revise
