#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
HOOK_SCRIPT="$SCRIPT_DIR/../hooks/codex-tmux-title.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  if [[ "$haystack" != *"$needle"* ]]; then
    fail "expected to find [$needle] in [$haystack]"
  fi
}

assert_file_empty() {
  local file="$1"
  if [[ -s "$file" ]]; then
    fail "expected [$file] to be empty"
  fi
}

run_test() {
  local name="$1"
  shift
  echo "test: $name"
  "$@"
}

make_fakebin() {
  local dir="$1"

  cat >"$dir/tmux" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
LOG_FILE=${TMUX_LOG_FILE:?}
printf 'tmux %s\n' "$*" >>"$LOG_FILE"
case "${1:-}" in
  display-message)
    printf '%s\n' "${FAKE_TMUX_WINDOW_ID:-3}"
    ;;
  show-window-option)
    if [[ "${*: -1}" == "@codex_auto_rename" ]]; then
      printf '%s\n' "${FAKE_TMUX_AUTO_RENAME:-}"
    elif [[ "${*: -1}" == "automatic-rename" ]]; then
      printf '%s\n' "${FAKE_TMUX_AUTOMATIC_RENAME:-on}"
    fi
    ;;
  set-window-option|rename-window)
    ;;
esac
EOF
  chmod +x "$dir/tmux"

  cat >"$dir/codex" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
LOG_FILE=${CODEX_LOG_FILE:?}
printf 'codex %s\n' "$*" >>"$LOG_FILE"
printf 'HOME=%s\n' "${HOME:-}" >>"$LOG_FILE"
if [[ -f "${HOME:-}/.codex/config.toml" ]]; then
  printf -- '--- config.toml ---\n' >>"$LOG_FILE"
  cat "${HOME}/.codex/config.toml" >>"$LOG_FILE"
fi
OUTPUT_FILE=""
while (($#)); do
  case "$1" in
    -o|--output-last-message)
      shift
      OUTPUT_FILE="$1"
      ;;
  esac
  shift || true
done

if [[ "${FAKE_CODEX_FAIL:-0}" == "1" ]]; then
  exit 23
fi

if [[ -n "$OUTPUT_FILE" ]]; then
  printf '%s\n' "${FAKE_CODEX_OUTPUT:-Hook Title}" >"$OUTPUT_FILE"
fi

printf '{"type":"message","role":"assistant"}\n'
EOF
  chmod +x "$dir/codex"
}

test_user_prompt_submit_generates_short_title() {
  local tmpdir
  tmpdir=$(mktemp -d)
  local cleanup_cmd="rm -rf '$tmpdir'"
  trap "$cleanup_cmd" RETURN

  local fakebin="$tmpdir/fakebin"
  mkdir -p "$fakebin"
  make_fakebin "$fakebin"

  local tmux_log="$tmpdir/tmux.log"
  local codex_log="$tmpdir/codex.log"
  local home_dir="$tmpdir/home"
  mkdir -p "$home_dir/.codex"
  printf 'test-auth\n' >"$home_dir/.codex/auth.json"
  : >"$tmux_log"
  : >"$codex_log"

  local output
  output=$(
    PATH="$fakebin:$PATH" \
    TMUX_PANE="%9" \
    TMUX_LOG_FILE="$tmux_log" \
    CODEX_LOG_FILE="$codex_log" \
    FAKE_CODEX_OUTPUT="Hook Focus" \
    HOME="$home_dir" \
    "$HOOK_SCRIPT" <<'EOF'
{"hook_event_name":"UserPromptSubmit","cwd":"/tmp/example","prompt":"change tmux title hook to use codex exec summaries"}
EOF
  )

  assert_contains "$output" '"continue": true'
  assert_contains "$(cat "$codex_log")" 'codex exec'
  assert_contains "$(cat "$codex_log")" 'HOME='
  assert_contains "$(cat "$codex_log")" 'gpt-5.4-mini'
  assert_contains "$(cat "$codex_log")" 'codex_hooks = false'
  assert_contains "$(cat "$codex_log")" 'model_reasoning_effort = "low"'
  if [[ "$(cat "$codex_log")" == *"HOME=$home_dir"* ]]; then
    fail "expected codex to run in a temporary bare HOME, not [$home_dir]"
  fi
  assert_contains "$(cat "$tmux_log")" 'tmux rename-window -t 3 Hook Focus'
}

test_non_prompt_events_do_nothing() {
  local tmpdir
  tmpdir=$(mktemp -d)
  local cleanup_cmd="rm -rf '$tmpdir'"
  trap "$cleanup_cmd" RETURN

  local fakebin="$tmpdir/fakebin"
  mkdir -p "$fakebin"
  make_fakebin "$fakebin"

  local tmux_log="$tmpdir/tmux.log"
  local codex_log="$tmpdir/codex.log"
  : >"$tmux_log"
  : >"$codex_log"

  local output
  output=$(
    PATH="$fakebin:$PATH" \
    TMUX_PANE="%9" \
    TMUX_LOG_FILE="$tmux_log" \
    CODEX_LOG_FILE="$codex_log" \
    "$HOOK_SCRIPT" <<'EOF'
{"hook_event_name":"PostToolUse","cwd":"/tmp/example","prompt":"ignored"}
EOF
  )

  assert_contains "$output" '"continue": true'
  assert_file_empty "$tmux_log"
  assert_file_empty "$codex_log"
}

test_nested_codex_guard_skips_generation() {
  local tmpdir
  tmpdir=$(mktemp -d)
  local cleanup_cmd="rm -rf '$tmpdir'"
  trap "$cleanup_cmd" RETURN

  local fakebin="$tmpdir/fakebin"
  mkdir -p "$fakebin"
  make_fakebin "$fakebin"

  local tmux_log="$tmpdir/tmux.log"
  local codex_log="$tmpdir/codex.log"
  : >"$tmux_log"
  : >"$codex_log"

  local output
  output=$(
    PATH="$fakebin:$PATH" \
    TMUX_PANE="%9" \
    TMUX_LOG_FILE="$tmux_log" \
    CODEX_LOG_FILE="$codex_log" \
    CODEX_TMUX_TITLE_DISABLE=1 \
    "$HOOK_SCRIPT" <<'EOF'
{"hook_event_name":"UserPromptSubmit","cwd":"/tmp/example","prompt":"ignored"}
EOF
  )

  assert_contains "$output" '"continue": true'
  assert_file_empty "$tmux_log"
  assert_file_empty "$codex_log"
}

run_test "UserPromptSubmit generates short title" test_user_prompt_submit_generates_short_title
run_test "Other hook events do nothing" test_non_prompt_events_do_nothing
run_test "Nested codex guard skips generation" test_nested_codex_guard_skips_generation

echo "PASS"
