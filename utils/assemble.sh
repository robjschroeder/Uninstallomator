#!/bin/zsh --no-rcs
# Assemble label CASE entries into ./Uninstallomator.sh.
# Replaces content between:
#   # BEGIN LABEL CASES
#   # END LABEL CASES

set -euo pipefail
setopt extendedglob

script_dir=$(dirname ${0:A})
repo_dir=$(dirname $script_dir)
labels_dir="$repo_dir/fragments/labels"
target="$repo_dir/Uninstallomator.sh"   # << default to .zsh
dry_run=0
min_bytes=200

while [[ $# -gt 0 ]]; do
  case "$1" in
    --labels) labels_dir="$2"; shift 2;;
    --target) target="$2"; shift 2;;
    --dry-run) dry_run=1; shift;;
    -h|--help)
      cat <<USAGE
Usage: ${0##*/} [--labels DIR] [--target FILE] [--dry-run]
Replaces the case labels region between markers in the target file.
Markers (indent allowed):
  # BEGIN LABEL CASES
  # END LABEL CASES
USAGE
      exit 0;;
    *) echo "# Unknown option: $1"; exit 2;;
  esac
done

[[ -f "$target" ]] || { echo "# Target not found: $target"; exit 1; }
[[ -d "$labels_dir" ]] || { echo "# Labels dir not found: $labels_dir"; exit 1; }
perl -i -pe 's/\r$//' "$target" 2>/dev/null || true

if ! /usr/bin/grep -Fq "# BEGIN LABEL CASES" "$target"; then
  echo "# Marker not found in target: # BEGIN LABEL CASES"; exit 1; fi
if ! /usr/bin/grep -Fq "# END LABEL CASES" "$target"; then
  echo "# Marker not found in target: # END LABEL CASES"; exit 1; fi

# Gather fragments
label_files=("$labels_dir"/**/*.sh(N) "$labels_dir"/*.sh(N))
label_files=("${(ou)label_files[@]}")
(( ${#label_files[@]} )) || { echo "# No label fragments found in $labels_dir"; exit 1; }

echo "# Target : $target"
echo "# Labels : $labels_dir"
echo "# Fragments found: ${#label_files[@]}"

# Build temp block file (avoids awk -v newline issues)
ts=$(date +%Y%m%d-%H%M%S)
blk="$repo_dir/.assemble_block.${ts}.tmp"
{
  echo "# BEGIN LABEL CASES"
  for f in "${label_files[@]}"; do
    rel="${f#${repo_dir}/}"
    echo "# === fragment: ${rel} ==="
    cat "$f"
    echo
  done
  echo "# END LABEL CASES"
} > "$blk"

# Sanity on block
if [[ ! -s "$blk" ]]; then echo "# Error: assembled block is empty"; rm -f "$blk"; exit 1; fi

# Dry run?
if (( dry_run )); then
  echo "# Backup: (dry-run) $target.bak-$ts"
  echo "# DRY-RUN: would write label cases into $target"
  echo "# ------- BEGIN NEW BLOCK -------"
  cat "$blk"
  echo "# -------- END NEW BLOCK -------"
  echo "# Labels present in assembled block:"
  awk '/^[[:space:]]*[A-Za-z0-9._-]+\)/{sub(/\).*/,"",$1);gsub(/[()]/,"",$1);print "  - "$1}' "$blk" | sort -u
  rm -f "$blk"
  exit 0
fi

# Backup current file
backup="${target}.bak-${ts}"
cp "$target" "$backup"
echo "# Backup: $backup"

tmp="${target}.tmp-${ts}"
/usr/bin/awk -v blk="$blk" '
  function print_block_with_indent(file, indent,   line) {
    while ((getline line < file) > 0) {
      if (line == "") print indent;
      else print indent line;
    }
    close(file);
  }
  {
    if ($0 ~ /^[ \t]*# BEGIN LABEL CASES[ \t]*$/) {
      match($0, /^[ \t]*/); indent=substr($0, RSTART, RLENGTH);
      print_block_with_indent(blk, indent);
      while (getline) { if ($0 ~ /^[ \t]*# END LABEL CASES[ \t]*$/) break; }
      next;
    }
    print;
  }
' "$backup" > "$tmp"

# Sanity floor
if [[ ! -s "$tmp" ]]; then echo "# Error: assembled file is empty. Keeping original."; rm -f "$tmp" "$blk"; exit 1; fi
sz=$(wc -c < "$tmp" | tr -d ' ')
if [[ -z "$sz" || "$sz" -lt "$min_bytes" ]]; then
  echo "# Error: assembled target too small ($sz bytes). Keeping original."
  rm -f "$tmp" "$blk"; exit 1
fi

mv -f "$tmp" "$target"
chmod 755 "$target"
rm -f "$blk"
echo "# Wrote labels into: $target ($sz bytes)"

# Quick verification
if /usr/bin/grep -Fq "zoom-us)" "$target"; then
  echo "# Verified: found 'zoom-us)' in $target"
else
  echo "# WARN: 'zoom-us)' not found in $target. Check fragment file and markers."
fi
