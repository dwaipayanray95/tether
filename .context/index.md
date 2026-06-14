# Context Mode Index

This directory provides **Project Context Mode** files for MCP‑enabled agents. Each file contains concise, well‑structured documentation that the MCP server can index and serve on demand.

## Available Files

- [hard‑rules.md](hard-rules.md) – Critical project constraints.
- [project‑structure.md](project-structure.md) – Directory layout and major components.
- [database‑schemas.md](database-schemas.md) – Firestore and RTDB schemas (with deprecation notes).
- [feature‑map.md](feature-map.md) – Mapping of UI/features to source files.
- [key‑constants.md](key-constants.md) – Core constants, colors, notification channels.
- [removed‑features.md](removed-features.md) – Log of features removed from the codebase and notification discrepancies.

Agents can reference any of these files directly via the MCP `@` syntax (e.g., `@hard-rules.md`). The MCP server will return the file content as part of the model prompt, keeping token usage minimal.
