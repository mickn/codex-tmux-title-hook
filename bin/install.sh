#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
HOOKS_DIR="$CODEX_HOME/hooks"
TARGET_SCRIPT="$HOOKS_DIR/codex-tmux-title.sh"
HOOKS_JSON="$CODEX_HOME/hooks.json"
BACKUP_SUFFIX=$(date +%Y%m%d%H%M%S)

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

require_cmd jq

mkdir -p "$HOOKS_DIR"
cp "$REPO_ROOT/hooks/codex-tmux-title.sh" "$TARGET_SCRIPT"
chmod +x "$TARGET_SCRIPT"

if [[ -f "$HOOKS_JSON" ]]; then
  cp "$HOOKS_JSON" "$HOOKS_JSON.bak.$BACKUP_SUFFIX"
else
  mkdir -p "$(dirname "$HOOKS_JSON")"
  printf '{\n  "hooks": {}\n}\n' >"$HOOKS_JSON"
fi

TMP_JSON=$(mktemp)

jq \
  --arg cmd "$TARGET_SCRIPT" \
  '
  def is_title_hook_command($cmd):
    (.command == $cmd) or ((.command // "") | test("(^|/)codex-tmux-title\\.sh$"));

  def scrub($cmd):
    map(
      if (.hooks? | type == "array") then
        .hooks |= map(select(is_title_hook_command($cmd) | not))
        | select((.hooks | length) > 0)
      else
        .
      end
    );

  def title_hook($cmd):
    {"type":"command","command":$cmd,"timeout":15};

  .hooks = (.hooks // {})
  | .hooks.SessionStart = ((.hooks.SessionStart // []) | scrub($cmd))
  | .hooks.PreToolUse = ((.hooks.PreToolUse // []) | scrub($cmd))
  | .hooks.PostToolUse = ((.hooks.PostToolUse // []) | scrub($cmd))
  | .hooks.Stop = ((.hooks.Stop // []) | scrub($cmd))
  | .hooks.UserPromptSubmit = (
      ((.hooks.UserPromptSubmit // []) | scrub($cmd)) as $existing
      | [{"hooks":[title_hook($cmd)]}] + $existing
    )
  ' "$HOOKS_JSON" >"$TMP_JSON"

mv "$TMP_JSON" "$HOOKS_JSON"

echo "Installed codex tmux title hook:"
echo "  script: $TARGET_SCRIPT"
echo "  hooks:  $HOOKS_JSON"
