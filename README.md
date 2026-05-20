# villagesql-skills

Agent skills for working with [VillageSQL](https://villagesql.com). These
skills run inside [Claude Code](https://claude.com/claude-code) and other
agent runtimes that support the
[Agent Skills](https://docs.claude.com/en/docs/claude-code/skills) format.

## Skills

| Skill | What it does |
|---|---|
| [`vsql-extension-builder`](skills/vsql-extension-builder/) | Builds a VillageSQL extension end-to-end through a 7-phase persona-driven workflow. Discovers the current VEF API from live SDK headers — no hardcoded API names. |

More skills will be added here over time.

## Installing

### Quick install

```bash
curl -sSL https://villagesql.com/skills | bash
```

Clones the repo to `~/.local/share/villagesql-skills` and symlinks every
skill into `~/.claude/skills/`. Re-running updates in place.

Override locations with env vars:

```bash
VILLAGESQL_SKILLS_SRC=~/code/villagesql-skills \
CLAUDE_SKILLS_DIR=~/.claude/skills \
  curl -sSL https://villagesql.com/skills | bash
```

### Manual install (recommended for contributors)

```bash
git clone https://github.com/villagesql/villagesql-skills.git ~/code/villagesql-skills
mkdir -p ~/.claude/skills
ln -s ~/code/villagesql-skills/skills/vsql-extension-builder ~/.claude/skills/vsql-extension-builder
```

Verify the skill is loaded by typing `/` in Claude Code — the skill name
should appear in the slash command list.

To update later:

```bash
git -C ~/code/villagesql-skills pull
```

## Skill layout

Each skill follows the standard Agent Skills directory layout:

```
skills/
└── <skill-name>/
    ├── SKILL.md           # entry point — frontmatter, workflow, gates
    └── references/        # detailed material loaded on demand
        └── *.md
```

`SKILL.md` is loaded eagerly when the skill triggers and stays thin and
procedural. Detail-heavy material (standards, checklists, environment
commands) lives in `references/` and is read by the agent only when the
relevant phase needs it.

## Contributing

Issues and pull requests welcome. For substantive changes — new skills,
workflow restructuring, new references — open an issue first to discuss the
shape before writing the skill.

A few conventions:

- Keep `SKILL.md` thin. If a section exceeds a screen, ask whether it
  belongs in `references/` instead.
- Reference files describe **process and principles**, not specific API
  names — names should be discovered from live sources during the
  workflow, not hardcoded in the skill.
- Match the voice of existing skills: terse, imperative, no marketing
  language.

## License

Apache-2.0 — see [`LICENSE`](LICENSE).

## Links

- VillageSQL: <https://villagesql.com>
- Documentation: <https://villagesql.com/docs>
- Discord: <https://discord.gg/KSr6whd3Fr>
