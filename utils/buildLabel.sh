#!/bin/zsh --no-rcs
#
# build-label.sh — generate Uninstallomator label fragments
# Usage:
#   utils/build-label.sh /Applications/App.app
#   utils/build-label.sh com.vendor.BundleID
#
# Writes: ./fragments/labels/<label>.sh   (override with --out-dir)
# Prints the same snippet to STDOUT.
#
# Built-in vendor prefix list: microsoft google
# Label examples: microsoftedge, googlechrome, slack, spotify
#

set -euo pipefail
setopt NULL_GLOB

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
(omit the file write with --no-write).
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
app_path=""; bundle_id=""; app_name="";
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

# vendor root like "com.vendor"
vendor_root=""
[[ -n "$bundle_id" ]] && vendor_root=$(echo "$bundle_id" | awk -F. '{print $1"."$2}')

# --- Arrays (unique) ---
typeset -Ua receipts launch_agents launch_daemons helpers system_files user_files profile_ids
receipts=() launch_agents=() launch_daemons=() helpers=() system_files=() user_files=() profile_ids=()

# Small helpers
lower(){ echo "$1" | tr '[:upper:]' '[:lower:]'; }
order_uniq(){ awk '!(seen[$0]++)'; }

# Tokens for app-specific matching (used for files/helpers)
app_base="$(basename "${app_path:-$app_name}" .app)"     # "Microsoft Edge"
app_name_sans_space="${app_name// /}"                    # "MicrosoftEdge"
last_bid_piece="${bundle_id##*.}"                        # "edgemac", "Chrome", etc.
_l_app_base=$(lower "$app_base")
_l_app_name=$(lower "$app_name")
_l_app_nospace=$(lower "$app_name_sans_space")
_l_last_bid=$(lower "$last_bid_piece")

match_app_token() {
  local s; s=$(lower "$1")
  [[ "$s" == *"$_l_app_base"* || "$s" == *"$_l_app_name"* || "$s" == *"$_l_app_nospace"* || ( -n "$_l_last_bid" && "$s" == *"$_l_last_bid"* ) ]]
}

# ============ DISCOVERY ============
# --- Receipts (coarse; filtered later by engine with --show-skipped if needed) ---
while IFS= read -r p; do
  # Only include exact bundle_id or bundle_id with minimal suffixes
  if [[ "$p" == "$bundle_id" || "$p" == "$bundle_id".* ]]; then
    receipts+=("$p")
  fi
done < <(/usr/sbin/pkgutil --pkgs 2>/dev/null)

# --- Launchd (tight: prefer bundle_id prefix; minimal fallback to app tokens) ---
for dir in /Library/LaunchAgents /Library/LaunchDaemons; do
  [[ -d "$dir" ]] || continue

  # Filename match
  while IFS= read -r f; do
    base=$(basename "$f")
    if [[ -n "$bundle_id" ]] && echo "$base" | grep -qiE "^${bundle_id}"; then
      [[ "$dir" == *LaunchAgents* ]] && launch_agents+=("$f") || launch_daemons+=("$f")
      continue
    fi
    # fallback — only if filename clearly mentions the app
    if match_app_token "$base"; then
      [[ "$dir" == *LaunchAgents* ]] && launch_agents+=("$f") || launch_daemons+=("$f")
    fi
  done < <(find "$dir" -maxdepth 1 -type f -name '*.plist' 2>/dev/null)

  # Plist :Label match
  while IFS= read -r f; do
    [[ -r "$f" ]] || continue
    label=$(/usr/libexec/PlistBuddy -c 'Print :Label' "$f" 2>/dev/null || defaults read "${f%.plist}" Label 2>/dev/null || true)
    if [[ -n "$label" ]]; then
      if [[ -n "$bundle_id" ]] && echo "$label" | grep -qiE "^${bundle_id}"; then
        [[ "$dir" == *LaunchAgents* ]] && launch_agents+=("$f") || launch_daemons+=("$f")
      elif match_app_token "$label"; then
        [[ "$dir" == *LaunchAgents* ]] && launch_agents+=("$f") || launch_daemons+=("$f")
      fi
    fi
  done < <(find "$dir" -maxdepth 1 -type f -name '*.plist' 2>/dev/null)
