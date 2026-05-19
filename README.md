# villagesql-skills

Agent skills for VillageSQL.

## Skills

- [`vsql-extension-builder/`](skills/vsql-extension-builder/SKILL.md) — End-to-end
  builder for VillageSQL extensions. Seven-phase persona-driven workflow:
  requirements, feasibility, scaffold, implementation, CTO review, UAT, and
  documentation. Discovers the current VEF API from live SDK headers — no
  hardcoded API names.

## Layout

Each skill lives in its own directory:

```
<skill-name>/
├── SKILL.md           # entry point — frontmatter, workflow, gates
└── references/        # detailed material loaded on demand
    └── *.md
```

`SKILL.md` stays thin and procedural. Detail-heavy material (standards,
checklists, environment commands, capability discovery) lives in
`references/` and is read only when the relevant phase needs it.
