# Refactoring Notes — Script Inventory & Drift Map

> Generated as a baseline for cleanup. Each script is summarised by
> **what** it does, **why** it exists, **how** it works, its call-graph
> position, and any overlap/drift with other tooling.
>
> Cross-cutting issues are collated at the end.

---

## Call graph (top-level)

```
bb-setup ────────► index.sh ─┬─► touchid-sudo.sh         (mac)
                             ├─► xcode.sh                 (mac)
                             ├─► macports.sh              (mac)
                             ├─► dots.sh                  (mac)
                             ├─► ubuntu-essentials.sh     (ubuntu)
                             ├─► ubuntu-git-setup.sh      (ubuntu)
                             ├─► claude.sh
                             ├─► zshrc-sync.sh
                             ├─► tmux-sync.sh
                             ├─► ghostty-sync.sh          (mac)
                             ├─► motd-sync.sh
                             ├─► ssh-sync.sh
                             ├─► observability-collector.sh ──► install-collector.sh
                             └─► hostname-fqdn.sh

bb-upgrade ──────► upgrade.sh ──► (subset of index.sh chain)

bb-sync ─────────► zshrc-sync + tmux-sync + ghostty-sync(mac) + motd-sync + claude-sync + ssh-sync
bb-sync-fleet ───► sync-fleet.sh ──► (zshrc-sync + ssh-sync + tmux-sync) remotely
bb-status-fleet ─► status-fleet.sh

orphans (no caller in repo): pam-ssh-agent-sudo.sh, tailscale-setup.sh,
                             setup-gpg-signing.sh, run-on-hosts.sh, new-machine.sh
```

---

## Shared library

### `detect-os.sh`

| | |
|---|---|
| **What** | Library exposing platform-detection helpers. |
| **Why** | Centralise OS/capability detection so scripts don't reimplement it. |
| **How** | Functions: `is_macos`, `is_ubuntu`, `is_cli_only`, `get_os_name`, `get_package_manager`, `has_icloud`, `get_user_bin_path`. `export -f` (bash-only — silently fails in zsh). No side effects on source. |
| **Called by** | 12 scripts source it. |
| **Drift** | `has_icloud()` is **never called** — three scripts (zshrc-sync, motd-sync, ssh-sync) each reimplement iCloud detection differently. Either adopt the library function or delete it. |

---

## Orchestrators

### `index.sh`

| | |
|---|---|
| **What** | Top-level bootstrap; runs the full install chain for macOS or Ubuntu. |
| **Why** | Single entry point for fresh machines; `bb-setup` points here. |
| **How** | Sources detect-os.sh; `run_script()` wrapper bails on first failure, optional sudo, `sleep 3` between each. macOS: touchid-sudo → xcode → macports → dots → claude → *-sync → observability → hostname. Ubuntu: ubuntu-essentials → ubuntu-git-setup → claude → *-sync → observability → hostname. |
| **Drift** | Calls hostname-fqdn.sh with `sudo` on Ubuntu where it just exits 0 — wasted prompt. `sleep 3` after every step is arbitrary. |

### `upgrade.sh`

| | |
|---|---|
| **What** | Migrate existing install to current scripts, preserving user state. |
| **Why** | `git pull` + safe re-sync without clobbering local edits. |
| **How** | Stashes local git changes; pulls `origin gold` (hardcoded); backs up non-symlink `.zshrc` + claude memory; runs claude → zshrc-sync → tmux-sync → ghostty-sync(mac) → motd-sync → ssh-sync; interactive y/n gate. |
| **Drift** | Line 78-82 treats iCloud-symlinked `.zshrc` as correct — **stale**, zshrc-sync.sh now migrates *away* from symlinks. Hardcoded `origin gold`. `missing_scripts` check string-matches its own filename list. |

### `new-machine.sh`

| | |
|---|---|
| **What** | Pre-flight wrapper: checks prerequisites then offers to run index.sh. |
| **Why** | Friendlier first-touch than running index.sh blind. |
| **How** | Sources detect-os.sh; checks git (Ubuntu) or iCloud dir (macOS); probes hardcoded boblbee paths; prompts to run index.sh or prints clone hint. |
| **Drift** | `create_symlink()` (lines 64-99) is **dead code**. Hardcoded path `~/Developer/workspace/matdotcx/boblbee` doesn't match the actual repo location on all machines. Line 73 mentions "iCloud" on Ubuntu branch. Orphan — nothing calls it. |

