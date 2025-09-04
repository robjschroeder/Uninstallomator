#!/bin/zsh --no-rcs

# Uninstallomator
#
# Uninstalls applictions
# 2025 Uninstallomator
#
# Inspired by the Installomator project: https://github.com/Installomator

export PATH=/usr/bin:/bin:/usr/sbin:/sbin


set -e
set -u
set -o pipefail


script_name="uninstallomator"
script_version="0.4.0"
log_file="/var/log/${script_name}.log"
dry_run="false"
force="false"
user_scope="console" # console | all (default console; use --user-scope all for MDM sweeps)

# === LOGGING ===
log() { printf '%s %s\n' "$(/bin/date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$log_file"; }
run() {
local cmd="$*"
if [[ "$dry_run" == "true" ]]; then
log "[DRY-RUN] $cmd"
else
log "> $cmd"
eval "$cmd"
fi
}

# === USER CONTEXT ===
get_current_user(){ /usr/sbin/scutil <<<"show State:/Users/ConsoleUser" | awk '/Name :/ { print $3 }'; }
get_user_uid(){ id -u "$(get_current_user)" 2>/dev/null || echo 501; }
run_as_user(){
local uid; uid=$(get_user_uid)
local cu; cu=$(get_current_user)
if [[ -n "$uid" && -n "$cu" && "$cu" != "loginwindow" && "$cu" != "root" ]]; then
/usr/bin/sudo -u "#${uid}" /usr/bin/env -i HOME="/Users/${cu}" PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin" zsh -lc "$*"
else
# fallback
eval "$*"
fi
}

# --- User-scope helpers ---
list_user_homes(){
dscl . -readall /Users NFSHomeDirectory UniqueID 2>/dev/null \
| awk '/^NFSHomeDirectory:/{home=$2} /^UniqueID:/{uid=$2; if (uid>=500) print home}' \
| sort -u \
| grep -E '^/Users/[^/]+' \
| grep -vE '^/Users/(Shared|Guest)$'
}
expand_user_path_for_home(){
local tpl="$1" home="$2"
printf '%s' "${tpl//%USER_HOME%/$home}"
}

# === HELPERS ===
confirm_rm(){
local target="$1"
if [[ -e "$target" || -L "$target" ]]; then
if [[ "$dry_run" == "true" ]]; then
log "[DRY-RUN] rm -rf -- '$target'"
else
log "> rm -rf -- '$target'"
/bin/rm -rf -- "$target"
fi
else
log "skip rm: $target (not present)"
fi
}
forget_pkg(){ local id="$1"; /usr/sbin/pkgutil --pkgs | /usr/bin/grep -q "^${id}$" && run "/usr/sbin/pkgutil --forget '${id}'" || log "skip forget: ${id} (no receipt)"; }
quit_app(){
local app_id="$1"
[[ -z "$app_id" ]] && return 0
run_as_user "/usr/bin/osascript -e 'tell application id \"$app_id\" to quit'" || true
/bin/sleep 2
if [[ "$force" == "true" ]] && /usr/bin/pgrep -f "$app_id" >/dev/null 2>&1; then
run "/usr/bin/pkill -9 -f '$app_id'" || true
fi
}
unload_launch(){
local plist="$1"
[[ -f "$plist" ]] || return 0
if [[ "$plist" == *"/LaunchAgents/"* ]]; then
run_as_user "/bin/launchctl bootout gui/$(get_user_uid) '$plist'" || true
else
run "/bin/launchctl bootout system '$plist'" || true
fi
run "/bin/rm -f '$plist'" || true
}
remove_profile(){ local identifier="$1"; [[ -z "$identifier" ]] && return 0; /usr/bin/profiles -P | /usr/bin/grep -q "$identifier" && run "/usr/bin/profiles -R -p '$identifier'" || true; }

