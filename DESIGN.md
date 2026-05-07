# DESIGN.md

Top-level design overview. The *shape* of this project: domains, layers, cross-cutting concerns, and the architectural rules that hold everything together.

Per-decision detail belongs in `docs/design-docs/`. This file is the map.

## Domains

<List the business domains. One paragraph each. Example:>

- **App settings** — user preferences, feature flags, per-account configuration.
- **<...>**

## Layers

<If the project enforces a layered architecture, document it here. Example:>

```
Types → Config → Repo → Service → Runtime → UI
```

- **Types** — pure data shapes, no logic.
- **Config** — typed configuration, no I/O.
- **Repo** — persistence boundary.
- **Service** — domain logic.
- **Runtime** — wiring, processes, scheduling.
- **UI** — anything user-facing.

Dependency direction is one-way through this list. Cross-domain dependencies go through `Providers`.

## Cross-cutting concerns

<auth, telemetry, feature flags, connectors. Each one enters through a single explicit interface — name it and link to it.>

## Hard rules

<Architectural invariants that should be mechanically enforced. Each rule should ideally have a custom lint that emits a remediation message.>

- <Rule>
- <Rule>