### `sync-fleet.sh`

| | |
|---|---|
| **What** | Pull repo + run core sync scripts on every host over SSH. |
| **Why** | Push-based convergence instead of logging into each host. |
| **How** | Reads hosts from args or `hosts/elements.txt`. One SSH payload per host: find repo (4 paths) → `git fetch HTTPS && merge --ff-only` → zshrc-sync + ssh-sync + tmux-sync. `PARALLEL=1` / `DRY_RUN=1`. |
| **Drift** | Runs a *subset* of `bb-sync()` (no motd, no claude, no ghostty). Repo-path list includes `~/Developer/matdotcx/boblbee` which the `.zshrc` `BOBLBEE_DIR` detection does *not* — divergent path lists. Hardcoded HTTPS URL. |

### `status-fleet.sh`

| | |
|---|---|
| **What** | Drift dashboard: commit, zshrc hash/type, plugin load, MacPorts, agent-dir perms — one line per host. |
| **Why** | See fleet health at a glance before syncing. |
| **How** | One SSH round-trip per host; heredoc bash emits key=value; compares to local HEAD + zshrc md5. Colour-coded table. Exits non-zero on drift. |
| **Drift** | Same 4-path repo search as sync-fleet (consistent with each other) but still diverges from `.zshrc`'s `BOBLBEE_DIR` list. |

### `run-on-hosts.sh`

| | |
|---|---|
| **What** | Generic "run commands-file on hosts-file" fan-out. |
| **Why** | Ad-hoc fleet ops without a bespoke script. |
| **How** | Parses commands + hosts files (strips `#`); per-command SSH session (`ssh -n -A`); `DRY_RUN` / `PARALLEL` / `STOP_ON_ERROR` / `SSH_OPTS` env flags. Parallel mode writes per-host logfiles. |
| **Drift** | Feature overlap with sync-fleet (both do SSH fan-out with parallel/dry-run) but this is generic. Different SSH defaults (`-A` vs `-A -o BatchMode=yes -o ConnectTimeout=5`). |

---

## Sync scripts (`*-sync.sh`)

### `zshrc-sync.sh`

| | |
|---|---|
| **What** | 3-way bidirectional sync: `~/.zshrc` ↔ `assets/.zshrc` ↔ iCloud. |
| **Why** | Keep shell config consistent; git-tracked source of truth. |
| **How** | Branches: Ubuntu (2-way repo↔home), mac+iCloud (3-way), mac-no-iCloud (2-way). Newest-mtime-wins; auto-commits. Migrates symlinked `~/.zshrc` → real local copy (iCloud symlinks break on eviction). |
| **Drift** | `check_icloud()` duplicates detect-os's `has_icloud()`. Lines 336-391 (mac-no-iCloud) are ~90% copy of lines 165-219 (Ubuntu) — should collapse. Lines 399-404 check for a `claude-sync` alias that no longer exists. Helper functions copy-pasted in motd-sync. |

### `motd-sync.sh`

