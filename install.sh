#!/usr/bin/env bash
# Install VillageSQL skills for all detected AI coding agents.
# Supports: Claude Code, OpenAI Codex, Cursor, Amp, Gemini CLI, Antigravity, Kiro
#
# Usage:
#   curl -sSL https://raw.githubusercontent.com/villagesql/villagesql-skills/main/install.sh | bash
#
# Env vars (optional):
#   VILLAGESQL_SKILLS_SRC  Local clone of villagesql-skills repo
#                          (default: ~/.local/share/villagesql-skills)
#   CLAUDE_SKILLS_DIR      Override Claude Code skills path
#                          (default: ~/.claude/skills)

set -euo pipefail

REPO_URL="https://github.com/villagesql/villagesql-skills.git"
SRC_DIR="${VILLAGESQL_SKILLS_SRC:-$HOME/.local/share/villagesql-skills}"

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

# Install all skills into a target directory via symlinks.
# $1 = target skills dir, $2 = agent label for output
install_to() {
  local dir="$1" label="$2"
  local n_installed=0 n_skipped=0
  mkdir -p "$dir"
  for skill_dir in "$SRC_DIR"/skills/*/; do
    skill_name=$(basename "${skill_dir%/}")
    [ -f "$skill_dir/SKILL.md" ] || continue
    target="$dir/$skill_name"
    if [ -e "$target" ] && [ ! -L "$target" ]; then
      n_skipped=$((n_skipped + 1))
      continue
    fi
    ln -sfn "${skill_dir%/}" "$target"
    n_installed=$((n_installed + 1))
  done
  printf "  %-28s %d installed" "$label" "$n_installed"
  [ "$n_skipped" -gt 0 ] && printf ", %d skipped (non-symlink exists)" "$n_skipped"
  echo
}

# Install the repo as an extension/plugin by symlinking the repo root.
# $1 = target path (the symlink to create), $2 = agent label for output
install_extension_to() {
  local target="$1" label="$2"
  mkdir -p "$(dirname "$target")"
  if [ -e "$target" ] && [ ! -L "$target" ]; then
    printf "  %-28s skipped (non-symlink exists)\n" "$label"
    return
  fi
  ln -sfn "$SRC_DIR" "$target"
  printf "  %-28s installed\n" "$label"
}

has_cmd() { command -v "$1" >/dev/null 2>&1; }
has_dir() { [ -d "$1" ]; }

echo
echo "Detecting agents..."
echo

agents_found=0

# Claude Code
if has_cmd claude || has_dir "$HOME/.claude"; then
  install_to "${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}" "Claude Code"
  agents_found=$((agents_found + 1))
fi

# OpenAI Codex + Cursor (share ~/.agents/skills/)
if has_cmd codex || has_dir "$HOME/.codex" || has_cmd cursor || has_dir "$HOME/.cursor"; then
  install_to "$HOME/.agents/skills" "Codex / Cursor"
  agents_found=$((agents_found + 1))
fi

# Amp
if has_cmd amp || has_dir "$HOME/.config/agents"; then
  install_to "$HOME/.config/agents/skills" "Amp"
  agents_found=$((agents_found + 1))
fi

# Gemini CLI (detect by command; dir alone is ambiguous with Antigravity)
if has_cmd gemini; then
  install_extension_to "$HOME/.gemini/extensions/villagesql" "Gemini CLI"
  agents_found=$((agents_found + 1))
fi

# Antigravity (agy) — replaced Gemini CLI; uses ~/.gemini/antigravity-cli/plugins/
if has_cmd agy; then
  install_extension_to "$HOME/.gemini/antigravity-cli/plugins/villagesql" "Antigravity (agy)"
  agents_found=$((agents_found + 1))
fi

# Kiro
if has_cmd kiro || has_dir "$HOME/.kiro"; then
  install_to "$HOME/.kiro/skills" "Kiro"
  agents_found=$((agents_found + 1))
fi

echo
if [ "$agents_found" -eq 0 ]; then
  echo "No supported agents detected."
  echo "Supported: Claude Code, OpenAI Codex, Cursor, Amp, Gemini CLI, Antigravity, Kiro"
  exit 1
fi

echo "Done. Restart any running agents to pick up new skills."
