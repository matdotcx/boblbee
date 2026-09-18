# Aluminium rebuild runbook

If aluminium (Diego's main Mac) dies: what comes back from where, and in what order. Written 17 Sep 2026 after the storage tidy-up; last revised 18 Sep 2026. Assumes a replacement Mac, a fresh macOS install, and that cobalt, radon and deadline are still up.

## 1. What is safe today (recoverable without aluminium)

| Thing | Where the copy lives | How it comes back |
|---|---|---|
| Desktop, Documents (Admin, Projects, Ebooks/Staging, Calibre Library, Screenshots, Claude/Scheduled, Arduino) | iCloud Desktop & Documents sync | sign in to iCloud; turn on Desktop & Documents; wait for the download (~30 GB, Calibre is 27 GB of it) |
| iCloud Drive: Ark/Archive, Ark/Sync/System, iOS Downloads | iCloud Drive | same sign-in |
| Photos | iCloud Photos + full mirror on cobalt (Backblaze) | sign-in; library rebuilds as optimised; originals stay on cobalt |
| Obsidian vault (notes) | iCloud Obsidian container **and** git on deadline (`deadline:vault.git`) and radon (`vault-mirror.git`) | iCloud brings the files; git history must be re-attached (step 5) |
| Code: repos under `Developer/workspace/matdotcx` | GitHub `matdotcx/*` | `git clone`; only uncommitted work is lost, so push branches often |
| Dotfiles (.zshrc, .tmux.conf, .motd, ghostty, zed, Claude settings and memory) | boblbee repo (GitHub) + `Ark/Sync/System` (iCloud) | boblbee bootstrap (step 3) |
| SSH keys and config, PGP keys | `Ark/Sync/System/.ssh` and `Ark/Sync/System/pgp-keys` (iCloud) | boblbee `ssh-sync.sh` seeds them; PGP import by hand |
| Screenshot upload pipeline | repo `matdotcx/screenshot-upload` with `install.sh` | run the installer |
| node_exporter LaunchAgent (`org.iaconelli.node-exporter`) | boblbee `scripts/install-collector.sh` | boblbee bootstrap |
| git-safe-sync.sh | shared copy in boblbee `scripts/lib/` (patched: pointer-file `.git`, `--remote`); xo still carries the older one | boblbee install copies it to `~/bin` |
| Music, TV | Apple cloud libraries; media on cobalt | sign in |
| Mail, Messages, Contacts, Calendars | iCloud / IMAP | sign in |
| Media library, Radarr/Sonarr, Photos mirror, Backblaze | all on cobalt | nothing to do |

## 2. What is lost today (exists only on aluminium)

| Thing | Why it matters | Fix |
|---|---|---|
| ~~`~/bin/vault-sync.sh`, `xo-mirror.sh`, `downloads-sweep.sh`, `sweep-now`, `add-mxroute-mcp.sh`~~ | **closed**: boblbee `hosts/agents/aluminium/` (assignment in `hosts/agent-assignments.txt`); `aluminium-agents` repo archived 23:15 | boblbee install does it |
| ~~LaunchAgent plists: vault-sync, xo-mirror, downloads-sweep~~ | **closed**: templated in boblbee `hosts/agents/aluminium/launchd/` (+ `org.iaconelli.koboshelf-backup`) | boblbee install does it |
| `~/.vault.git` | the vault's git dir; the iCloud tree has only a one-line `.git` pointer to it | re-clone from deadline and re-attach (step 5); nothing lost, just a procedure |
| ~~`~/Library/Application Support/KoboShelf`~~ | **closed**: `koboshelf-state-backup` snapshots it nightly at 03:30 into `~/Documents/Calibre Library/.koboshelf-backups/state/<date>` (iCloud), 14 kept; first snapshot 851 MB taken 17 Sep | restore: copy `state/latest/` back to `~/Library/Application Support/KoboShelf` |
| `~/.local/state/downloads-sweep` (stamp, manifests) | harmless; the NAS has the manifests | none needed |
| Downloads younger than 14 days, `~/Library` caches, Claude sandbox VM, Xcode/Arduino toolchains | reinstallable or transient | accept |
| Radarr/Sonarr API keys | on cobalt, not here | none |
| Full Disk Access grants, iCloud sign-in, Photos "Shared with You", Safari download location | per-machine settings | redo by hand (list in step 6) |

## 3. Rebuild order (estimated 2–3 hours of attention, most of it waiting on iCloud)

1. **macOS + Apple ID.** Sign in; turn on iCloud Drive with Desktop & Documents, Photos, Messages. Let it start downloading.
2. **Xcode Command Line Tools, MacPorts/Homebrew** as boblbee expects (`scripts/xcode.sh`, `scripts/macports.sh`).
3. **boblbee bootstrap.** Clone `matdotcx/boblbee` to `~/Developer/workspace/matdotcx/boblbee` (the path is hard-coded), then run its macOS quick start. It restores `.zshrc`/tmux/motd, seeds `~/.ssh` from `Ark/Sync/System/.ssh` once iCloud has it, installs node_exporter and the nightly self-update agent, and syncs Claude settings. Clone the private `ark-config` beside it.
4. **Clone the rest of `matdotcx/*`** into the same workspace (xo, screenshot-upload, KoboShelf, deadline, dns, observability, …). Run `screenshot-upload/install.sh`.
5. **Re-attach the vault to git.** After iCloud has restored the Obsidian container:
   ```
   git clone --bare deadline:vault.git ~/.vault.git
   cd "~/Library/Mobile Documents/iCloud~md~obsidian/Documents/Zettelkasten"
   printf 'gitdir: %s\n' "$HOME/.vault.git" > .git      # iCloud may already have restored this file
   git -C ~/.vault.git config core.bare false
   git -C ~/.vault.git config core.worktree "$PWD"
   git remote add radon ops@radon:vault-mirror.git 2>/dev/null; git status
   ```
   Expect `git status` to show only files changed since the last push; commit them with the normal sync.
6. **Aluminium's own agents come with boblbee** (step 3 already installed them: `index.sh` ends with `host-agents.sh`, which reads `hosts/agent-assignments.txt`). Verify with `boblbee/scripts/host-agents.sh --check`. Grant **Full Disk Access to `/bin/zsh`** (xo-mirror, vault-sync). Restore KoboShelf state from `~/Documents/Calibre Library/.koboshelf-backups/state/latest/` after KoboShelf's first launch.
7. **Apps and their pointers.** calibre → open `~/Documents/Calibre Library`; KoboShelf → same library, then restore the KoboShelf state folder from its backup; CleanShot X export path → `~/Documents/Screenshots`; Claude Desktop routines pick up `Documents/Claude/Scheduled` automatically.
8. **Per-machine settings to redo:** Full Disk Access as above; Photos → Settings → iCloud (optimise storage is fine here; cobalt holds originals); Safari download location `~/Downloads`; Messages "Keep messages" preference; Time Machine destination if you add one.
9. **Verify:** `~/bin/vault-sync.sh` exits 0; `sweep-now --dry-run` reaches cobalt; `curl localhost:9100/metrics` answers; a screenshot lands on media.iaconelli.org; xo-mirror log shows no "operation not permitted".

## 4. Remaining exposure

Everything above is covered by iCloud, GitHub or cobalt. What a dead aluminium still loses:

- Downloads younger than 14 days (the weekly sweep has not offloaded them yet).
- Uncommitted or unpushed git work.
- `~/Library` application data other than KoboShelf (which has its nightly snapshot).
- Per-machine grants and preferences (step 8).

A Time Machine destination on cobalt, or Backblaze on aluminium, would close those too. Not done as of September 2026.

## 5. Keeping this current

This runbook lives in boblbee (`docs/aluminium-rebuild-runbook.md`) because boblbee is the tool that performs most of the rebuild. When a new job, agent or data location is added to aluminium, add a row to section 1 or 2 in the same commit. The per-host agent profile is `hosts/agents/aluminium/`; anything installed by hand instead of through it belongs in section 2 until it is moved.
