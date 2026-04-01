#!/usr/bin/env bash
# Codex CLI tmux window title updater.
# Receives JSON via stdin from Codex hook events and updates the tmux window title.
# Also supports --restore for manual cleanup.

set -euo pipefail

TITLE_WIDTH=18
TITLE_GENERATOR_MODEL="gpt-5.4-mini"
TITLE_GENERATOR_GUARD="CODEX_TMUX_TITLE_DISABLE"

continue_hook() {
  echo '{"continue": true}'
  exit 0
}

clean_text() {
  echo "$1" | tr '\n' ' ' | sed 's/  */ /g' | sed 's/^ *//;s/ *$//'
}

fixed_width() {
  local text="$1"
  local width="$2"
  local len=${#text}

  if [[ $len -gt $width ]]; then
    echo "${text:0:$((width-2))}.."
  elif [[ $len -lt $width ]]; then
    local pad=$((width - len))
    printf "%s%*s" "$text" "$pad" ""
  else
    echo "$text"
  fi
}

fallback_title() {
  local prompt="$1"
  local cleaned

  cleaned=$(clean_text "$prompt" | sed 's/[^[:alnum:][:space:]-]/ /g' | sed 's/  */ /g')
  cleaned=$(echo "$cleaned" | awk '{print $1, $2, $3, $4}' | sed 's/  */ /g' | sed 's/^ *//;s/ *$//')

  if [[ -z "$cleaned" ]]; then
    cleaned="Codex Task"
  fi

  echo "$cleaned"
}

generate_title_with_codex() {
  local prompt="$1"
  local dir="$2"
  local prompt_file output_file title=""

  prompt_file=$(mktemp)
  output_file=$(mktemp)

  cat >"$prompt_file" <<EOF
Write a tmux window title for an active coding session.

Requirements:
- Return only the title text.
- 2 to 4 words.
- Clear and specific to the work being done.
- No quotes or surrounding punctuation.
- Prefer plain ASCII.
- Max 18 characters if possible.

User prompt:
$prompt
EOF

  if env "$TITLE_GENERATOR_GUARD"=1 codex exec - \
    -c features.codex_hooks=false \
    -m "$TITLE_GENERATOR_MODEL" \
    --skip-git-repo-check \
    --json \
    --color never \
    --sandbox read-only \
    -C "$dir" \
    -o "$output_file" \
    <"$prompt_file" \
    >/dev/null 2>&1; then
    title=$(clean_text "$(cat "$output_file" 2>/dev/null || true)")
  fi

  rm -f "$prompt_file" "$output_file"

  echo "$title"
}

if [[ "${1:-}" == "--restore" ]]; then
  if [[ -z "${TMUX_PANE:-}" ]]; then
    exit 0
  fi
  WINDOW_ID=$(tmux display-message -p -t "$TMUX_PANE" '#I' 2>/dev/null || true)
  if [[ -z "$WINDOW_ID" ]]; then
    exit 0
  fi
  AUTO_RENAME=$(tmux show-window-option -t "$WINDOW_ID" -v @codex_auto_rename 2>/dev/null || true)
  if [[ -n "$AUTO_RENAME" ]]; then
    tmux set-window-option -t "$WINDOW_ID" automatic-rename "$AUTO_RENAME" 2>/dev/null || true
  else
    tmux set-window-option -t "$WINDOW_ID" automatic-rename on 2>/dev/null || true
  fi
  tmux set-window-option -t "$WINDOW_ID" -u @codex_base_title 2>/dev/null || true
  tmux set-window-option -t "$WINDOW_ID" -u @codex_auto_rename 2>/dev/null || true
  exit 0
fi

if [[ "${!TITLE_GENERATOR_GUARD:-}" == "1" ]]; then
  continue_hook
fi

INPUT=$(cat)
HOOK_EVENT=$(echo "$INPUT" | jq -r '.hook_event_name // empty')
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
PROMPT=$(echo "$INPUT" | jq -r '.prompt // empty')

if [[ "$HOOK_EVENT" != "UserPromptSubmit" ]]; then
  continue_hook
fi

if [[ -z "${TMUX_PANE:-}" ]]; then
  continue_hook
fi

DIR="${CWD:-$PWD}"
CLEAN_PROMPT=$(clean_text "$PROMPT")

if [[ -z "$CLEAN_PROMPT" ]]; then
  continue_hook
fi

TITLE=$(generate_title_with_codex "$CLEAN_PROMPT" "$DIR")
if [[ -z "$TITLE" ]]; then
  TITLE=$(fallback_title "$CLEAN_PROMPT")
fi

TITLE=$(clean_text "$TITLE" | sed 's/^["'"'"'[:space:]]*//;s/["'"'"'[:space:]]*$//')
FINAL_TITLE=$(fixed_width "$TITLE" "$TITLE_WIDTH")

WINDOW_ID=$(tmux display-message -p -t "$TMUX_PANE" '#I' 2>/dev/null || true)
if [[ -n "$WINDOW_ID" ]]; then
  if [[ -z "$(tmux show-window-option -t "$WINDOW_ID" -v @codex_auto_rename 2>/dev/null)" ]]; then
    AUTO_RENAME=$(tmux show-window-option -t "$WINDOW_ID" -v automatic-rename 2>/dev/null || echo "on")
    tmux set-window-option -t "$WINDOW_ID" @codex_auto_rename "$AUTO_RENAME" 2>/dev/null || true
  fi
  tmux set-window-option -t "$WINDOW_ID" automatic-rename off 2>/dev/null || true
  tmux set-window-option -t "$WINDOW_ID" @codex_base_title "$FINAL_TITLE" 2>/dev/null || true
  tmux rename-window -t "$WINDOW_ID" "$FINAL_TITLE" 2>/dev/null || true
fi

continue_hook
