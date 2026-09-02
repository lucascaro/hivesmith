---
issue: 62
pr:
type: added
bump: minor
---
- **`install.sh` now installs into pi.** `agents.json` gains a `pi` entry, so a global install links skills into `~/.pi/agent/skills/` whenever `~/.pi` exists, and `--agents pi`, `--status`, `--doctor`, and `--uninstall` all work against it. pi implements the Agent Skills standard, so hivesmith skills install unmodified. pi is the first harness whose project layout is not its home layout re-rooted at the project directory — it reads project skills from `.pi/skills`, not `.pi/agent/skills` — so the registry gains an optional `local_skills_dir` key that wins for the local scope only. Only `pi` declares it; every other harness resolves exactly as before. Note that pi loads project skills only after you trust the project, and that pointing pi's `settings.json` `skills` array at another harness's directory will now surface the same skills twice. A new `agent-scopes` CI job runs `tests/install-agent-scopes-test.sh`, which does real installs in a scratch `HOME` and fails if a local pi install ever lands in `.pi/agent/skills` again.
