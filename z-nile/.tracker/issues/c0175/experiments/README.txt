Recorded real-CLI output, 2026-11-15 (c0175 prep). Each file is the stdout of one tiny run through `./zn run --time <s> --`,
in a scratch directory outside the repository. The probes' prompts: "reply with the single word ok" and "Run the shell command:
echo hi. Then reply with the single word done."
E1-agy-stream-tool-run.jsonl         agy 1.5.7: `agy -p <prompt> --output-format stream-json --model gemini-3.8-flash-low --dangerously-skip-permissions`
E4-opencode-stream-tool-run.jsonl    opencode 1.18.31: `opencode run <prompt> -m deepseek/deepseek-flash --format json --auto --dir <cwd>`
The other probes (error shapes, effort forms, the stderr log's tool marker, `opencode export`) are quoted in the issue's
Unknowns & experiments, and the specs under acceptance/ carry their lines.
Round 2 (the design review's F1 to F7), 2026-11-15:
E5-loopback-provider.py                  an OpenAI-compatible fake on 127.0.0.1 (python3 -I E5-loopback-provider.py <port> <mode file> <log>);
                                         the mode file says ok, 429 or 429retry (a retry-after of 400 s); a prompt with TOOL:bash, TOOL:par or TOOL:task
                                         makes it answer a bash call, two parallel bash calls or a task (subagent) call
E5-loopback-provider.opencode-config.json  the OPENCODE_CONFIG_CONTENT that names it as provider `fake`, model `m`
E16-agy-subagent-run.jsonl               agy 1.5.7 asked to call invoke_subagent: subagent steps carry no usage
E18-opencode-task-run.jsonl              opencode against the loopback provider: a task call runs a child session whose steps never reach stdout
Other results (stderr and exports) are quoted in the issue's Unknowns & experiments (E5, E6, E15, E17, E18).
Revision, 2026-11-17 (the user's rulings of 2026-11-16): prototype.patch is rebuilt as the diff of branch proto-c0175-rulings against
proto-c0251-rulings (c0251's revised prototype), less this issue's folder; its c0251/docs.spec hunk is the Override edit. The kimi alias
kimi-code/kimi-for-coding (display name K2.8 Preview) was read from ~/.kimi-code/config.toml, no model call (issue E19).
