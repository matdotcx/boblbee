# Radon rebuild runbook

If radon (the desktop, standby console, and home of XO, KoboShelf and the vault clone) loses its home folder or dies: what comes back from where, and in what order. Written 17 Oct 2026, after a test of xenon's `cleanup-oct.sh` deleted `/Users/ops` on 15 Oct (xenon `docs/LEDGER.md`, radon table). Assumes helium, cobalt and deadline are up.

`scripts/rebuild-radon.sh` does everything below that needs no person; `--check` reports the state of each step without changing anything.

## 1. What comes back, and from where

| Thing | Where the copy lives | How it comes back |
|---|---|---|
| Desktop, Documents, Downloads, Pictures, Music | iCloud, and macOS privacy protection (they survived the 15 Oct deletion) | sign in to iCloud |
| SSH keys and `~/.ssh/config`, `known_hosts` | iCloud `Ark/Sync/System/.ssh`; ark-config `boblbee/*.age` | `ssh-sync.sh`; the script adds iCloud's `known_hosts` entries |
| SSH key passphrases | your vault (the login Keychain held them) | `ssh-add --apple-use-keychain`, once |
| Code under `Developer/workspace/matdotcx` | GitHub `matdotcx/*` | the script clones radon's repos; only unpushed work is lost |
| Dotfiles, Claude settings, hooks and memory | boblbee | the script's module step |
| node_exporter, log-trim, posture, boblbee self-update | boblbee | the script; node_exporter re-registers with helium |
| `~/vault`, its git-only deploy key, `~/vault-mirror.git` | deadline `vault.git`; the key escrowed in ark-config `boblbee/hosts/radon/` | boblbee's radon profile (needs `id_bootstrap`) |
| koboshelfd, the `koboshelf` tunnel, the Kobo's token | KoboShelf repo; token and tunnel credentials escrowed in ark-config `KoboShelf/` | KoboShelf `deploy/rebuild-host.sh` (needs `id_bootstrap`) |
| xo's push job | xo repo | the script |
| The cc box's pf anchor and LaunchDaemon (`/etc/pf.anchors/org.iaconelli.kohinoor`, `org.iaconelli.kohinoor.pf`) | outside the home folder: they survive | the script checks them (`kohinoor/cc.sh host`) |
| The cc box itself: start-at-login agent, image, volumes, tailnet identity | kohinoor repo; the volumes are in `~/Library` and are lost | the script rebuilds and starts it; you join it to the tailnet |
| xo's dispatch and replies jobs, MCP config, Routines | xo repo (`recovery/`) and deadline (MCP bearer tokens) | you, at the Mac (§3 step 4) |

## 2. What doesn't come back by itself

| Thing | Why | Fix |
|---|---|---|
| IMAP and Slack passwords for xo (`imap-mcp`, `imap-mcp-xo`, `slack-mcp-maf` in the Keychain) | only in the Keychain and your vault | `xo/recovery/bootstrap-mac.sh` asks for them |
| xo's Claude approvals (`xo/.claude/settings.local.json`, gitignored) | lived only on radon | approve the routines' tools on their first runs; keep the list tight |
| Claude Desktop Routines | made in the app's UI | recreate: folder `xo`, daily 08:00, prompt `/xo` |
| `~/KoboInbox` (books, delivery ledger, reading state) | only on radon | your backup; without the ledger, the Kobo may be offered books it already has |
| GPG signing key | `~/.gnupg` | import from your vault, then `setup-gpg-signing.sh` |
| macOS preferences (Finder, Dock, clock) | `~/Library/Preferences` | `scripts/dots.sh` (it also uses sudo) |
| `~/.config/xenon` (healthchecks keys, ntfy topic) | radon runs no See, so nothing needs them | copy from krypton's `/usr/local/etc/xenon/` if radon becomes the standby console |

`id_bootstrap` itself is the one key the rebuild needs from outside: radon doesn't normally hold it (LEDGER §4). Seed it for the rebuild, and remove it afterwards if you'd rather radon kept not holding it. The paper key works instead for KoboShelf (`AGE_IDENTITY`).

## 3. Rebuild order (about an hour of attention)

1. **macOS, Apple ID, iCloud Drive** (Desktop & Documents on). Tailscale signed in. MacPorts with `age`, `gh`, `cloudflared`, and Apple's `container` from its signed `.pkg` (they live outside the home folder, so a lost home folder keeps them).
2. **GitHub and boblbee.** `gh auth login --web` (approve the code from your phone), then clone `matdotcx/boblbee` to `~/Developer/workspace/matdotcx/boblbee`. Set your git name and email. Seed `~/.config/boblbee/id_bootstrap` from the vault.
3. **Run `boblbee/scripts/rebuild-radon.sh`.** In order, it:
    1. runs preflight;
    2. runs `ssh-sync.sh` and adds iCloud's `known_hosts` entries;
    3. clones `ark-config`, `xenon`, `observability`, `xo`, `imap-mcp`, `KoboShelf` and `kohinoor`;
    4. runs boblbee's user-level modules;
    5. installs xo's push job;
    6. runs `host-agents.sh` (the vault and the mirror) and self-update;
    7. runs KoboShelf's `rebuild-host.sh`;
    8. checks the cc box's pf anchor (`kohinoor/cc.sh host --apply`) and starts the box;
    9. checks SSH to the fleet.

    It ends with the list of what's left for you. Unlock the SSH keys when it asks (`ssh-add --apple-use-keychain …`), then re-run it.
4. **xo, at the Mac.**
    1. Run `xo/recovery/bootstrap-mac.sh`.
    2. Quit and reopen Claude Desktop. This ends any Remote Control session.
    3. Recreate the Routine.
    4. Run `xo/recovery/install-replies-job.sh`, then `install-dispatch-job.sh`.
    5. Watch the first runs and approve the tools they ask for.
5. **The rest:** `dots.sh`, GPG, background-item approvals (System Settings → General → Login Items & Extensions), and `~/KoboInbox` from backup.

## 4. Verify

- `scripts/rebuild-radon.sh --check`: no MISSING; only the manual items in its list.
- `boblbee/scripts/host-agents.sh --check`: the radon profile reports the vault origin through the deploy key as ok.
- helium's Prometheus: radon's `node` target is up.
- `curl -s https://kobo.iaconelli.org/health` answers. If the token came back from escrow, the Kobo syncs with no change; if it's new, run `KoboShelf/deploy/point-kobo.sh --apply` with the Kobo plugged in.
- `tail ~/logs/vault-sync.log ~/logs/xo-push.log`: clean runs.
- `kohinoor/cc.sh check`: every probe `ok`, and the box is on the tailnet as `tag:cc`.

## 5. Notes from 15–17 Oct

- `xo/recovery/install-push-job.sh` installs xo's older `git-safe-sync.sh` into `~/bin`, over boblbee's. boblbee's is a superset, so the script runs host-agents afterwards to put it back.
- `claude-sync.sh` keeps whichever `settings.json` is newer and commits and pushes it to boblbee's `gold`. If Claude Code writes a fresh one after boblbee is cloned (likely, when Claude runs the rebuild), that bare default would replace the curated copy, so the script skips `claude-sync` in that case and lists it for you.
- Anything that deletes is tested with HOME pointed at a sandbox and the delete disabled (xenon Gaps #17).
