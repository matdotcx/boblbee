#!/bin/zsh
# Mirror XO daily debriefs from radon into the Obsidian vault's Archive/Daily folder.
set -u
SRC="ops@radon:/Users/ops/Developer/workspace/matdotcx/xo/debrief/"
STAGE="$HOME/.cache/xo-debrief"
VAULT="$HOME/Library/Mobile Documents/iCloud~md~obsidian/Documents/Zettelkasten"
DAILY="$VAULT/Archive/Daily"
mkdir -p "$STAGE" "$DAILY"
/usr/bin/rsync -az --include='*/' --include='*.md' --exclude='*' "$SRC" "$STAGE/" || { echo "$(date) rsync failed"; exit 1; }
n=0
for f in "$STAGE"/20*/*/*.md; do
  [ -f "$f" ] || continue
  b=$(basename "$f"); d="${b%.md}"; dest="$DAILY/$b"
  if [ ! -f "$dest" ] || ! cmp -s <(tail -n +9 "$dest" 2>/dev/null) "$f"; then
    { printf -- "---\ncreated: %s\nmodified: %s\ntags: [journal, xo]\ntype: journal\nstatus: active\narea: vault\n---\n" "$d" "$d"; cat "$f"; } > "$dest"; n=$((n+1))
  fi
done
[ -f "$STAGE/_outstanding.md" ] && { printf -- "---\ncreated: 2026-04-09\nmodified: %s\ntags: [journal, xo, outstanding]\ntype: journal\nstatus: active\narea: vault\ndescription: \"XO outstanding items ledger, mirrored from radon\"\n---\n\n" "$(date +%F)"; cat "$STAGE/_outstanding.md"; } > "$DAILY/XO Outstanding.md"
echo "$(date) mirrored $n new or changed debriefs"