| | |
|---|---|
| **What** | 3-way sync of `.motd` (home ↔ repo ↔ iCloud), **symlinks** `~/.motd` to winner. |
| **Why** | Share login banner across hosts. |
| **How** | Inline `OSTYPE` check (doesn't source detect-os). With iCloud: sync newest, then symlink home → iCloud. Without: symlink home → repo. Auto-commits. |
| **Drift** | **Nearly identical structure to zshrc-sync** but inverse strategy (symlinks to iCloud; zshrc copies from it). All helpers (`get_file_mtime`, `find_newest_file`, `commit_dotfiles_changes`, `log_message`, `check_permissions`, `check_icloud`, `backup_*`) are copy-pasted. Uses `$OSTYPE` not `is_macos`. **Prime consolidation target.** |

### `tmux-sync.sh`

| | |
|---|---|
| **What** | Bidirectional sync of tmux.conf + base + dark/light themes between repo and `~/.tmux.conf` / `~/.config/tmux/`. |
| **Why** | Keep tmux config + themes in sync; auto-reload live sessions. |
| **How** | `sync_file()` helper per file (newest-mtime-wins). Unconditional `commit_dotfiles_changes` at end. Reloads via `tmux source-file`. |
| **Drift** | **Third copy** of `get_file_mtime()` + `commit_dotfiles_changes()`. No iCloud leg (simpler — probably correct). |

### `ghostty-sync.sh`

| | |
|---|---|
| **What** | Bidirectional config sync + one-way theme push (mac only). |
| **Why** | Terminal emulator config in repo. |
| **How** | `is_macos` gate. Config: newest-mtime-wins. Themes: repo → `~/.config/ghostty/themes/` only (no reverse). Auto-commits. |
| **Drift** | **Fourth copy** of the helpers. Uses `stat -f %m` directly (mac-only so fine). Theme strategy (push-only) inconsistent with tmux-sync (bidirectional). |

### `ssh-sync.sh`

| | |
|---|---|
| **What** | Populate `~/.ssh` from iCloud (mac), or just fix perms (Ubuntu). One-way pull. |
| **Why** | Seed keys/config from iCloud, migrate away from fragile symlinks. |
| **How** | mac+iCloud: if symlink → migrate to real dir; if dir → pull newer portable files; if absent → create. Fixes perms (600/644/700), strips quarantine xattr, cleans stale agent sockets. **iCloud is read-only source.** Ubuntu: perms + print pubkeys. |
| **Drift** | Own `check_icloud()` (third implementation — read-only check; others write-test). Different philosophy from zshrc-sync (one-way vs 3-way) — intentional, but the inconsistency is unstated. |

### `claude-sync.sh`

| | |
|---|---|
| **What** | Copy `~/.config/claude/memory/user.md` → `claude/memory/user.md`, show diff, prompt to commit. |
| **Why** | Capture Claude CLI memory into git. |
| **How** | `cd` to repo via `BASH_SOURCE`. Bails if file missing or no diff. Interactive y/n + commit msg. |
| **Drift** | **Likely a no-op** — if claude.sh has run, `~/.config/claude/memory/user.md` is already a symlink to the repo file, so `cp` same → self → no diff. Possible dead workflow. No shared commit helper. |

---

## macOS system setup

### `dots.sh`

| | |
|---|---|
| **What** | Opinionated `defaults write` dump (Finder/Dock/menubar/updates/Safari/sleep). |
| **Why** | One-shot new-Mac personalisation. |
| **How** | zsh script (associative arrays). Prompts for computer name; sets ComputerName/HostName/LocalHostName/NetBIOS. `run_command()` wrapper logs to `~/boblbee.log`. Branches sleep policy on MacBook-vs-desktop. Kills Finder/Dock/SystemUIServer. |
| **Drift** | Extra `fi` at line 265 causes indent drift (harmless but confusing). Sets HostName to short name; hostname-fqdn.sh later overwrites with FQDN → two writes. `run_command()` not shared. Doesn't source detect-os. |

### `touchid-sudo.sh`

| | |
|---|---|
| **What** | Insert `pam_tid.so` into `/etc/pam.d/sudo`. |
| **Why** | TouchID authorises sudo. |
| **How** | Checks lib exists, not already present, first line matches expected. `sed -i .bak` insert. |
| **Drift** | Same sed-PAM pattern as pam-ssh-agent-sudo.sh — separate implementations. |

### `xcode.sh`

| | |
|---|---|
| **What** | Install Xcode CLT via softwareupdate if missing. |
| **Why** | Prereq for compilers/git/MacPorts. |
| **How** | `xcode-select -p` check; magic temp file to surface CLT in update list; grep + install latest. |
| **Drift** | pam-ssh-agent-sudo also checks `xcode-select -p` with the same pattern. |

### `macports.sh`

| | |
|---|---|
| **What** | Build MacPorts from source at latest stable tag; install essential ports. |
| **Why** | Preferred package manager. |
| **How** | Fetches latest git tag; tarball-backup existing `/opt/mports`; clones + builds + installs; writes `/etc/paths.d/macports`; `port selfupdate`; installs zsh plugins + git + curl. 24h recency skip prompt. |
| **Drift** | Shebang at line 7 (after comments) — wrong placement. Unconditionally appends to paths.d → duplicate lines on re-run. `SCRIPT_DIR`/`BOBLBEE_DIR` defined (lines 15-16) but **never used** — dead. |

### `hostname-fqdn.sh`

| | |
|---|---|
| **What** | Set macOS HostName to `<LocalHostName>.<dns-search-domain>`. |
| **Why** | Proper FQDN for prompts/logs. |
| **How** | `is_macos` gate; scrapes search domain via `scutil --dns` (filters Tailscale); idempotent. |
| **Drift** | dots.sh already sets HostName to short name — this overwrites. index.sh calls this with `sudo` on Ubuntu where it immediately exits — wasted prompt. |

### `pam-ssh-agent-sudo.sh`

| | |
|---|---|
| **What** | Build + install `pam_ssh_agent_auth` from source; configure sudo to accept agent keys. |
| **Why** | Passwordless sudo over SSH (incl. Tailscale SSH) without TouchID reach. |
| **How** | Downloads tarball + 8 Debian patches + macOS `explicit_bzero` shim. Builds against MacPorts OpenSSL. Adds `SSH_AUTH_SOCK` to sudoers env_keep; inserts PAM line. `install|uninstall` subcommands. |
| **Drift** | **Orphan** — not called by index.sh, no alias. `[[ "$(uname)" != "Darwin" ]]` instead of detect-os. Log helpers copy-pasted (5th implementation). |

---

## Ubuntu setup

### `ubuntu-essentials.sh`

| | |
|---|---|
| **What** | Install apt packages, configure npm prefix, install Claude CLI, chsh to zsh. |
| **Why** | Ubuntu equivalent of xcode.sh + macports.sh. |
| **How** | `is_ubuntu` gate; refuse root; apt install loop with installed-check; npm prefix `~/.npm-global`; `chsh -s zsh`; throwaway `.zshrc` if absent. `set -e`. |
| **Drift** | Installs Claude CLI (lines 90-96) — **duplicates claude.sh**. index.sh runs both → second is redundant on Ubuntu. |

### `ubuntu-git-setup.sh`

| | |
|---|---|
| **What** | Interactive git config + SSH key copy/generate + optional GitHub token + test connection. |
| **Why** | Match macOS git workflow on Ubuntu. |
| **How** | `is_ubuntu` gate. Prompts name/email if unset; writes ~10 global configs. SSH: copy-from-mac (paste stdin), generate (rsa 4096), or skip. Starts agent + add. |
| **Drift** | SSH flow overlaps ssh-sync.sh (both touch `~/.ssh`, both fix perms) — could conflict if run back-to-back. Log helpers copy-pasted from ubuntu-essentials. |

---

## Observability

### `observability-collector.sh`

| | |
|---|---|
| **What** | Install node_exporter (via install-collector.sh) then register with `helium` over SSH. |
| **Why** | Auto-enrol new machines into Prometheus. |
| **How** | Probes :9100/:9101 for idempotency. Resolves helium via **hardcoded** FQDN + IP fallback. `ssh -A helium ~/observability/scripts/register-host.sh <hostname> <ip> <port>`. Prefers Tailscale IP. |
| **Drift** | Hardcoded server FQDN + IP + remote script path. Probes port 9101 for `com.observability.macos-exporter.plist` which **this repo never installs** — legacy external dependency. |

### `install-collector.sh`

| | |
|---|---|
| **What** | Download + install node_exporter binary; wire up LaunchAgent (mac) or systemd (linux). |
| **Why** | The actual installer; observability-collector is the orchestrator. |
| **How** | Own platform detection (**doesn't source detect-os** despite header comment). Downloads tarball → `~/bin/node_exporter`. Writes launchd plist or systemd unit (user/system per `$EUID`). Verifies via curl. |
| **Drift** | Redefines `is_macos()` instead of sourcing detect-os. Hardcoded version `1.10.2`. Log helpers = **5th copy**. |

---

## Misc

### `tailscale-setup.sh`

| | |
|---|---|
| **What** | Install Tailscale + auth prompt. |
| **Why** | VPN mesh enrolment. |
| **How** | mac: opens App Store page for manual install. Ubuntu: `curl | sh` official installer then `sudo tailscale up --ssh`. Status check via JSON. |
| **Drift** | **Orphan** — not in index.sh, no alias. But observability-collector *depends* on Tailscale IP — sequencing hazard. |

### `setup-gpg-signing.sh`

| | |
|---|---|
| **What** | Configure git to GPG-sign commits/tags; push pubkey to GitHub via `gh`. |
| **Why** | Verified commits. |
| **How** | Greps secret keys for email (arg or git config). Sets signingkey + gpgsign. `gh gpg-key add` if absent. |
| **Drift** | **Orphan.** Only script with no colour codes / log helpers / header consistency. |

### `claude.sh`

| | |
|---|---|
| **What** | Install Claude CLI via npm; symlink `~/.config/claude/memory/user.md` → repo. |
| **Why** | CLI install + memory-file sync. |
| **How** | Checks for `claude`; tries npm → installs npm via MacPorts if missing. `mkdir -p`; backs up existing; `ln -sf $PWD/claude/memory/user.md`. |
| **Drift** | **`$PWD` bug** — `bb-setup` does `cd $BOBLBEE_DIR/scripts` then runs index.sh, so `$PWD` = scripts/ when claude.sh runs → symlink points at `scripts/claude/memory/user.md` → **broken**. ubuntu-essentials also installs Claude CLI (duplicate). If the symlink *did* work, claude-sync.sh would be a no-op. |

---

## `.zshrc` entrypoints

| Name | What | Target |
|---|---|---|
| `BOBLBEE_DIR` | First of 3 hardcoded paths that exists | — |
| `bb-help` | Echo command list | — |
| `bb-setup` | `cd $BOBLBEE_DIR/scripts && ./index.sh` | index.sh |
| `bb-upgrade` | Run upgrade | upgrade.sh |
| `bb-sync-zshrc` | — | zshrc-sync.sh |
| `bb-sync-tmux` | — | tmux-sync.sh |
| `bb-sync-ghostty` | — | ghostty-sync.sh |
| `bb-sync-claude` | — | claude-sync.sh |
| `bb-sync-ssh` | — | ssh-sync.sh |
| `bb-sync-motd` | — | motd-sync.sh |
| `bb-status-fleet` | — | status-fleet.sh |
| `bb-sync-fleet` | — | sync-fleet.sh |
| `bb-reload` | `exec $SHELL -l` | — |
| `bb-sync()` | All six syncs + push | multiple |
| `bb-status()` | Local repo/zshrc/ssh state | — |
| `bb-edit()` | `cd $BOBLBEE_DIR && $EDITOR .` | — |

**Drift in .zshrc:**
- `bb-sync()` uses `[[ "$OSTYPE" == "darwin"* ]]` not `is_macos` (which is defined in the same file).
- `BOBLBEE_DIR` detection (3 paths) **doesn't include** `~/Developer/matdotcx/boblbee` — the actual repo location on some machines. All aliases break there.
- `bb-sync()` doesn't run hostname-fqdn or observability-collector; index.sh does.
- `bb-status()` knows about symlink→local migration; `upgrade.sh` doesn't.

---

# Cross-cutting issues

## 1. Copy-pasted helpers (biggest consolidation win)

| Helper | Copies | Where |
|---|---|---|
| `get_file_mtime()` | 4 | zshrc-sync, motd-sync, tmux-sync, ghostty-sync |
| `commit_dotfiles_changes()` | 4 | zshrc-sync, motd-sync, tmux-sync, ghostty-sync |
| `log_info/success/warn/error` | 5 | install-collector, pam-ssh-agent-sudo, run-on-hosts, ubuntu-essentials, ubuntu-git-setup |
| `check_icloud()` | 3 | zshrc-sync, motd-sync, ssh-sync (all different!) |
| Colour code definitions | ~all | Every script defines RED/GREEN/BLUE/NC inline |

**Refactor:** a `lib.sh` alongside `detect-os.sh` with the shared helpers.
Single sourcing line, no more drift.

## 2. Inconsistent platform detection

| Pattern | Users |
|---|---|
| `is_macos` (detect-os) | ghostty-sync, hostname-fqdn, index, new-machine, observability-collector, ssh-sync, tailscale-setup, tmux-sync, ubuntu-*, upgrade, zshrc-sync |
| Raw `$OSTYPE` | motd-sync, install-collector (own def), .zshrc `bb-sync()` |
| `uname` | pam-ssh-agent-sudo |

`detect-os.sh has_icloud()` exists but **zero callers** — three scripts roll their own.

## 3. Orphans

Not in any call graph (manual-invoke only):
- `pam-ssh-agent-sudo.sh`
- `tailscale-setup.sh` (but observability *depends* on Tailscale being up)
- `setup-gpg-signing.sh`
- `run-on-hosts.sh` (intentional — generic tool)
- `new-machine.sh` (bootstrap-only)

Decide: wire into index.sh, document as manual, or delete.

## 4. Hardcoded values (config-file candidates)

| Value | Where | Problem |
|---|---|---|
| Repo paths | 4 different lists: .zshrc (3 paths), new-machine (2), status-fleet (4), sync-fleet (4) | .zshrc list is missing the path some machines actually use |
| `origin gold` | upgrade.sh, sync-fleet.sh | Branch rename = 2 edits |
| `Ark/Sync/System/` | zshrc-sync, motd-sync, ssh-sync | iCloud layout is repo-wide assumption, undocumented |
| helium FQDN+IP+script path | observability-collector | Server change = edit + redeploy |
| node_exporter `1.10.2` | install-collector | Manual version bump |

## 5. Likely bugs

| Script | Bug |
|---|---|
| `claude.sh` | `$PWD`-dependent symlink target → broken link when run via `bb-setup` |
| `macports.sh` | Shebang after comment block; paths.d append duplicates on re-run; unused `SCRIPT_DIR`/`BOBLBEE_DIR` |
| `dots.sh` | Extra `fi` at line 265 (indent-only, but confusing) |
| `index.sh` | sudo-calls hostname-fqdn on Ubuntu where it's a no-op |
| `claude-sync.sh` | No-op if claude.sh symlink is in place (same file → self) |

## 6. Stale logic

| Script | Stale |
|---|---|
| `upgrade.sh` | Treats iCloud-symlinked .zshrc as good state (migration target is local-copy now) |
| `zshrc-sync.sh` | Lines 399-404 check for a `claude-sync` alias that no longer exists |
| `observability-collector.sh` | Probes port 9101 for `macos-exporter` LaunchDaemon this repo never installs |

## 7. Inconsistent sync philosophies

| Script | Strategy | iCloud role |
|---|---|---|
| zshrc-sync | 3-way bidirectional | Participant (local copy, not symlink) |
| motd-sync | 3-way + symlink | Live mount (symlink to iCloud) |
| ssh-sync | 1-way pull | Read-only source |
| tmux-sync | 2-way bidirectional | None |
| ghostty-sync | 2-way config, 1-way themes | None |
| claude-sync | 1-way pull | None (but claude.sh symlinks) |

Three different iCloud models in use. motd-sync still symlinks (same
failure mode that prompted the zshrc/ssh migrations). Worth deciding on
one strategy and applying consistently.

---

# Suggested refactor order (low risk → high)

1. **lib.sh** — extract `get_file_mtime`, `commit_dotfiles_changes`,
   `log_*`, colour codes. Mechanical; high payoff.
2. **Unify iCloud detection** — either adopt `detect-os.sh has_icloud()`
   everywhere or delete it and promote one of the local impls.
3. **Single `BOBLBEE_DIR` search** — one function in lib.sh,
   one path list, sourced by .zshrc and all fleet scripts.
4. **Fix the obvious bugs** (claude.sh `$PWD`, macports.sh shebang/paths.d,
   index.sh Ubuntu sudo).
5. **Collapse zshrc-sync Ubuntu + mac-no-iCloud branches** — ~50 lines saved.
6. **Align motd-sync with zshrc-sync strategy** — copy not symlink.
   Then consider factoring both into a generic `sync_three_way()` helper.
7. **Decide orphan fate** — wire tailscale into index before observability,
   document the rest as optional or delete.
8. **Config file** for hardcoded values (paths, branch, iCloud layout,
   monitoring server).
