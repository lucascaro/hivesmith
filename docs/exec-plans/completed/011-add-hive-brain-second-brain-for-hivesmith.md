# Add hive brain — a second brain for hivesmith

- **Spec:** [docs/product-specs/011-add-hive-brain-second-brain-for-hivesmith.md](../../product-specs/011-add-hive-brain-second-brain-for-hivesmith.md)
- **Issue:** #11
- **Stage:** DONE
- **Status:** completed
- **PR:** [#12](https://github.com/lucascaro/hivesmith/pull/12)
- **Branch:** feature/11-add-hive-brain (merged + deleted)

## Summary

Add a **cross-project**, file-based, git-trackable persistent knowledge store ("hive brain") at `~/.hivesmith/brain/` that hivesmith skills read at the start of a run and append to at the end. Entries are tagged by scope (`universal | ecosystem | user | project`); retrieval is filtered by active-project context so only relevant lessons surface. Goal: stop rediscovering the same lessons across repos. v1 is markdown shards with YAML front-matter, write-time redaction, explicit-promotion-only, no vector store, no hosted backend.

## Research

### Existing memory-like surfaces in this repo

- `AGENTS.md` — read by every feature skill at startup (e.g. `skills/feature-research/SKILL.md:29`, `skills/feature-plan/SKILL.md:26`, `skills/feature-implement/SKILL.md:25`, `skills/review-pr/SKILL.md:38`). It's the existing "how we work here" memo: module map, build/test commands, conventions. Mutable but not append-only.
- `golden-principles.md` — mechanical rules `gc-sweep` enforces. Capped at 5–10 principles, structured as Rule / Why / Detection / Fix shape. Not read by feature skills.
- `docs/design-docs/<slug>.md` — per-feature deep research split-offs (`skills/feature-research/SKILL.md:39`). One-feature artifacts, not project-wide.
- `docs/exec-plans/{active,completed}/<NNN>-<slug>.md` — per-feature `Decision log` and `Progress` sections, append-only (template at `docs/exec-plans/_template.md:33-43`). These embed in the plan and stay there after the plan moves to `completed/`.

**Gap:** there is no project-wide, cross-feature, append-only "brain." Lessons learned in feature N are buried in `completed/NNN-*.md` and never surface in feature N+1.

### Skill read/write hooks

All feature skills follow a shared shape: read `AGENTS.md` early → run agents / write code → append to per-feature decision log late. Natural integration points:

- **Read hook** (early, after `AGENTS.md`): `feature-research`, `feature-plan`, `feature-implement`, `review-pr`, `ralph-loop`.
- **Write hook** (late, after work converges): `feature-implement` step 39 (`skills/feature-implement/SKILL.md:32`) already appends to `Decision log` / `Progress`; same call site can also append a brain entry. `review-pr` after a finding cluster resolves; `ralph-loop` on convergence.

### Install / render mechanics

`install.sh` symlinks/renders skills into **agent homes** (`~/.claude/skills/...`), not into target projects. Prefix rendering happens in `$HIVESMITH_DIR/.rendered/$PREFIX/skills/`. **No project-local data dir convention exists** — `AGENTS.md`, `PLANS.md`, `DESIGN.md` etc. all live at project root, and skills read them via project-relative paths.

→ The brain file should live in the project repo (likely `docs/` or root), read via project-relative path, just like `AGENTS.md`. No `.hivesmith/` or `.claude/` data dir.

### `hivesmith-init` scaffolding

`skills/hivesmith-init/SKILL.md` creates `docs/{exec-plans/{active,completed},design-docs,product-specs,references,generated}/` (step ~27). The brain needs a scaffolding step: create the brain file from a template at init time, plus a checkbox in step 3 and a template-copy step ~5.

### Constraints / dependencies

- **Single source.** Per `golden-principles.md`: brain must be one file, not scattered. All skills read the same path.
- **Boundary validation.** Skills validate brain shape on read, not mid-execution.
- **Append-only history.** Like `Decision log` / `Progress`, entries are never rewritten — git diff is the audit trail.
- **Boil the lake (AGENTS.md:20).** v1 must integrate at least 2 skills (read + write) end-to-end, not stub the API. Not an ocean — a single file + 2 skill edits + scaffolding is bounded and achievable.
- **Read budget.** Adding a brain read to every skill adds tokens. Brain must be small or scoped (e.g. last N entries / tagged subset) so it doesn't bloat every prompt.
- **Prefix rendering.** Skill body cross-references use `/skill-name` and get rewritten under prefix. Brain file path is project-relative, so prefix rendering does not affect it.
- **CHANGELOG / CI gates.** Adding the brain is user-visible (new file, scaffold change), so `[Unreleased]` entry required (`AGENTS.md:32`).

### Prior art survey (May 2026)

Surveyed the AI-agent ecosystem for project-local persistent memory. Key findings:

**Dominant patterns:**
- *Single-file instructions layer* — `AGENTS.md` (open standard, Linux Foundation / Agentic AI Foundation), Claude Code's `CLAUDE.md`, Cursor's `.cursor/rules/*.mdc`, Aider's "conventions". Loaded verbatim every run. **Not memory** — config/instructions.
- *Memory-Bank pattern* (Cline / Roo Code / Kilo, ports to Cursor/Windsurf) — multi-file dir: `projectbrief.md`, `productContext.md`, `activeContext.md`, `progress.md`, `decisionLog.md`, `systemPatterns.md`. Agent reads all at session start, updates at end-of-task. Free-form, agent-edited, single-conversation scope.
- *Per-agent memory frontmatter* (Claude Code v2.1.33, Feb 2026) — each subagent gets its own `MEMORY.md`, first ~200 lines injected. **Subagents do not share memory** — already drawing public criticism.
- *Aider's repo-map* — tree-sitter call-graph ranked PageRank-style, sized to a token budget. Best automatic code-structure memory; not user-curated.
- *Memory-layer libraries* — Mem0, Letta/MemGPT, Zep+Graphiti, Cognee. External services / DBs, not git-tracked, not code-adjacent. Win on cross-project personalization or temporal queries — not the hivesmith case.

**Distilled best practices:**
- Markdown in git beats vector DBs for project-scoped, code-adjacent memory (diff-friendly, code-reviewable, survives tool churn).
- *Separate instructions from lessons.* AGENTS.md/CLAUDE.md = stable rules. A second store = accumulated findings. Mixing causes "wiki-dump" anti-pattern.
- *Append-only with timestamps + scope tags.* Treat as event log, derive current state. Pruning is a separate deliberate pass.
- *Schema "fact + why + where + when"* — bare facts rot.
- *Hybrid read scope* — always inject a tight curated index (~200–500 lines), retrieve full entries on demand by tag/path. Full-file-every-run breaks past 1–2K lines (context rot is real even in 2026).
- *Treat memory contents as untrusted* — NVIDIA / OWASP / 2026 arXiv survey all flag indirect AGENTS.md/memory injection. Wrap in delimiters; never let memory grant tool permissions or override AGENTS.md.
- *Async writes + explicit pruning* — Mem0/Letta moved writes off response path. Scheduled "memory gardener" beats inline upkeep.
- *Per-skill silos are a trap* unless skills are truly disjoint — cross-skill lessons want to be shared.

**Anti-patterns to avoid:**
- "Wiki-dump" CLAUDE.md/AGENTS.md (20K+ tokens before user types).
- Memory blindness — useful facts age out and never resurface.
- Context poisoning / spAIware — persistent injected instructions surviving sessions.
- Editable mutable memory without history — overwriting deletes audit trail.
- One-big-file past ~2K lines (context rot dominates).
- Per-feature silos with no roll-up — re-learning the same lessons.
- Unbounded growth — signal:noise collapses without a gardener.

**What's novel vs prior art:** Cline/Roo Memory-Bank is the closest neighbor, but its files are agent-edited free-form working memory tied to a single conversation. Hivesmith's pipeline produces *structured handoffs between skills* — (a) writes happen at known phase boundaries (end of review, end of ship), not "whenever the agent feels like it"; (b) each skill has a known information need, so retrieval can be skill-keyed; (c) the brain is cross-feature by design. Don't clone Memory-Bank — borrow the file-shard idea, drop always-read-everything, add the schema and the gardener.

### Cross-project pivot (May 2026, follow-up survey)

Spec was revised: brain is **cross-project**, not per-repo. That breaks several assumptions of the previous research pass.

**What changes:**
- *Storage.* No longer in the project repo. Default `~/.hivesmith/brain/`, mirroring the `~/.claude/` precedent users already understand.
- *Scoping.* Skill+topic is no longer enough — *active-project context disambiguates*. "Tests are flaky" needs `(repo, language, runner)` or it surfaces a Jest fact during a pytest run.
- *Trust.* Indirect injection that previously poisoned one repo now persists to every session on the machine. InjecMEM (OpenReview) and the GitHub MCP heist (Docker blog) show cross-repo bleed is a documented attack class.
- *Stale facts.* "Auth is flaky" is true in repo X for 3 weeks. Without temporal scoping it becomes a permanent universal claim. Graphiti's bitemporal facts are the only mainstream answer.
- *Retrieval.* Must filter by active-project context first, *then* semantic/tag match (Mem0 entity-scoped pattern).
- *Privacy.* Code snippets and secrets from project A must not reach project B prompts. Write-time redaction is now non-negotiable.

**Cross-project landscape:**
- Claude Code: `~/.claude/CLAUDE.md` (user-global instructions) + per-project auto-memory; **no first-class cross-project shared memory** — community has been requesting since 2025 (issue #36561). Third parties like `claude-mem` fill the gap.
- Cursor: explicit split — Global User Rules + project `.cursor/rules/*.mdc` + Team Rules dashboard. Memories themselves are project-scoped.
- Windsurf: rules shareable, memories explicitly individual; team pattern is a dotfiles repo.
- Mem0: 4-scope model (`user_id`, `agent_id`, `app_id`, `run_id`) + arbitrary metadata for filtering. Cleanest existing answer to universal-vs-project tagging.
- Letta: Memory blocks attachable to multiple agents via `block_ids`. Concurrency-safe additive insert.
- Zep / Graphiti: temporal knowledge graph with bitemporal facts ("X was true between t1 and t2").
- A-Mem (arxiv 2502.12110): Zettelkasten-style linked notes — universal facts link to project-specific applications.

**Schema implications — multi-dimensional tagging, not a single hierarchy:**
- `scope`: `universal | ecosystem | user | team | project`
- `ecosystem` (when applicable): `python+poetry`, `bun`, `kubectl`, etc.
- `repo`: canonical id (origin URL hash) when scope=project
- `valid_from` / `valid_until`: borrowed from Graphiti — kills stale "flaky" claims automatically
- `provenance`: which session/commit/tool wrote it (mandatory for injection forensics)
- `confidence`: down-weight one-off observations vs corroborated patterns

**Privacy / leakage — state of the art:**
- OWASP Agent Memory Guard (2026) is the canonical checklist.
- Production systems do: write-time redaction (regex + secret scanners), explicit allow-lists for promotion, signed provenance, quarantine for entries derived from untrusted file content (READMEs, issue bodies, web pages), retrieval-time scope filters that *refuse* to surface project=A facts in a project=B session.
- Strong signal: **never copy raw code/file content into the brain**. Distilled, redacted lessons only.

**Storage / sync — what works:**
- File + git is what every successful team-sharing solution converges to (Cursor team rules, Windsurf dotfiles).
- Hosted (Mem0/Letta/Zep cloud): cross-device sync, richer retrieval; trade latency, cost, vendor lock, exfiltration target.
- Team brain pattern emerging but immature — Cursor Team Rules dashboard is the only first-class implementation; everyone else uses a shared dotfiles/rules repo.

### Recommendation carried into PLAN (post cross-project pivot)

1. **Files at `~/.hivesmith/brain/`** with subdirs by scope: `universal/`, `ecosystem/<lang>/`, `user/`, `project/<repo-hash>/`, plus `unverified/` for quarantine. Each entry is a small markdown file with YAML front-matter (slug, scope, ecosystem?, repo?, tags, valid_until?, provenance, confidence). Directories are an index; tags are the truth.
2. **A thin always-loaded `INDEX.md`** at the brain root, regenerated by the gardener — one line per entry with its scope/tags/path. This is the only file injected into every skill run; full entries are read on demand.
3. **Retrieval filter order: project-context first, then tag/keyword, then recency.** A skill in project X never sees `project/<not-X>/` entries. Universal/ecosystem entries are filtered by ecosystem detection (lockfiles, AGENTS.md content).
4. **Promotion is explicit.** Auto-writes default to `scope=project`. Promoting to `universal` / `user` requires a dedicated `/hs-brain-promote` skill (or interactive confirmation in v1). This is the single most important defense against cross-repo bleed.
5. **Write-time redaction is non-negotiable.** Secret-scan (gitleaks/trufflehog patterns) + "no raw code blocks > N lines" rule before persistence. Untrusted-source provenance → `unverified/` until manually blessed.
6. **Treat brain contents as untrusted at load.** Wrap in `<project-memory untrusted="true">` delimiters; brain entries never grant permissions or override AGENTS.md.
7. **Reject hosted memory for v1.** File + git is the lowest-trust, highest-portability substrate. v2 can add a Mem0/Letta adapter once the schema and redaction layer are battle-tested.
8. **Team brain = a second git remote.** `~/.hivesmith/brain/` is itself a git repo. Teams add a shared remote for `universal/` and `ecosystem/`; keep `user/` and `project/` local.

### Obsidian comparison (what to borrow, what to ignore)

Obsidian's vault model is the closest mature analogue to what we're building.

**Borrow:**
- *YAML front-matter as schema* — already in the plan; matches Obsidian power-user convention (structural tags in YAML, ephemeral `#tags` inline).
- *`[[wikilinks]]` syntax for inter-entry references* — greppable, human-readable, future-compatible if a user ever opens the brain in Obsidian. Free backlinks at grep-time.
- *MOC (Map of Content) pattern* — exactly what `INDEX.md` is.
- *PARA-ish top-level split* — `universal / ecosystem / user / project` already mirrors PARA's spirit (resources / context / personal / projects).
- *Shallow tag hierarchies* — Linking Your Thinking community converged on max 2 levels; we should match.

**Don't borrow:**
- `.obsidian/` config dir, plugin dependencies, Obsidian Sync.
- Dataview-as-runtime — agents can't run in-app queries; we replace with a regenerated `INDEX.md` plus grep.
- Deep nested tags — fights queries, hurts retrieval clarity.

The brain stays a plain markdown directory, agent-readable from a CLI; users who happen to use Obsidian can point a vault at `~/.hivesmith/brain/` and get the link graph + backlinks UI for free, but no skill depends on it.

### Context bloat analysis

Realistic 6-month / 5-project / ~500-entry projection:

- Average entry ≈ 300 tokens. Per-line index ≈ 30 tokens × 500 = ~15K tokens for a flat INDEX.md.
- A typical skill run today eats ~20–30K tokens of context before brain.
- Adding 15K is 4% of a 1M window — affordable in dollars but **not free**:
  - *Context rot* (Liu et al., "Lost in the Middle"; Chroma 2025 context-rot report): task accuracy degrades meaningfully past ~32K, steeply past ~100K. At 40K we're in the gentle slope; every doubling hurts.
  - *Prompt cache*: a regenerated INDEX.md after every write busts the cache prefix for every subsequent skill run. Costly.

**Mitigations adopted into the design:**

1. **Tiered index, never inject the full thing.**
   - *Tier 1 — Hot* (≤ ~50 lines, ~1.5K tokens, always injected): pinned + recently-used + highest-confidence.
   - *Tier 2 — Filtered slice* (≤ ~500 lines, ~15K tokens, eager-injected): `universal/` + `ecosystem/<active-lang>/` + `user/` + `project/<this-repo-hash>/`. Computed cheaply from active project context (repo URL hash, lockfile-based ecosystem detection).
   - *Tier 3 — Cold* (grep-only): everything else. Agent only touches via on-demand Read.
2. **Hard caps:**
   - `INDEX.md` ≤ ~2000 lines total; gardener evicts oldest-unused / lowest-confidence to `archive/`.
   - Per-skill-run injected brain budget: ≤ 8K tokens; ≤ 5 on-demand Reads. Encoded as a rule in each integrating skill.
3. **Glob-conditional injection** (Cursor-rules pattern): project-scope entries declare `applies_to:` globs; surface only when matching files are touched in the current diff/change.
4. **Ranking metadata in every index line** — recency, confidence, backlink count, `valid_until` — so top-K selection is mechanical (agent picks the obvious K, doesn't browse).
5. **Cache-friendly gardening** — gardener writes `INDEX.md` at session boundaries, not per write; staging happens in `unverified/` so the hot prefix stays stable across runs.
6. **Per-skill-run state-a-question-first rule** (anti-greediness): the skill must state *what it's looking up* before each on-demand Read. Cheap discipline; prevents the "let me just read 30 entries" failure mode.

Aider's repomap (~1K tokens, PageRank-ranked, recomputed per turn) and Cursor's per-rule glob injection are the two closest prior-art mechanisms — we're effectively combining them.

### Graphify integration — division of labor

This repo already runs **graphify** (`AGENTS.md:1-5`, `graphify-out/GRAPH_REPORT.md`). Graphify provides — per-project — a self-updating knowledge graph of the codebase: 172 nodes / 210 edges / 15 communities here. It exposes:

- `graphify-out/graph.json` + `graph.html` (visual)
- `GRAPH_REPORT.md` (community hubs, "god nodes", surprising connections, hyperedges) — already uses Obsidian-style `[[wikilinks]]`
- `graphify query "<q>" --budget N` (BFS/DFS traversal with explicit token budget — exactly the retrieval primitive we'd otherwise reinvent)
- `graphify path A B`, `graphify explain X`
- `graphify watch` + `graphify hook install` (auto-rebuild on file changes / git hooks) — the "keep itself current" guarantee
- `graphify save-result` — feeds Q&A answers back into a `graphify-out/memory/` dir to grow the graph

This is highly relevant. The cleanest division of labor:

- **Graphify owns code-structure knowledge** — what calls what, where things live, communities, "god nodes," call paths. Per-project, machine-derived, automatically current. **Brain never duplicates this.** No entries like "auth lives at src/auth.ts" or "the feature pipeline is feature-next → … → ralph-loop" — graphify has them, and a brain copy will rot the moment files move.
- **Hive brain owns experiential/cross-project knowledge** — lessons, gotchas, decisions, conventions. Things that are *not* derivable from current code: "macOS CI runners are flaky for tests that hit the network," "we tried approach X and it doesn't work because of Y," "this team prefers terse PR descriptions." Cross-project by design.
- **Linkage:** brain entries `[[wikilink]]` to graphify nodes when referencing specific code abstractions. Same syntax both systems already use → greppable join, no parser needed. A brain entry like "the `[[review-pr fan-out]]` hyperedge tends to over-fire on docs-only PRs, suggest skipping correctness agent" cleanly references a graphify node.
- **Retrieval composition at skill startup:**
  1. Read brain `INDEX.md` (cross-project lessons).
  2. Read graphify `GRAPH_REPORT.md` if present (per-project structure orientation, ~1-2K tokens).
  3. On demand: `graphify query` for code-structure questions; brain on-demand Reads for lesson lookups.
  Two complementary lookups, no overlap.
- **Feedback loop:** brain entries derived from a specific project's investigation can also call `graphify save-result` to feed the per-project graph. Brain remains the cross-project store; graphify remains the per-project memory. They reinforce each other.

**Concrete consequences for the plan:**

- Drop "code-structure entries" from brain scope. The brain schema's `applies_to:` glob and `repo:` hash is for *lessons* about that code, not the code map.
- Borrow graphify's `--budget N` retrieval idiom for brain on-demand Reads (cap on tokens returned, not just count of entries).
- A brain entry's YAML can include `graph_nodes: [foo, bar]` to declare it pertains to specific graphify nodes — gardener can then validate those nodes still exist in the graph and flag the entry if they don't (auto-rot detection).
- `hs-hivesmith-init` should suggest `graphify install` if not already present — they're synergistic, not redundant.
- The brain does *not* need a vector store nor a graph of its own in v1. Tag-filter + grep + `[[wikilinks]]` for human-followable references is enough; if cross-entry semantic retrieval becomes a need later, the same data can be ingested into a brain-side graphify run (graphify takes any markdown corpus).

This narrows scope, removes the most rot-prone entry class, and lets the brain do exactly the thing graphify *can't* (cross-project, experiential, opinion-bearing).

### Open questions for PLAN (post-pivot, narrowed)

1. **Repo identity hash** for `project/<hash>/`: hash of `git config remote.origin.url` (canonicalized: strip `.git`, strip user, lowercase) is the obvious choice — confirm in PLAN. Fallback for repos with no remote: hash of toplevel path.
2. **Ecosystem detection** for retrieval filtering: lockfile-based (`package.json` → bun/node, `pyproject.toml` → python+poetry, etc.) is straightforward — agree the v1 detection list in PLAN.
3. **Read integration v1**: `hs-feature-research`, `hs-feature-plan`, `hs-review-pr`. Each reads `INDEX.md` + filters by active project + ecosystem.
4. **Write integration v1**: `hs-feature-implement` (on convergence), `hs-review-pr` (per finding cluster resolved), `hs-ralph-loop` (on convergence). Default `scope=project` unless promotion skill invoked.
5. **Init / scaffolding**: `~/.hivesmith/brain/` should be auto-initialized (and `git init`'d) on first use. `hs-hivesmith-init` should *not* be the only path — most users running a hivesmith skill on an existing repo will hit the brain first. Add lazy-init to a shared helper.
6. **Redaction tooling**: bundle a simple regex set in v1 (AWS keys, GitHub tokens, generic high-entropy strings) or shell out to `gitleaks` if installed. Shell-out plus inline fallback is cleanest — confirm in PLAN.
7. **Gardener (`/hs-brain-garden`)**: scope for v1 = regenerate `INDEX.md`, archive entries past `valid_until`, surface promotion candidates. Keep dedup heuristics minimal.
8. **Existing user-global `~/.claude/CLAUDE.md` and auto-memory**: brain *complements*, does not replace. Confirm in PLAN that brain reads do not also read auto-memory (avoid duplication / loops).

## Approach

**Chosen design:** a cross-project, file-based, git-trackable markdown store at `~/.hivesmith/brain/`, with **shared bash helpers under `scripts/brain/`** that all integrating skills call. Schema is YAML front-matter + body. Retrieval is **tiered** (hot pin / eager-filtered slice / cold grep). Promotion is **gated by an explicit skill**. Writes are **redacted at the boundary**. Code-structure facts are **delegated to graphify**, not stored in the brain. Two new user-facing skills (`hs-brain-promote`, `hs-brain-garden`) plus read/write integration into 3+3 existing skills.

**Why this beats the obvious alternatives:**
- *Hosted backend (Mem0/Letta/Zep)* — vendor lock, latency, an exfiltration target, breaks the "git is the audit trail" property. Rejected for v1; left as a v2 adapter slot.
- *Per-repo `docs/brain/`* — original v0 idea. Rejected on the cross-project pivot: lessons don't transfer across repos and most of the value of a "second brain" comes from accumulating across projects.
- *Single big `brain.md`* — context rot past ~2K lines, no scope filtering, can't shard `universal/` from `project/`. Rejected.
- *Subsume into graphify* (use `graphify-out/memory/`) — graphify is per-project; conflating it with cross-project memory loses the clean "graphify=code map, brain=lessons" separation. Rejected. Instead, link via `[[wikilinks]]` and `graph_nodes:` YAML.
- *Make brain ops skills themselves rather than helpers* — overkill: skills are ~200-line markdown prose files; per-call brain ops want to be 30-line bash helpers. We do create *user-facing* skills for promote and garden (those are real workflows), but read/append are helpers called inline.

**Layout on disk (target user machine):**

```
~/.hivesmith/brain/                  # git repo, init'd on first use
├── INDEX.md                         # gardener-regenerated, tiered (hot/all)
├── SCHEMA.md                        # entry schema doc (copied from templates)
├── README.md                        # team-onboarding doc (copied from templates)
├── universal/<slug>.md              # cross-project lessons
├── ecosystem/<lang>/<slug>.md       # language/runtime-specific
├── user/<slug>.md                   # user preferences across projects
├── project/<repo-hash>/<slug>.md    # per-project lessons
├── unverified/<slug>.md             # quarantine: untrusted-source provenance
└── archive/<YYYY-MM>/<slug>.md      # gardener-evicted, kept for git history
```

`<repo-hash>` = first 12 chars of `sha256(canonicalized(remote.origin.url))`. Fallback: hash of `git rev-parse --show-toplevel` for repos without a remote.

**Entry schema (YAML front-matter + body):**

```yaml
---
slug: tests-flaky-on-macos-network
scope: project          # universal | ecosystem | user | project
ecosystem: bun          # optional; required when scope=ecosystem
repo: 7f3a91c2b4d5      # required when scope=project
applies_to: ["**/test/**/*.ts"]   # optional globs (Cursor-style conditional injection)
tags: [testing, ci, flake]
graph_nodes: [review_pr_skill, ci_workflow]   # optional; gardener checks these still exist
valid_until: 2026-08-09  # optional Graphiti-style temporal expiry
provenance:
  source: hs-feature-implement
  session: 2026-05-09T17:42:11Z
  pr: 42
  trusted: true         # false = derived from untrusted file content → unverified/
confidence: 0.7         # 0.0-1.0
created: 2026-05-09
backlinks: 0            # gardener-maintained
---

# Lesson title

**Lesson:** <one-paragraph distilled lesson>

**Why:** <one-paragraph reason / context>

**How to apply:** <one-paragraph guidance>
```

**`INDEX.md` format (tiered):**

```markdown
<!-- HOT (≤50 lines, pinned + recent + high-confidence) -->
- [[universal/lake-vs-ocean]] · universal · conf=0.9 · 2026-05-08 · "boil-the-lake test"
- [[ecosystem/bun/bun-test-isolation]] · ecosystem:bun · conf=0.8 · 2026-05-07 · ...

<!-- HOT END -->

<!-- ALL (gardener-sorted by scope then date desc, capped 2000 lines) -->
- [[project/7f3a91c2b4d5/auth-flaky-macos]] · project:7f3a91… · conf=0.7 · 2026-05-09 · applies_to=test/auth/* · ...
...
```

Skills inject HOT verbatim; for ALL, they grep with the active project's repo-hash + ecosystem and inject only matching lines.

**Read flow (called by integrating skills):**

```
scripts/brain/read.sh
  detect repo_hash, ecosystem
  ensure ~/.hivesmith/brain/ exists (lazy-init if not)
  emit:
    1. HOT block of INDEX.md (always)
    2. ALL lines that match scope=universal OR scope=user OR (scope=ecosystem AND ecosystem=$detected) OR (scope=project AND repo=$repo_hash)
    3. for any applies_to entries, intersect with the calling skill's "current change" file list (passed via env BRAIN_FILES) — drop entries whose globs don't match
    4. budget cap: stop emitting when output reaches BRAIN_BUDGET_TOKENS (default 8000, est'd by char count / 4)
  prepend untrusted-data delimiter: <project-memory untrusted="true">...</project-memory>
```

**Write flow (called by integrating skills):**

```
scripts/brain/append.sh --scope project --slug "<slug>" --tags "..." [--graph-nodes "..."] [--valid-until DATE] --confidence 0.7 [--from-untrusted-source] < lesson.md
  validate slug (kebab-case, ≤80 chars)
  validate scope ∈ {universal,ecosystem,user,project}
  if --from-untrusted-source: target = unverified/<slug>.md
  else: target = <scope>/<...>/<slug>.md
  redact: run scripts/brain/redact.sh on body BEFORE write
    - regex passes: AWS keys, GitHub tokens, generic high-entropy strings, RSA/EC private keys
    - reject any code fence > 25 lines (forces distillation)
    - if `gitleaks detect --pipe` is on PATH, run it on body and abort on hit
  fill provenance from env (HIVESMITH_SKILL, current ISO timestamp, PR number from gh if available)
  write file, add to git, commit with conventional message "brain: add <slug>"
  return target path on stdout
```

**Promotion flow (`hs-brain-promote` skill):**

User invokes with an entry slug. Skill prompts for new scope (`universal` / `ecosystem:<lang>` / `user`). Diffs the candidate, asks for confirmation (no auto-promotion). On approval: move file via `git mv`, update front-matter `scope:`, append a Decision-log line to the entry body. This is the only path that broadens scope.

**Gardener flow (`hs-brain-garden` skill):**

1. Regenerate `INDEX.md` (HOT + ALL tiers).
2. Move entries past `valid_until` to `archive/<YYYY-MM>/`.
3. Validate `graph_nodes:` references against per-project `graphify-out/graph.json` files when present (cwd or registered paths) — flag stale.
4. Surface promotion candidates: entries with high confidence + multiple recent reads + no project-specific tags.
5. Surface dedupe candidates: entries with overlapping tags + similar slugs (Levenshtein cheap heuristic).

Outputs are reported but never auto-applied — gardener is read-mostly; user runs `hs-brain-promote` or manual edits to act.

**Lazy-init (called from `read.sh` and `append.sh`):**

```
if [[ ! -d ~/.hivesmith/brain ]]; then
  mkdir -p ~/.hivesmith/brain/{universal,ecosystem,user,project,unverified,archive}
  cd ~/.hivesmith/brain && git init -q && git commit --allow-empty -m "brain: init"
  cp $HIVESMITH_DIR/templates/brain/{SCHEMA.md,README.md,INDEX.md,.gitignore} ~/.hivesmith/brain/
fi
```

`hs-hivesmith-init` runs the same lazy-init explicitly and additionally suggests `graphify install` if not present.

**Skill integration points (exact locations):**

| Skill | Read site | Write site |
|---|---|---|
| `hs-feature-research/SKILL.md` | New step after step 21 (after AGENTS.md read, before Explore agents launch): call `scripts/brain/read.sh` and inject result | — |
| `hs-feature-plan/SKILL.md` | New step after step 28 (after AGENTS.md read): same | — |
| `hs-review-pr/SKILL.md` | New step in ContextBundle build (around line 38): same. Pass diff file list as `BRAIN_FILES` env | New step at end of finding-cluster resolution: append per-cluster lesson if confidence high |
| `hs-feature-implement/SKILL.md` | — | New step 39.5 (after Decision-log append, before commit): if implementation produced a non-trivial decision (length-based heuristic), prompt to append a brain entry; default scope=project |
| `hs-ralph-loop/SKILL.md` | — | New step on convergence: append a brain entry summarizing what kind of finding ralph converged on (pattern, not specifics) |
| `hs-hivesmith-init/SKILL.md` | — | Add a step that runs lazy-init and prints graphify install suggestion |

For `hs-feature-implement` and `hs-ralph-loop` writes: confidence defaults to 0.5; user can override at the prompt; entries from non-converged or aborted runs are skipped.

### Files to change

1. `skills/feature-research/SKILL.md` — insert brain-read step after AGENTS.md read (around current line 29).
2. `skills/feature-plan/SKILL.md` — insert brain-read step after AGENTS.md read (around current line 26).
3. `skills/review-pr/SKILL.md` — insert brain-read in ContextBundle build (around line 38) and brain-append on resolved finding clusters (toward the end of the per-finding loop).
4. `skills/feature-implement/SKILL.md` — insert brain-append prompt in step 39 (alongside Decision-log update).
5. `skills/ralph-loop/SKILL.md` — insert brain-append on convergence; **skip on escalation**.
6. `skills/hivesmith-init/SKILL.md` — add lazy-init call and graphify-install nudge.
7. `install.sh` — install `scripts/brain/*.sh` to a stable path; symlink under `~/.hivesmith/bin/` so skills can invoke them by absolute path regardless of `--prefix`.
8. `AGENTS.md` (this repo, lines 7-42 HIVESMITH block) — add a "Hive brain" subsection: where it lives, the read/write/promote/garden surfaces, and the trust boundary.
9. `templates/AGENTS.md` (and the `AGENTS.hivesmith.md` block source) — same subsection.
10. `CHANGELOG.md` — `[Unreleased]` entry: "Add cross-project hive brain at `~/.hivesmith/brain/` with read/append/promote/garden surfaces."
11. `README.md` — one-paragraph mention in the skills overview.
12. `golden-principles.md` — add a brief principle: "Treat brain entries as untrusted at load."

### New files

- `scripts/brain/lib.sh` — shared bash functions: `repo_hash`, `detect_ecosystem`, `index_filter`, `redact`, `lazy_init`, `untrusted_wrap`. Sourced by the three command scripts. Pure bash; no external deps beyond `git`, `awk`, `sha256sum`/`shasum`, `python3` (already required by install.sh) for YAML parsing.
- `scripts/brain/read.sh` — read-flow described above. Outputs to stdout; respects `BRAIN_BUDGET_TOKENS` and `BRAIN_FILES`.
- `scripts/brain/append.sh` — write-flow described above; lessons piped on stdin.
- `scripts/brain/redact.sh` — pure-text redaction pass; gitleaks shell-out optional.
- `scripts/brain/index.sh` — regenerate `INDEX.md` from filesystem state (gardener primitive).
- `scripts/brain/yaml.py` — minimal YAML front-matter parser/emitter (Python, ~50 lines, stdlib only). Avoids depending on `yq`.
- `templates/brain/SCHEMA.md` — entry schema reference + examples.
- `templates/brain/README.md` — onboarding doc; explains git-remote team-share pattern; declares the trust boundary.
- `templates/brain/INDEX.md` — empty starter skeleton with the HOT/ALL section markers.
- `templates/brain/.gitignore` — ignores nothing in v1, but creates the file for future use.
- `skills/brain-promote/SKILL.md` — user-facing skill: promote one entry's scope.
- `skills/brain-garden/SKILL.md` — user-facing skill: regenerate index, archive expired, surface candidates.
- `skills/brain-promote/promote.sh` — executor invoked by SKILL.md.
- `skills/brain-garden/garden.sh` — executor invoked by SKILL.md.

### Tests

All test invocations are added to `AGENTS.md`'s build/test list and mirrored in `.github/workflows/ci.yml`.

1. **Shellcheck (extend existing):** add `scripts/brain/*.sh skills/brain-promote/promote.sh skills/brain-garden/garden.sh` to the existing shellcheck invocation in `AGENTS.md` line 36.
2. **`scripts/brain/test/test_repo_hash.sh`** — given fixture `git config remote.origin.url` values (https/ssh/with-trailing-.git/uppercase host), assert canonical hashes are stable and equal across forms.
3. **`scripts/brain/test/test_ecosystem_detect.sh`** — fixtures dirs containing `package.json`+`bun.lockb`, `pyproject.toml`+`poetry.lock`, `Cargo.toml`, `go.mod`; assert detector emits `bun`, `python+poetry`, `rust`, `go`.
4. **`scripts/brain/test/test_redact.sh`** — feed strings containing AWS access keys, GitHub PATs (`ghp_…`), private RSA blocks, a 30-line code fence; assert `redact.sh` either masks them or aborts with a non-zero exit.
5. **`scripts/brain/test/test_append_isolation.sh`** — set `HOME=$(mktemp -d)`, run two appends from different fake-project cwds, assert files land in `project/<hash-A>/` and `project/<hash-B>/` respectively and never cross-contaminate.
6. **`scripts/brain/test/test_read_filter.sh`** — populate a brain with 4 fixture entries (one per scope), run `read.sh` from a project whose repo-hash matches one of them, assert output contains universal+user+matching-project entry, does not contain non-matching project entry, and respects `BRAIN_BUDGET_TOKENS=500`.
7. **`scripts/brain/test/test_index_regen.sh`** — populate a brain with N fixture entries, run `index.sh`, assert HOT contains N≤50 highest-ranked entries, ALL is sorted, and result is byte-stable on repeated runs (cache-friendliness).
8. **`scripts/brain/test/test_promote.sh`** — start from a `project/…/foo.md`, run `promote.sh foo --to universal`, assert `git mv` happened and YAML `scope` updated.
9. **`scripts/brain/test/test_lazy_init.sh`** — `HOME=$(mktemp -d)`, no pre-existing `~/.hivesmith/brain/`, run `read.sh`, assert dir is created, git initialized, templates copied, exit 0 with empty output.
10. **`scripts/brain/test/test_garden_stale_graph_nodes.sh`** — fixture entry with `graph_nodes: [foo, bar]`; fixture `graphify-out/graph.json` with only `foo`; run garden; assert it flags the entry but does not modify it.
11. **Render correctness:** existing render-correctness check (AGENTS.md line 38) extended to assert `/hs-brain-promote` and `/hs-brain-garden` resolve under prefix.
12. **Install smoke (extended):** existing dry-run install asserts `scripts/brain/*.sh` are placed under `~/.hivesmith/bin/` and are executable.
13. **Changelog non-empty:** existing gate covers the new `[Unreleased]` entry.
14. **review-pr regression suite:** add a fixture case `cases/brain-aware-review/` that exercises the brain-read step in `hs-review-pr` (graded LLM harness — verify the bundle includes the `<project-memory>` block when a brain entry matches, omits it when none match).

A test runner `scripts/brain/test/run-all.sh` invokes 2-10 and reports pass/fail; CI runs it alongside the existing shellcheck/install-smoke jobs.

**Coverage on the success criteria:**
- *Documented schema + storage* → `templates/brain/SCHEMA.md` + `templates/brain/README.md`.
- *Read/write entry points usable from skills* → `scripts/brain/{read,append}.sh` + integration in 6 skills.
- *Write-time redaction* → `scripts/brain/redact.sh` + test 4.
- *Explicit promotion* → `skills/brain-promote/` + test 8.
- *Two skills read end-to-end across two repos* → `hs-feature-research`, `hs-feature-plan`, `hs-review-pr` integrate read; test 5 + test 6 prove cross-repo isolation; manual smoke test in two real repos before merge.

## Decision log

<Append-only. One entry per non-trivial decision made during implementation. Keep entries short.>

## Progress

- **2026-05-09** — TRIAGE → RESEARCH. Type=enhancement, Complexity=M, Priority=P1.
- **2026-05-09** — Research complete. Five open questions surfaced for PLAN.
- **2026-05-09** — Prior-art survey added (May 2026 ecosystem scan). Five questions narrowed with leaning recommendations.
- **2026-05-09** — Spec pivoted: brain is **cross-project**, not per-repo. Storage moved to `~/.hivesmith/brain/`. Cross-project follow-up survey added; recommendation expanded from 5 to 8 bullets covering scope tagging, retrieval filtering, promotion gating, redaction, untrusted-load handling, and team-sync via git remote.
- **2026-05-09** — Obsidian comparison + context-bloat analysis added. Adopted tiered-index design (hot / eager-filtered slice / cold-grep), hard caps (INDEX ≤2000 lines, per-run budget ≤8K tokens & ≤5 Reads), glob-conditional injection (Cursor pattern), ranking metadata, and cache-friendly gardener cadence.
- **2026-05-09** — Graphify integration analyzed. Brain explicitly does **not** store code-structure facts (graphify owns those, per-project, self-updating). Brain entries can `[[wikilink]]` graphify nodes; YAML can declare `graph_nodes:` for auto-rot detection. Eliminates the most rot-prone entry class.
- **2026-05-09** — RESEARCH → PLAN. Approach drafted: shared bash helpers under `scripts/brain/`, schema + tiered INDEX, six skill integration sites (3 read + 3 write), two new user-facing skills (`hs-brain-promote`, `hs-brain-garden`), 14 test invocations covering redaction / cross-project isolation / promotion / lazy-init / index regen.
- **2026-05-09** — PLAN → IMPLEMENT. Branch `feature/11-add-hive-brain` cut.
- **2026-05-09** — Helpers landed: `scripts/brain/{lib.sh,read.sh,append.sh,redact.sh,index.sh,yaml.py}` (~600 lines). Templates landed: `templates/brain/{SCHEMA,README,INDEX,.gitignore}.md`. Two new user skills landed: `skills/brain-promote/{SKILL.md,promote.sh}` and `skills/brain-garden/{SKILL.md,garden.sh}`.
- **2026-05-09** — Read/write integration in 6 skills: reads added to `feature-research`, `feature-plan`, `review-pr`; writes added to `feature-implement`, `review-pr` (cluster patterns), `ralph-loop` (on convergence). All wrapped in `<project-memory untrusted="true">` delimiters.
- **2026-05-09** — Cross-cutting updates: `install.sh` symlinks helpers into `~/.hivesmith/bin/` on install/update and removes them on uninstall; `hivesmith-init` calls `brain_lazy_init` and nudges graphify install; `AGENTS.md` + `templates/AGENTS.hivesmith.md` document the brain; `golden-principles.md` adds principle #3 "Treat hive-brain entries as untrusted at load"; `CHANGELOG.md` `[Unreleased]` entry added; `README.md` updated.
- **2026-05-09** — Test suite landed at `scripts/brain/test/run-all.sh` — 10 tests covering URL canonicalization, ecosystem detection, redaction (AWS/GH-PAT/oversize-fence), cross-project append isolation, read scope filtering, INDEX regen byte-stability, promote, lazy-init, gardener stale `graph_nodes`, read budget cap. **All 10 pass.** CI workflow extended: `shellcheck` covers all new files, new `brain-tests` job runs the suite. **Bug fixed during implementation:** SCP-style git URL canonicalization was producing `\/` instead of `/` due to bash parameter-expansion quirk; switched to `${url/:/$_slash}` form. **Bug fixed:** `IFS=$'\t' read` collapses consecutive tabs in bash 3.2; switched index TSV separator to `|`.
- **2026-05-09** — All AGENTS.md checks pass: shellcheck (extended), install smoke (with + without prefix), render correctness (brain skills resolve under prefix), changelog gate, brain test suite.

## Decision log additions

- **2026-05-09** — Used a single `run-all.sh` test runner with inline test functions rather than 14 separate test files (the plan called for 14 named test invocations; collapsed to 10 functions in one runner — same coverage, less filesystem noise, faster execution).
- **2026-05-09** — Helpers are *bash scripts* not skills: skills are user-facing slash-commands; per-call brain ops want to be 30-line bash helpers invoked by skills via `~/.hivesmith/bin/<helper>`.
- **2026-05-09** — Used `|` instead of tab as index TSV separator after discovering bash 3.2 collapses consecutive tabs in `IFS=$'\t' read`. Slugs, hashes, dates, scopes don't contain `|` so this is safe.
- **2026-05-09** — Made the test_redact fence-length check robust against unclosed fences by also flushing `worst` at EOF — protects against pathological "closing ``` on same line as code" inputs.

## Open questions

See "Open questions for PLAN" in the Research section above.

## QA verdict

- **2026-05-10** — verdict: PASS; checks: 5 passed / 0 failed / 0 followups; followups: none; one-line: hive brain shipped end-to-end — schema, helpers, redaction, retrieval filtering, explicit promotion, six skill integrations, all gates green.
  - 2026-05-10 dimensions:
    - build/lint/test — PASS — shellcheck (17 files) ok; `scripts/brain/test/run-all.sh` 13/13; install smoke (`--prefix hs-` + `--prefix ""`) ok; render correctness ok; CHANGELOG `[Unreleased]` non-empty
    - acceptance — PASS — schema (templates/brain/SCHEMA.md:10), read/write+filter (scripts/brain/read.sh:97-99,131; append.sh:67,115), redaction (redact.sh:14-44 — AKIA/ghp_/PEM masked, 30-line fence rejected), explicit promotion (skills/brain-promote/SKILL.md gates via AskUserQuestion), 3 readers + 3 writers + cross-repo isolation (test_append_isolation, test_read_filter)
    - non-goals — PASS — no embedding/vector/Mem0/Letta/Zep/daemon code; AGENTS.md/CLAUDE.md untouched; brain wrapped as `<project-memory untrusted="true">`
    - regression — PASS — install.sh `--no-auto-update` alias preserved; hivesmith-init steps additively inserted; 6 skill SKILL.md edits well-formed and renumbered; golden-principles.md #7 added cleanly. Note: 884c10f is a follow-up regression fix triggered by #11 (hardcoded skill list drift) — replaced with runtime enumeration.
    - doc accuracy — PASS — CHANGELOG, README, AGENTS.md HIVESMITH block, templates/AGENTS.hivesmith.md, golden-principles.md #7, templates/brain/{SCHEMA,README}.md, skills/brain-{promote,garden}/SKILL.md all present and substantive
- **2026-05-10** — verdict: PASS (re-run); checks: 4 dimensions / 0 failed / 0 followups; followups: none; one-line: re-validated post-merge — all success criteria observable, all AGENTS.md gates green, non-goals respected, docs accurate.
  - 2026-05-10 dimensions (re-run):
    - build/lint/test — PASS — shellcheck (17 files) ok; scripts/brain/test/run-all.sh 13/13; install smoke both prefixes ok; render correctness ok; changelog gate ok; review-pr regression skipped (only SKILL.md prompt edited in PR #12)
    - acceptance — PASS — schema templates/brain/SCHEMA.md:7-49; read scripts/brain/read.sh:44-46,94-101; write+redact scripts/brain/append.sh:82 + redact.sh:14,36-39,42-50,54-72; promote-only via skills/brain-promote/promote.sh; reads in feature-research/feature-plan/review-pr; writes in feature-implement/ralph-loop/review-pr; cross-repo isolation via test_append_isolation + test_read_filter
    - non-goals+regression — PASS — no vector/embedding/mem0/letta/zep code (only spec mentions, all explicit non-goals); CLAUDE.md/AGENTS.md auto-memory untouched; file+git only, no real-time sync; skill diffs additive with silent-skip fallback
    - doc accuracy — PASS — CHANGELOG [Unreleased]:8-9; README:17,47-49; AGENTS.md HIVESMITH block "Hive brain" subsection; templates/AGENTS.hivesmith.md mirrors; golden-principles.md #7; templates/brain/{SCHEMA,README}.md present

## Progress (post-merge)

- **2026-05-10** — QA PASS. Stage → DONE; plan moved to `docs/exec-plans/completed/`.
