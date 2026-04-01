# Codex tmux Title Hook

A small hook for the Codex CLI that renames the current tmux window based on the latest user prompt.

It runs only on `UserPromptSubmit`, asks Codex in non-interactive mode for a short session title, and writes that title into the active tmux window. The result is a compact label that stays focused on the task instead of flipping between tool states.

## What It Does

- Uses the submitted Codex prompt as the source of truth.
- Calls `codex exec -m gpt-5.4-mini` to summarize that prompt into a 2-4 word title.
- Disables nested Codex hooks during that summary call so the title generation does not recurse.
- Writes the title into the active tmux window and turns off tmux `automatic-rename` for that window.
- Leaves all non-`UserPromptSubmit` events alone.

## Requirements

- macOS or Linux
- `tmux`
- `bash`
- `jq`
- Codex CLI installed and working

## Install

### Option 1: clone and install

```bash
git clone https://github.com/mickn/codex-tmux-title-hook.git
cd codex-tmux-title-hook
./bin/install.sh
```

### Option 2: curl installer

```bash
curl -fsSL https://raw.githubusercontent.com/mickn/codex-tmux-title-hook/main/bin/install.sh | bash
```

The installer:

- copies `hooks/codex-tmux-title.sh` to `~/.codex/hooks/codex-tmux-title.sh`
- creates a backup of `~/.codex/hooks.json` if it already exists
- registers the hook only under `UserPromptSubmit`
- removes older registrations of the same hook from `SessionStart`, `PreToolUse`, `PostToolUse`, and `Stop`

## Installed Behavior

After install, your `~/.codex/hooks.json` will include a `UserPromptSubmit` hook that points at:

```json
"/Users/you/.codex/hooks/codex-tmux-title.sh"
```

The hook timeout is set to 15 seconds to allow the cheap summary call to finish cleanly.

## Uninstall

Remove the installed script:

```bash
rm -f ~/.codex/hooks/codex-tmux-title.sh
```

Then remove its entry from `~/.codex/hooks.json`, or restore the backup created by the installer.

## Test

```bash
bash tests/codex-tmux-title.test.sh
bash tests/install.test.sh
```

## Notes

- The nested title-generation call uses `gpt-5.4-mini` intentionally to keep it fast and cheap.
- The hook preserves a simple fallback title if the summary call fails.
- The repository ships the same shell test harness used to verify both the hook and the installer behavior.
