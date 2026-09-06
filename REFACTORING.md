# Refactoring Notes — Open Items

Salvaged from the `refactor-notes` branch (`e2887f6`, 2026-03-10). That
branch carried a 430-line script inventory and drift map. Most of what it
recommended has since shipped, so this file keeps only what is still true
against `gold` as of 2026-09-06 — plus the current call graph, which is
worth having.

**Do not treat this as a full inventory.** It is a short list of loose
ends. The original is recoverable at `e2887f6` if the per-script detail is
ever wanted again.

---

## Call graph (current)

```
bb-setup ──► index.sh ─┬─ (ubuntu) ubuntu-essentials, ubuntu-git-setup,
                       │           git-config-shared, claude, claude-sync,
                       │           zshrc-sync, tmux-sync, motd-sync, ssh-sync,
                       │           tailscale-setup, observability-collector,
                       │           setup-gpg-signing, self-update
                       │
                       └─ (macos)  hostname-fqdn, touchid-sudo, xcode, macports,
                                   dots, git-config-shared, claude, claude-sync,
                                   zshrc-sync, tmux-sync, ghostty-sync, zed-sync,
                                   motd-sync, ssh-sync, tailscale-setup,
                                   observability-collector, pam-ssh-agent-sudo,
                                   setup-gpg-signing, self-update

observability-collector.sh ──► install-collector.sh

bb-sync ────────► the *-sync.sh scripts
bb-sync-fleet ──► sync-fleet.sh   ──► (syncs run remotely)
bb-status-fleet ► status-fleet.sh
bb-update-fleet ► update-fleet.sh

no caller in repo: run-on-hosts.sh  (intentional — generic fleet tool)
```

---

## Open item 1 — RESOLVED: two-way sync primitives extracted

`tmux-sync`, `ghostty-sync` and `zed-sync` each hand-rolled the same
copy + mtime-compare dance. The ghostty and zed theme loops were
byte-for-byte identical to each other.

Rather than bend these onto `sync_dotfile()` — which is the three-way
home/iCloud/repo model and commits each file as it goes — `lib.sh` gained
two primitives matching the shape these scripts actually use:

- `sync_file_2way <repo> <local> <name>` — one file, newest side wins,
  copied across if present on only one side.
- `sync_dir_2way <repo_dir> <local_dir> <label> <plural>` — the same,
  file by file across a directory.

All three scripts now batch a single `commit_dotfiles_changes` at the
end, exactly as before. Net: tmux-sync 116→71 lines, ghostty-sync
131→58, zed-sync 142→59.

## Open item 2 — `ssh-sync.sh` runs a deliberate split model

Every other sync script is uniformly bidirectional. `ssh-sync.sh` is
split, on purpose:

- **Keys** — one-way, iCloud → local, never written back
  (`ssh-sync.sh:28`, `:131`). A host must not push local key material
  back to the shared source.
- **Config** — bidirectional, same mtime-compare as the other scripts
  (`ssh-sync.sh:198`, `:207`).

This is correct as-is. It is listed here only so the asymmetry stops
getting re-flagged as drift — any future `sync_dotfile()` consolidation
has to preserve the one-way key leg.

## Open item 3 — `dots.sh` colour codes (deliberately left alone)

`dots.sh` is the only script still defining `RED`/`GREEN`/`YELLOW`/`NC`
inline rather than sourcing `lib/lib.sh`. This was considered and
rejected: `dots.sh` is a `#!/bin/zsh` script that runs early in bootstrap
under `sudo` and rewrites macOS defaults. Trading four self-contained
colour lines for a three-file source chain (`detect-os.sh` →
`lib/config.sh` → `lib/lib.sh`) makes the riskiest script in the repo
depend on the rest of it for no functional gain.

The other four macOS setup scripts (`macports`, `setup-gpg-signing`,
`touchid-sudo`, `xcode`) do not source `lib.sh` either, and duplicate
nothing — they simply have no need for it.

---

## Resolved since the original notes

Recorded so these do not get re-opened:

- **`lib.sh` extracted** — `log_*`, colours, `get_file_mtime`,
  `commit_dotfiles_changes`, `check_icloud`, `sync_dotfile` are each
  defined exactly once and sourced by 23 of 30 scripts.
- **Symlink sync retired** — no script uses `ln -s` any more. `motd-sync`
  moved to the copy-based model, which was the specific failure mode that
  prompted the original note.
- **Orphans wired up** — `pam-ssh-agent-sudo.sh`, `tailscale-setup.sh` and
  `setup-gpg-signing.sh` are all called from `index.sh`.
- **Hardcoded values centralised** — repo path, branch, iCloud layout and
  the monitoring host live in `lib/config.sh`. The helium address is now
  derived from DNS with a `BOBLBEE_DOMAIN` override rather than hardcoded.
- **Security hardening** — node_exporter binds Tailscale IP or localhost
  (never `0.0.0.0`), SSH agent forwarding is opt-in rather than default,
  and the real host inventory is gitignored with an example shipped.
  (This is what the `refactor-all` branch proposed; gold arrived at the
  same result independently.)
- **Bug list cleared** — `macports.sh` shebang, `claude.sh` `$PWD`
  symlink target, and `zshrc-sync.sh`'s stale `claude-sync` alias check
  are all fixed. `new-machine.sh` was deleted.
- **`has_icloud()`** — removed from `detect-os.sh`; the stale README and
  DOCUMENTATION references were corrected alongside this file.
- **`get_file_mtime()` hardened** — it called `is_macos()`, which lives in
  `detect-os.sh`. A script sourcing `lib.sh` alone got `0` back for every
  file, silently making every mtime comparison a tie and sending syncs the
  wrong way. It now probes `stat -f` then `stat -c` and needs no
  platform helper. (`git-config-shared.sh` sources `lib.sh` without
  `detect-os.sh` today, but touches none of the affected helpers — this
  was latent, not live.)
