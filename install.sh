#!/usr/bin/env bash
# Install VillageSQL Claude Code skills.
#
# Usage:
#   curl -sSL https://raw.githubusercontent.com/villagesql/villagesql-skills/main/install.sh | sh
#
# Env vars (optional):
#   VILLAGESQL_SKILLS_SRC  Where to clone the source repo
#                          (default: ~/.local/share/villagesql-skills)
#   CLAUDE_SKILLS_DIR      Where to symlink skills
#                          (default: ~/.claude/skills)

set -euo pipefail

REPO_URL="https://github.com/villagesql/villagesql-skills.git"
SRC_DIR="${VILLAGESQL_SKILLS_SRC:-$HOME/.local/share/villagesql-skills}"
SKILLS_DIR="${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}"

if ! command -v git >/dev/null 2>&1; then
  echo "Error: git is required but not installed." >&2
  exit 1
fi

if [ -d "$SRC_DIR/.git" ]; then
  echo "Updating $SRC_DIR..."
  git -C "$SRC_DIR" pull --ff-only
else
  echo "Cloning into $SRC_DIR..."
  mkdir -p "$(dirname "$SRC_DIR")"
  git clone "$REPO_URL" "$SRC_DIR"
fi

mkdir -p "$SKILLS_DIR"

installed=0
skipped=0
for skill_dir in "$SRC_DIR"/skills/*/; do
  skill_name=$(basename "${skill_dir%/}")
  if [ ! -f "$skill_dir/SKILL.md" ]; then
    continue
  fi
  target="$SKILLS_DIR/$skill_name"
  if [ -e "$target" ] && [ ! -L "$target" ]; then
    echo "  skip: $skill_name (target exists and is not a symlink)"
    skipped=$((skipped + 1))
    continue
  fi
  ln -sfn "${skill_dir%/}" "$target"
  echo "  installed: $skill_name"
  installed=$((installed + 1))
done

echo
echo "Done. $installed skill(s) installed, $skipped skipped."
echo "Restart Claude Code if it's running."