apply_label() {
  local label="$1"

  # Reset per-run variables
  app_name="" bundle_id="" notes=""
  typeset -a app_paths pkgs files user_files agents daemons profiles
  app_paths=() pkgs=() files=() user_files=() agents=() daemons=() profiles=()

  case $label in
    # BEGIN LABEL CASES
    # === fragment: fragments/labels/adobeacrobatreader.sh ===
    adobeacrobatreader)
        app_name="Acrobat Reader"
        bundle_id="com.adobe.Reader"
        app_paths=(
          "/Applications/Adobe Acrobat Reader.app"
        )
        pkgs=(
          "com.adobe.acrobat.DC.reader.app.pkg.MUI"
          "com.adobe.armdc.app.pkg"
          "com.adobe.acrobat.DC.reader.appsupport.pkg.MUI"
        )
        files=(
          "/Library/Application"
          "Support/adobe/Reader"
          "Support/adobe/Reader/DC"
          "Support/adobe/WebExtnUtils/DC_Reader"
        )
        user_files=(
          "%USER_HOME%/Library/Application Support/Acrobat Reader"
          "%USER_HOME%/Library/Preferences/com.adobe.Reader.plist"
          "%USER_HOME%/Library/Caches/com.adobe.Reader"
          "%USER_HOME%/Library/Logs/Acrobat Reader"
        )
        agents=()
        daemons=()
        profiles=()
    ;;
    
    # === fragment: fragments/labels/base.sh ===
    base)
        app_name="Base"
        bundle_id="uk.co.menial.Base"
        app_paths=(
          "/Applications/Base.app"
        )
        pkgs=()
        files=()
        user_files=(
          "%USER_HOME%/Library/Application Support/Base"
          "%USER_HOME%/Library/Preferences/uk.co.menial.Base.plist"
          "%USER_HOME%/Library/Caches/uk.co.menial.Base"
          "%USER_HOME%/Library/Logs/Base"
        )
        agents=()
        daemons=()
        profiles=()
    ;;
    
    # === fragment: fragments/labels/camostudio.sh ===
    camostudio)
        app_name="Camo Studio"
        bundle_id="com.reincubate.macos.cam"
        app_paths=(
          "/Applications/Camo Studio.app"
        )
        pkgs=()
        files=(
          "/Library/PrivilegedHelperTools/com.reincubate.macos.cam.PrivilegedHelper"
        )
        user_files=(
          "%USER_HOME%/Library/Application Support/Camo Studio"
          "%USER_HOME%/Library/Preferences/com.reincubate.macos.cam.plist"
          "%USER_HOME%/Library/Caches/com.reincubate.macos.cam"
          "%USER_HOME%/Library/Logs/Camo Studio"
        )
        agents=()
        daemons=(
          "/Library/LaunchDaemons/com.reincubate.macos.cam.PrivilegedHelper.plist"
        )
        profiles=()
    ;;
    
    # === fragment: fragments/labels/dfublasterpro.sh ===
    dfublasterpro)
        app_name="DFU Blaster Pro"
        bundle_id="com.twocanoes.DFU-Blaster-Pro"
        app_paths=(
          "/Applications/DFU Blaster Pro.app"
        )
        pkgs=(
          "com.twocanoes.pkg.DFU-Blaster"
        )
        files=()
        user_files=(
          "%USER_HOME%/Library/Application Support/DFU Blaster Pro"
          "%USER_HOME%/Library/Preferences/com.twocanoes.DFU-Blaster-Pro.plist"
          "%USER_HOME%/Library/Caches/com.twocanoes.DFU-Blaster-Pro"
          "%USER_HOME%/Library/Logs/DFU Blaster Pro"
        )
        agents=()
        daemons=()
        profiles=()
    ;;
    
    # === fragment: fragments/labels/googlechrome.sh ===
    googlechrome)
        app_name="Chrome"
        bundle_id="com.google.Chrome"
        app_paths=(
          "/Applications/Google Chrome.app"
        )
        pkgs=(
          "com.google.Chrome"
        )
        files=()
        user_files=(
          "%USER_HOME%/Library/Application Support/Chrome"
          "%USER_HOME%/Library/Preferences/com.google.Chrome.plist"
          "%USER_HOME%/Library/Caches/com.google.Chrome"
          "%USER_HOME%/Library/Logs/Chrome"
        )
        agents=()
        daemons=()
        profiles=()
    ;;
    
    # === fragment: fragments/labels/microsoftedge.sh ===
    microsoftedge)
        app_name="Edge"
        bundle_id="com.microsoft.edgemac"
        app_paths=(
          "/Applications/Microsoft Edge.app"
        )
        pkgs=(
          "com.microsoft.edgemac"
          "com.microsoft.dlp.ux"
          "com.microsoft.dlp.daemon"
          "com.jamf.appinstallers.Edge"
          "com.microsoft.package.Microsoft_Excel.app"
          "com.microsoft.powershell"
          "com.microsoft.CompanyPortalMac"
          "com.microsoft.OneDrive"
          "com.microsoft.wdav"
          "com.microsoft.package.Microsoft_Outlook.app"
          "com.microsoft.dlp.agent"
          "com.jamf.appinstallers.MicrosoftEdge"
          "com.microsoft.package.Microsoft_AutoUpdate.app"
          "com.microsoft.MSTeamsAudioDevice"
          "com.microsoft.pkg.licensing"
          "com.microsoft.teams2"
        )
        files=(
          "/Library/microsoft/Edge"
          "/Library/Application"
          "Support/microsoft/EdgeUpdater"
          "Support/microsoft/EdgeUpdater/118.0.2088.86"
          "/Library/microsoft/Edge/NativeMessagingHosts"
        )
        user_files=(
          "%USER_HOME%/Library/Application Support/Edge"
          "%USER_HOME%/Library/Preferences/com.microsoft.edgemac.plist"
          "%USER_HOME%/Library/Caches/com.microsoft.edgemac"
          "%USER_HOME%/Library/Logs/Edge"
        )
        agents=()
        daemons=(
          "/Library/LaunchDaemons/com.microsoft.EdgeUpdater.wake.system.plist"
        )
        profiles=()
    ;;
    
    # === fragment: fragments/labels/mist.sh ===
    mist)
        app_name="Mist"
        bundle_id="com.ninxsoft.mist"
        app_paths=(
          "/Applications/Mist.app"
        )
        pkgs=()
        files=(
          "/Library/PrivilegedHelperTools/com.ninxsoft.mist.helper"
        )
        user_files=(
          "%USER_HOME%/Library/Application Support/Mist"
          "%USER_HOME%/Library/Preferences/com.ninxsoft.mist.plist"
          "%USER_HOME%/Library/Caches/com.ninxsoft.mist"
          "%USER_HOME%/Library/Logs/Mist"
        )
        agents=()
        daemons=(
          "/Library/LaunchDaemons/com.ninxsoft.mist.helper.plist"
        )
        profiles=()
    ;;
    
    # === fragment: fragments/labels/postman.sh ===
    postman)
        app_name="Postman"
        bundle_id="com.postmanlabs.mac"
        app_paths=(
          "/Applications/Postman.app"
        )
        pkgs=(
          "com.jamf.appinstallers.Postman"
        )
        files=()
        user_files=(
          "%USER_HOME%/Library/Application Support/Postman"
          "%USER_HOME%/Library/Preferences/com.postmanlabs.mac.plist"
          "%USER_HOME%/Library/Caches/com.postmanlabs.mac"
          "%USER_HOME%/Library/Logs/Postman"
        )
        agents=()
        daemons=(
          "/Library/LaunchDaemons/com.reincubate.macos.cam.PrivilegedHelper.plist"
        )
        profiles=()
    ;;
    
    # === fragment: fragments/labels/slack.sh ===
    slack)
        app_name="Slack"
        bundle_id="com.tinyspeck.slackmacgap"
        app_paths=(
          "/Applications/Slack.app"
        )
        pkgs=(
          "com.jamf.appinstallers.Slack"
        )
        files=()
        user_files=(
          "%USER_HOME%/Library/Application Support/Slack"
          "%USER_HOME%/Library/Preferences/com.tinyspeck.slackmacgap.plist"
          "%USER_HOME%/Library/Caches/com.tinyspeck.slackmacgap"
          "%USER_HOME%/Library/Logs/Slack"
        )
        agents=()
        daemons=()
        profiles=()
    ;;
    
    # === fragment: fragments/labels/spotify.sh ===
    spotify)
        app_name="Spotify"
        bundle_id="com.spotify.client"
        app_paths=(
          "/Applications/Spotify.app"
        )
        pkgs=(
          "com.jamf.appinstallers.Spotify"
        )
        files=()
        user_files=(
          "%USER_HOME%/Library/Application Support/Spotify"
          "%USER_HOME%/Library/Preferences/com.spotify.client.plist"
          "%USER_HOME%/Library/Caches/com.spotify.client"
          "%USER_HOME%/Library/Logs/Spotify"
        )
        agents=()
        daemons=(
          "/Library/LaunchDaemons/com.mann.JamfClientCommunicationsDoctor.plist"
        )
        profiles=()
    ;;
    
    # === fragment: fragments/labels/suspiciouspackage.sh ===
    suspiciouspackage)
        app_name="Suspicious Package"
        bundle_id="com.mothersruin.SuspiciousPackageApp"
        app_paths=(
          "/Applications/Suspicious Package.app"
        )
        pkgs=()
        files=()
        user_files=(
          "%USER_HOME%/Library/Application Support/Suspicious Package"
          "%USER_HOME%/Library/Preferences/com.mothersruin.SuspiciousPackageApp.plist"
          "%USER_HOME%/Library/Caches/com.mothersruin.SuspiciousPackageApp"
          "%USER_HOME%/Library/Logs/Suspicious Package"
        )
        agents=()
        daemons=()
        profiles=()
    ;;
    
    # === fragment: fragments/labels/zoomus.sh ===
    zoomus)
        app_name="zoom.us"
        bundle_id="us.zoom.xos"
        app_paths=(
          "/Applications/zoom.us.app"
        )
        pkgs=(
          "us.zoom.pkg.videomeeting"
        )
        files=()
        user_files=(
          "%USER_HOME%/Library/Application Support/zoom.us"
          "%USER_HOME%/Library/Preferences/us.zoom.xos.plist"
          "%USER_HOME%/Library/Caches/us.zoom.xos"
          "%USER_HOME%/Library/Logs/zoom.us"
        )
        agents=()
        daemons=()
        profiles=()
    ;;
    
    # END LABEL CASES
    *)
      log "ERROR: Unknown label: $label"; exit 2
    ;;

  esac

  # === Execute ===
  log "== Uninstalling: ${app_name:-$label} =="

  [[ -n "$bundle_id" ]] && quit_app "$bundle_id"

  # run vendor-provided uninstallers first (if any)
  local p id

  # unload launch items
  for p in "${agents[@]}";  do [[ -n "$p" ]] && unload_launch "$p"; done
  for p in "${daemons[@]}"; do [[ -n "$p" ]] && unload_launch "$p"; done

  # remove app bundles and files
  for p in "${app_paths[@]}"; do [[ -n "$p" ]] && confirm_rm "$p"; done
  for p in "${files[@]}";     do [[ -n "$p" ]] && confirm_rm "$p"; done

  # per-user debris (supports console|all via %USER_HOME%)
  if [[ "$user_scope" == "all" ]]; then
    local uh tgt
    for p in "${user_files[@]}"; do
      [[ -z "$p" ]] && continue
      if [[ "$p" == %USER_HOME%* ]]; then
        while IFS= read -r uh; do
          tgt="$(expand_user_path_for_home "$p" "$uh")"
          [[ -n "$tgt" ]] && run "/bin/rm -rf -- '$tgt'"
        done < <(list_user_homes)
      else
        run "/bin/rm -rf -- '$p'"
      fi
    done
  else
    local cu_home="/Users/$(get_current_user)" tgt
    for p in "${user_files[@]}"; do
      [[ -z "$p" ]] && continue
      if [[ "$p" == %USER_HOME%* ]]; then
        tgt="$(expand_user_path_for_home "$p" "$cu_home")"
      elif [[ "$p" == ~/* ]]; then
        tgt="${p/#~\//$cu_home/}"
      else
        tgt="$p"
      fi
      [[ -n "$tgt" ]] && run_as_user "/bin/rm -rf -- '$tgt'"
    done
  fi

  # receipts and profiles
  for id in "${pkgs[@]}";    do [[ -n "$id" ]] && forget_pkg "$id"; done
  for id in "${profiles[@]}"; do [[ -n "$id" ]] && remove_profile "$id"; done

  log "== Completed: ${app_name:-$label} =="
}


# === CLI ===
usage(){
cat <<USAGE
${script_name} v${script_version}
Usage:
${script_name} --label <label> [--dry-run] [--force] [--user-scope console|all]
USAGE
}

main(){
  local label=""   # <— add this
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --label) label="$2"; shift 2;;
      --dry-run) dry_run="true"; shift;;
      --force) force="true"; shift;;
      --user-scope) user_scope="$2"; shift 2;;
      -h|--help) usage; exit 0;;
      *) log "Unknown arg: $1"; usage; exit 2;;
    esac
  done
  if [[ -z "$label" ]]; then usage; exit 2; fi
  apply_label "$label"
}


main "$@"
