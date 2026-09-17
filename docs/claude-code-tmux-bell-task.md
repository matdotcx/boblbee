# Task: wire a Claude Code attention signal into boblbee

## Goal

When Claude Code runs inside a tmux window, the window should flag itself in the
tmux status bar the moment Claude finishes a task or pauses for a permission
prompt — so I can work in another window and glance back when I'm needed. This
behaviour must persist across the whole fleet via boblbee, not just this host.

## How it works (so the changes make sense)

tmux's `monitor-bell` flags a background window when that window receives a
terminal bell (BEL). Claude Code only emits a BEL when its notification channel
is set to `terminal_bell`; its default desktop notification on Ghostty/Kitty/
iTerm2 is a different escape sequence that will **not** trip `monitor-bell`.
Inside tmux the bell also needs `allow-passthrough` to escape to the outer
terminal. So there are two coordinated changes:

1. **tmux** — fleet-synced via `assets/tmux-base.conf`.
2. **Claude Code** — `preferredNotifChannel: "terminal_bell"` in
   `~/.claude/settings.json`, which also needs to persist across the fleet.

## Repo facts

- Path: `~/Developer/workspace/matdotcx/boblbee`, default branch `gold`.
- Shared cross-host tmux settings: `assets/tmux-base.conf`.
  Main config: `assets/tmux.conf`. Themes: `assets/tmux-theme-*.conf`.
- Sync model: copy-not-symlink, newest-mtime-wins across home/repo/iCloud.
- Sync commands: `bb-sync-tmux`, `bb-sync-claude`, `bb-sync-fleet`.
  Fleet host list: `hosts/elements.txt`.
- Commits are GPG-signed automatically.

**Read each file before editing it. Make every edit idempotent so re-running is
safe. Do not run anything destructive.**

## Step 1 — tmux config

Edit `assets/tmux-base.conf`. If a block with the marker comment
`# --- Claude Code attention signal` already exists, update it in place rather
than appending a duplicate. Otherwise add:

```bash
# --- Claude Code attention signal -----------------------------------------
# Let Claude Code's bell (and its notifications/progress) escape tmux
set -g allow-passthrough on

# When a background window rings the bell, flag it in the status bar
# instead of beeping or printing a message
set -g monitor-bell on
set -g bell-action other
set -g visual-bell off
set -g window-status-bell-style 'fg=red,bold'
# --------------------------------------------------------------------------
```

Conflict check before committing: grep `assets/tmux.conf` and
`assets/tmux-theme-*.conf` for `window-status-bell-style`, `monitor-bell`,
`visual-bell`, and `allow-passthrough`. Work out the source order in
`assets/tmux.conf` (which files it sources, in what order). If a theme file sets
`window-status-bell-style` *after* `tmux-base.conf` is sourced, the theme will
win — in that case move the `window-status-bell-style` line into the theme
file(s) instead, using the theme's existing palette/convention rather than
hard-coding red, and keep only the behavioural toggles in `tmux-base.conf`.

## Step 2 — Claude Code setting (this host)

Set `preferredNotifChannel` to `terminal_bell`, merging into any existing
settings rather than overwriting (the file may already hold `hooks`, `env`, etc.):

```bash
mkdir -p ~/.claude
f=~/.claude/settings.json
[ -f "$f" ] || echo '{}' > "$f"
tmp=$(mktemp)
jq '.preferredNotifChannel = "terminal_bell"' "$f" > "$tmp" && mv "$tmp" "$f"
jq . "$f" >/dev/null && echo "settings.json valid"
```

## Step 3 — make the Claude setting persist across the fleet

Add `~/.claude/settings.json` to boblbee's sync so the bell channel rides out to
every host, following the existing dotfile conventions.

First inspect what's already there: `scripts/claude.sh`, any
`scripts/*claude*sync*.sh`, `scripts/lib/lib.sh` (the `sync_dotfile()` helper),
`scripts/lib/config.sh`, and `assets/`. Note the existing Claude integration
syncs `claude/memory/user.md` to `~/.config/claude/memory/` — a *different* file
at a *different* path — so settings.json is not yet covered.

Then:

1. **Seed the canonical asset from this host's current file.** After Step 2,
   `~/.claude/settings.json` holds the correct content (existing keys plus
   `preferredNotifChannel`). Copy it to a tracked asset, e.g.
   `assets/claude-settings.json`. Seed it this way rather than hand-authoring
   keys: settings.json is schema-validated, and keys that actually belong in
   `~/.claude.json` (theme, `editorMode`, MCP servers, OAuth state) are silently
   rejected if placed in settings.json. Copying the live, already-valid file
   avoids that footgun.

2. **Wire up the sync.** Prefer folding settings.json into the existing Claude
   sync surface (`claude.sh` / `bb-sync-claude`) alongside the memory file, so
   there is a single "Claude" sync command — mirror how the memory file is
   handled, but use the standard `sync_dotfile()` newest-mtime-wins helper that
   `zshrc-sync.sh` uses, mapping `assets/claude-settings.json` <-> 
   `~/.claude/settings.json`. If `claude.sh`'s structure makes a separate
   `claude-settings-sync.sh` cleaner, do that instead and add a matching
   `bb-sync-*` alias. Wire the step into `scripts/index.sh` in both the macOS
   and Ubuntu sequences, next to the existing Claude step.

3. **Validate.** Confirm the asset is valid JSON: `jq . assets/claude-settings.json`.

Reconciliation warning: under newest-mtime-wins, the first `bb-sync-fleet` after
this will push the canonical settings.json onto each host, overwriting that
host's user-scope `~/.claude/settings.json`. That is the intent for a uniform
fleet, but if any host has user-scope settings worth keeping, reconcile them into
`assets/claude-settings.json` before running the fleet sync. Per-project and
machine-local overrides belong in `.claude/settings.json` /
`.claude/settings.local.json`, which sit *above* user settings in precedence and
are never touched by this sync — so this only sets the global default and leaves
project-specific work alone.

## Step 4 — commit and propagate

```bash
cd ~/Developer/workspace/matdotcx/boblbee
git add assets/tmux-base.conf assets/claude-settings.json   # plus any theme/sync/index files you changed
git commit -m "tmux+claude: flag tmux window on Claude Code attention bell"
git push

bb-sync-tmux        # applies the tmux change on this host
bb-sync-claude      # applies the settings.json change on this host
bb-sync-fleet       # pull + sync across every host in hosts/elements.txt
```

`bb-sync-fleet` updates files on each host but will not reload tmux servers
already running there; reload with `tmux source-file ~/.tmux.conf` where needed,
or the change applies to new sessions.

## Step 5 — verify

```bash
tmux show-options -g  | grep -E 'allow-passthrough|monitor-bell|bell-action|visual-bell'
tmux show-options -gw | grep 'window-status-bell-style'
jq .preferredNotifChannel ~/.claude/settings.json        # expect "terminal_bell"
jq .preferredNotifChannel assets/claude-settings.json    # canonical asset matches
```

After `bb-sync-fleet`, spot-check one other host (e.g. over SSH) that its
`~/.claude/settings.json` now reports `terminal_bell` too.

Functional test: in a tmux session, start Claude Code in one window, switch to
another window, and give Claude a task. When it finishes or asks permission, the
Claude window should turn red in the status bar.

## Notes / constraints

- `allow-passthrough` needs tmux 3.3 or newer (current macOS and Ubuntu 24.04
  hosts are fine).
- Keep British English in any comments; no emojis.