done

# --- Helpers (privileged tools & plug-ins) ---
for p in \
  "/Library/PrivilegedHelperTools/${bundle_id}"* \
  "/Library/PrivilegedHelperTools/${app_name_sans_space}"* \
  "/Library/PrivilegedHelperTools/"*${app_name_sans_space}* \
  "/Library/Internet Plug-Ins/${app_name}"* \
  "/Library/Internet Plug-Ins/"*${app_name}*; do
  for m in $p(N); do
    match_app_token "$m" && helpers+=("$m")
  done
done

# Fallback: add any helper tools that start with the bundle ID prefix (case-insensitive)
bundle_prefix=$(echo "$bundle_id" | tr '[:upper:]' '[:lower:]')
for f in /Library/PrivilegedHelperTools/*; do
  fname=$(basename "$f" 2>/dev/null)
  if [[ -e "$f" && "$fname" == ${bundle_prefix}* && ! " ${helpers[@]} " =~ " $f " ]]; then
    helpers+=("$f")
  fi
done

# --- System files (only app-specific subtrees; preserve spaces) ---
# Exact/common candidates:
for m in \
  "/Library/Application Support/${app_name}" \
  "/Library/Application Support/${vendor_root#*.}/${app_name}" \
  "/Library/${app_name}" \
  "/Library/${vendor_root#*.}/${app_name}" \
  "/Library/Logs/${app_name}"; do
  [[ -e "$m" ]] && system_files+=("$m")
done

# Vendor bases: include only subpaths that match app tokens; up to depth 2
for base in "/Library/Application Support/${vendor_root#*.}" "/Library/${vendor_root#*.}"; do
  [[ -d "$base" ]] || continue
  while IFS= read -r d; do
    match_app_token "$d" && system_files+=("$d")
  done < <(find "$base" -maxdepth 2 -type d 2>/dev/null)
done

# Dedup (split on newlines only; preserve spaces in paths)
receipts=("${(@f)$(printf '%s\n' "${receipts[@]:-}" | order_uniq)}")
launch_agents=("${(@f)$(printf '%s\n' "${launch_agents[@]:-}" | order_uniq)}")
launch_daemons=("${(@f)$(printf '%s\n' "${launch_daemons[@]:-}" | order_uniq)}")
helpers=("${(@f)$(printf '%s\n' "${helpers[@]:-}" | order_uniq)}")
system_files=("${(@f)$(printf '%s\n' "${system_files[@]:-}" | order_uniq)}")


# --- User files template (engine expands %USER_HOME%) ---
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

# ============ LABEL NAMING ============
# Built-in vendor prefix allow-list:
VENDOR_PREFIXES=( microsoft google adobe )

# derive vendor token (2nd part of bundle id)
vendor_token=""
if [[ -n "$bundle_id" ]]; then
  vendor_token="$(echo "$bundle_id" | awk -F. '{print $2}' | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+//g')"
fi

# base from app name (letters+digits only)
base_label="$(echo "$app_name" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+//g')"
if [[ -z "$base_label" && -n "$bundle_id" ]]; then
  base_label="$(echo "${bundle_id##*.}" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+//g')"
fi

# prefix if vendor in allow-list and base doesn't already start with it
should_prefix=0
if [[ -n "$vendor_token" ]]; then
  for v in "${VENDOR_PREFIXES[@]}"; do
    if [[ "$v" == "$vendor_token" ]]; then should_prefix=1; break; fi
  done
fi

if (( should_prefix )) && [[ "$base_label" != ${vendor_token}* ]]; then
  label_guess="${vendor_token}${base_label}"
else
  label_guess="${base_label}"
fi

# Final sanitize (keep a-z0-9 only)
label_guess="$(echo "$label_guess" | sed -E 's/[^a-z0-9]+//g')"

# ============ OUTPUT ============
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

label_file="$out_dir/${label_guess}.sh"
mkdir -p "$out_dir"

# STDOUT
snippet
# Write file (unless --no-write)
if (( no_write == 0 )); then
  snippet > "$label_file"
  print -u2 -- "# Wrote fragment: ${label_file}"
fi
