---
title: A refusal never prints the value it refused
when: both
tags: [secrets, refusal, config, remote]
check: Does every refusal that is caused by a configuration value, a remote address or an environment value name the key and the reason without echoing the value, which may hold a token or a credential?
---
The values most often refused (an address with credentials, a program-running config entry) are exactly the ones that may contain a secret. Echoing them puts the secret in a log, a transcript and a pull request.

**Why:** f0428 steps 1 and 2 (2026-11-21, code reviews): a refusal of a local config entry printed the entry, and a refused remote printed its address with the embedded credential. Both now name the key and the form only.

**How to apply:** refusals print the name of the thing and the rule it broke. A test feeds a value holding a marker string and asserts the marker is absent from all output.
