#!/bin/zsh --no-rcs

# Builds the labels to use in the case statements for Uninstallomator. 
# Useage: 
# ./utils/build-label.sh /Path/To/App.app
# or
# ./utils/build-label.sh com.app.bundleId
#
# Outputs the label to ./fragments/labels

set -euo pipefail

# --- defaults ---
script_dir=$(dirname ${0:A})
repo_dir=$(dirname $script_dir)
out_dir="$repo_dir/fragments/labels"
no_write=0

usage(){
  cat <<USAGE
Usage:
  $(basename "$0") [--out-dir DIR] [--no-write] </Applications/App.app | bundle-id>

Emits a case-style label block suitable for Uninstallomator and writes it to DIR/<label>.sh
(omit file write with --no-write).
USAGE
}

# --- args ---
[[ $# -lt 1 ]] && usage && exit 2
while [[ $# -gt 0 ]]; do
  case "$1" in
    --out-dir) out_dir="$2"; shift 2;;
    --no-write) no_write=1; shift;;
    -h|--help) usage; exit 0;;
    *) break;;
  esac
done
[[ $# -lt 1 ]] && usage && exit 2
input="$1"

# --- Resolve app path / metadata ---
app_path=""; bundle_id=""; app_name=""; team_id="";
if [[ -d "$input" && "$input" == *.app ]]; then
  app_path="$input"
  bundle_id=$(/usr/bin/defaults read "$app_path/Contents/Info" CFBundleIdentifier 2>/dev/null || true)
  app_name=$(/usr/bin/defaults read "$app_path/Contents/Info" CFBundleName 2>/dev/null || basename "$app_path" .app)
else
  bundle_id="$input"
  app_path=$(mdfind "kMDItemCFBundleIdentifier == '$bundle_id' && kMDItemContentType == 'com.apple.application-bundle'" | head -n1)
  if [[ -n "$app_path" ]]; then
    app_name=$(/usr/bin/defaults read "$app_path/Contents/Info" CFBundleName 2>/dev/null || basename "$app_path" .app)
  else
    app_name="$bundle_id"
  fi
fi
vendor_root=""; [[ -n "$bundle_id" ]] && vendor_root=$(echo "$bundle_id" | awk -F. '{print $1"."$2}')
team_id=$(codesign -dv "$app_path" 2>&1 | awk -F= '/TeamIdentifier=/{print $2}' || true)

# --- Arrays (unique) ---
typeset -Ua receipts launch_agents launch_daemons helpers system_files user_files profile_ids
receipts=() launch_agents=() launch_daemons=() helpers=() system_files=() user_files=() profile_ids=()

# --- Receipts ---
while IFS= read -r p; do receipts+=("$p"); done < <(
  /usr/sbin/pkgutil --pkgs 2>/dev/null | egrep -i "${bundle_id}|${vendor_root}|${app_name// /[[:space:]]}"
)

# --- Launchd ---
for dir in /Library/LaunchAgents /Library/LaunchDaemons; do
  [[ -d "$dir" ]] || continue
  while IFS= read -r f; do
    base=$(basename "$f")
    if echo "$base" | grep -qiE "${vendor_root}|${bundle_id}"; then
      [[ "$dir" == *LaunchAgents* ]] && launch_agents+=("$f") || launch_daemons+=("$f")
    fi
  done < <(find "$dir" -maxdepth 1 -type f -name '*.plist' 2>/dev/null)
  while IFS= read -r f; do
    [[ -r "$f" ]] || continue
    label=$(/usr/libexec/PlistBuddy -c 'Print :Label' "$f" 2>/dev/null || defaults read "${f%.plist}" Label 2>/dev/null || true)
    if [[ -n "$label" ]] && echo "$label" | grep -qiE "${vendor_root}|${bundle_id}"; then
      [[ "$dir" == *LaunchAgents* ]] && launch_agents+=("$f") || launch_daemons+=("$f")
    fi
  done < <(find "$dir" -maxdepth 1 -type f -name '*.plist' 2>/dev/null)
done

# --- Helpers & System files ---
for p in \
  "/Library/PrivilegedHelperTools/${vendor_root}*" \
  "/Library/PrivilegedHelperTools/${bundle_id}*" \
  "/Library/Internet Plug-Ins/${app_name}*" \
  "/Library/Internet Plug-Ins/${vendor_root}*" \
  "/Library/PrivilegedHelperTools/${app_name// /}*"; do
  for m in $p(N); do helpers+=("$m"); done
done

for p in \
  "/Library/Application Support/${app_name}" \
  "/Library/Application Support/${vendor_root#*.}" \
  "/Library/${app_name}" \
  "/Library/${vendor_root#*.}" \
  "/Library/Logs/${app_name}"; do
  for m in $p(N); do system_files+=("$m"); done
done

# --- User files template (engine uses %USER_HOME% expansion) ---
user_files+=(
  "%USER_HOME%/Library/Application Support/${app_name}"
  "%USER_HOME%/Library/Preferences/${bundle_id}.plist"
  "%USER_HOME%/Library/Caches/${bundle_id}"
  "%USER_HOME%/Library/Logs/${app_name}"
)

# --- Profiles (heuristic) ---
if profiles -P >/dev/null 2>&1; then
  while IFS= read -r line; do profile_ids+=("$line"); done < <(
    profiles -P | egrep -i "${vendor_root}|${bundle_id}" | awk -F': ' '/profileIdentifier/{print $2}' | sort -u
  )
fi

# --- Emit helpers (skip empty strings) ---
print_array_block(){
  local name="$1"; shift
  local -a arr=()
  local x
  for x in "$@"; do [[ -n "$x" ]] && arr+=("$x"); done
  if (( ${#arr[@]} == 0 )); then
    printf '    %s=()\n' "$name"
    return
  fi
  printf '    %s=(\n' "$name"
  for x in "${arr[@]}"; do
    printf '      "%s"\n' "$x"
  done
  printf '    )\n'
}

snippet() {
  cat <<SNIPPET
${label_guess})
    app_name="${app_name}"
    bundle_id="${bundle_id}"
$(print_array_block app_paths  "$app_path")
$(print_array_block pkgs       "${receipts[@]:-}")
$(print_array_block files      "${helpers[@]:-}" "${system_files[@]:-}")
$(print_array_block user_files "${user_files[@]:-}")
$(print_array_block agents     "${launch_agents[@]:-}")
$(print_array_block daemons    "${launch_daemons[@]:-}")
$(print_array_block profiles   "${profile_ids[@]:-}")
;;
SNIPPET
}

# --- Label filename ---
label_guess=$(echo "$app_name" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-|-$//g')
[[ -z "$label_guess" && -n "$bundle_id" ]] && label_guess=$(echo "$bundle_id" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g')
label_file="$out_dir/${label_guess}.sh"
mkdir -p "$out_dir"

# --- Output ---
snippet  # STDOUT
if (( no_write == 0 )); then
  snippet > "$label_file"
  print -u2 -- "# Wrote fragment: ${label_file}"
fi
