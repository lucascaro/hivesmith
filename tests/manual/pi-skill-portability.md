# Manual smoke: hivesmith skills in Pi

Covers native Pi skill discovery and the host-capability fallbacks in `review-loop`, `pr-queue`, `brainstorm`, and `graphify-init`. Hivesmith does not install a Pi agent/subagent plugin; run this with Pi's built-in tools only, then repeat the agent-backed paths with your own plugin if desired.

## 1. Install and discover a skill

In a scratch project:

```bash
mkdir -p .pi
~/.hivesmith/install.sh --local --agents pi --prefix hs-
```

Trust the project in Pi, start `pi`, and invoke `/skill:hs-review-loop`. Pi should load the skill as a native Agent Skill. If the project is not trusted, project skills are not loaded; use a global install or trust the project.

## 2. Check capability-aware behavior (built-ins only)

Use a disposable PR and run `/skill:hs-review-loop <PR> --max-iterations 1` with no agent/subagent plugin enabled.

- The skill runs the iteration inline; it does not try to call Claude's `Agent` or `Skill` tools.
- The review step follows the installed `review-pr/SKILL.md` instructions. If those instructions cannot be located, the loop escalates instead of improvising a review.
- If autofix is needed, it follows the installed `autofix/SKILL.md` instructions. Existing push, CI, risky-change, and convergence gates remain in force.
- If an interaction needs structured options, the skill asks in chat with numbered options and waits.

Use a disposable PR because review-loop can push an authorized autofix. Do not use a protected or fork PR for this smoke.

## 3. Check an available user-owned subagent plugin

Repeat the review-loop smoke with your own agent/subagent plugin enabled. Hivesmith should dispatch through the tool and schema that plugin exposes. Verify the worker receives the target skill instructions or readable paths; if it cannot, the workflow must not claim the nested skills ran.

## 4. Check unsupported host hooks are explicit

Invoke `/skill:hs-graphify-init` from Pi. It should explain that its automatic refresh and orientation hooks currently configure Claude Code, and must not run that setup expecting Pi hooks. No Pi extension or agent plugin should be installed by this skill.
