#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT="$SCRIPT_DIR/.."
INSTALL_SCRIPT="$REPO_ROOT/bin/install.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_file_exists() {
  local file="$1"
  [[ -f "$file" ]] || fail "expected file [$file] to exist"
}

assert_json_equals() {
  local expr="$1"
  local expected="$2"
  local file="$3"
  local actual
  actual=$(jq -r "$expr" "$file")
  [[ "$actual" == "$expected" ]] || fail "expected [$expr] to be [$expected], got [$actual]"
}

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

fake_home="$tmpdir/home"
mkdir -p "$fake_home/.codex/hooks"

cat >"$fake_home/.codex/hooks.json" <<'EOF'
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "/tmp/old/codex-tmux-title.sh",
            "timeout": 5
          }
        ]
      }
    ],
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "/tmp/old/codex-tmux-title.sh",
            "timeout": 5
          }
        ]
      }
    ]
  }
}
EOF

HOME="$fake_home" CODEX_HOME="$fake_home/.codex" bash "$INSTALL_SCRIPT"

assert_file_exists "$fake_home/.codex/hooks/codex-tmux-title.sh"
assert_json_equals '.hooks.UserPromptSubmit[0].hooks[0].command' "$fake_home/.codex/hooks/codex-tmux-title.sh" "$fake_home/.codex/hooks.json"
assert_json_equals '.hooks.UserPromptSubmit[0].hooks[0].timeout' "15" "$fake_home/.codex/hooks.json"

session_len=$(jq '.hooks.SessionStart | length' "$fake_home/.codex/hooks.json")
[[ "$session_len" == "0" ]] || fail "expected SessionStart hooks to be scrubbed"

backup_count=$(find "$fake_home/.codex" -maxdepth 1 -name 'hooks.json.bak.*' | wc -l | tr -d ' ')
[[ "$backup_count" == "1" ]] || fail "expected one hooks.json backup, found [$backup_count]"

echo "PASS"
