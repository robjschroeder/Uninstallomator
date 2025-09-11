#!/bin/zsh --no-rcs
label="" # if no label is sent to the script, this will be used

# Uninstallomator
#
# Uninstalls applications
# 2025 Uninstallomator
#
# Inspired by the Installomator project: https://github.com/Installomator

export PATH=/usr/bin:/bin:/usr/sbin:/sbin

# NOTE: adjust these variables:

# set to 0 for production, 1 for debugging
# while debugging, affected files will be listed, but
# also no actual uninstallation will be performed
DEBUG=1

# notify behavior
NOTIFY=success
# options:
#   - success      notify the user on success
#   - silent       no notifications
#   - all          all notifications (great for Self Service installation)

# logo-icon used in dialog boxes if app is blocking
LOGO=appstore
# options:
#   - appstore      Icon is Apple App Store (default)
#   - jamf          JAMF Pro
#   - mosyleb       Mosyle Business
#   - mosylem       Mosyle Manager (Education)
#   - addigy        Addigy
#   - microsoft     Microsoft Endpoint Manager (Intune)
#   - ws1           Workspace ONE (AirWatch)
#   - filewave      FileWave
#   - kandji        Kandji
# path can also be set in the command call, and if file exists, it will be used.
# Like 'LOGO="/System/Applications/App\ Store.app/Contents/Resources/AppIcon.icns"'
# (spaces have to be escaped).

# User Scope
USERSCOPE=0
# options:
#  - 0             Runs uninstall as the current user (default).
#  - 1             Uninstalls for all users.

#
### Logging
# Logging behavior
LOGGING="INFO"
# options:
#   - DEBUG     Everything is logged
#   - INFO      (default) normal logging level
#   - WARN      only warning
#   - ERROR     only errors
#   - REQ       ????

# Log Date format used when parsing logs for debugging, this is the default used by
# install.log, override this in the case statements if you need something custom per
# application (See adobeillustrator).  Using stadard GNU Date formatting.
LogDateFormat="%Y-%m-%d %H:%M:%S"

# Get the start time for parsing install.log if we fail.
starttime=$(date "+$LogDateFormat")

# Check if we have rosetta installed
if [[ $(/usr/bin/arch) == "arm64" ]]; then
    if ! arch -x86_64 /usr/bin/true >/dev/null 2>&1; then # pgrep oahd >/dev/null 2>&1
        rosetta2=no
    fi
fi
VERSION="1.1.3"
VERSIONDATE="2025-09-11"


# MARK: Functions

# --- Logging ---
# levels: DEBUG < INFO < WARN < ERROR < REQ
declare -A levels=( [DEBUG]=0 [INFO]=1 [WARN]=2 [ERROR]=3 [REQ]=4 )
log_location="/private/var/log/Uninstallomator.log"

printlog() { # $1 message, $2 level (default INFO)
  local msg="$1" lvl="${2:-INFO}" ts
  ts=$(date +%F\ %T)

  # de-dup consecutive lines
  if [[ "$msg" == "${previous_log_message:-}" ]]; then
    ((logrepeat=logrepeat+1))
    return
  fi
  if (( logrepeat > 1 )); then
    echo "$ts : ${lvl} : $label : Last Log repeated ${logrepeat} times" | tee -a "$log_location"
    logrepeat=0
  fi
  previous_log_message="$msg"

  # honor LOGGING threshold
  if (( ${levels[$lvl]:-1} >= ${levels[${LOGGING:-INFO}]:-1} )); then
    if [[ $EUID -eq 0 ]]; then
      echo "$ts : ${lvl} : $label : $msg" | tee -a "$log_location"
    else
      echo "$ts : ${lvl} : $label : $msg"
    fi
  fi
}

# --- Cleanup and exit ---
cleanupAndExit() { # $1 code, $2 message, $3 level (default INFO)
  local code="${1:-0}" msg="${2:-}" lvl="${3:-INFO}"
  [[ -n "$msg" ]] && printlog "$msg" "$lvl"
  printlog "################## End Uninstallomator, exit code $code" REQ
  exit "$code"
}

# --- Current user / run as user ---
get_current_user() { scutil <<<"show State:/Users/ConsoleUser" | awk '/Name :/ {print $3}'; }
runAsUser() {
  local cu; cu=$(get_current_user)
  [[ -z "$cu" || "$cu" == "loginwindow" ]] && return 0
  local uid; uid=$(id -u "$cu")
  launchctl asuser "$uid" sudo -u "$cu" "$@"
}

# --- Notifications (optional) ---
displaynotification(){ # $1 msg, $2 title
  local message="${1:-Message}" title="${2:-Notification}"
  local manageaction="/Library/Application Support/JAMF/bin/Management Action.app/Contents/MacOS/Management Action"
  local hubcli="/usr/local/bin/hubcli" swiftdialog="/usr/local/bin/dialog"
  if [[ -x "$swiftdialog" && "${NOTIFY_DIALOG:-0}" -eq 1 ]]; then
    "$swiftdialog" --notification --title "$title" --message "$message"
  elif [[ -x "$manageaction" ]]; then
    "$manageaction" -message "$message" -title "$title" &
  elif [[ -x "$hubcli" ]]; then
    "$hubcli" notify -t "$title" -i "$message" -c "Dismiss"
  else
    runAsUser osascript -e "display notification \"$message\" with title \"$title\""
  fi
}

# --- Blocking processes (simple kill policy; extend later if needed) ---
checkRunningProcesses() {
  # DEBUG==1 → skip enforcement
  [[ "${DEBUG:-0}" -eq 1 ]] && { printlog "DEBUG mode: skipping blocking process checks" DEBUG; return; }
  local counted=0 x
  for _ in {1..4}; do
    for x in "${blockingProcesses[@]}"; do
      [[ "$x" == "NONE" || -z "$x" ]] && continue
      if pgrep -xq "$x"; then
        printlog "Found blocking process: $x" INFO
        pkill "$x" || true
        sleep 5
        ((counted++))
      fi
    done
  done
  if (( counted > 0 )) && pgrep -fq "${bundle_id:-__nope__}"; then
    cleanupAndExit 11 "Could not quit all processes for $app_name; aborting." ERROR
  fi
  printlog "No blocking processes remain" INFO
}

# --- Launchd unload + file removal + receipts ---
unload_launch(){
  local p="$1"
  [[ -f "$p" ]] || return 0
  if [[ "$p" == *"/LaunchAgents/"* ]]; then
    local cu; cu=$(get_current_user); local uid; uid=$(id -u "$cu" 2>/dev/null || echo 501)
    runAsUser launchctl bootout "gui/$uid" "$p" || true
  else
    launchctl bootout system "$p" || true
  fi
  rm -f -- "$p" || true
}

# --- File removal (with confirmation and debug support) ---
confirm_rm(){
  local t="$1"
  if [[ -e "$t" || -L "$t" ]]; then
    if [[ "${DEBUG:-0}" -eq 1 ]]; then
      printlog "[DEBUG] would remove: $t" DEBUG
    else
      printlog "Removing: $t" INFO
      rm -rf -- "$t" || true
    fi
  fi
}

# --- Receipts ---
forget_pkg(){
  local id="$1"
  if pkgutil --pkgs | grep -qx "$id"; then
    if [[ "${DEBUG:-0}" -eq 1 ]]; then
      printlog "[DEBUG] would pkgutil --forget '$id'" DEBUG
    else
      pkgutil --forget "$id" || true
    fi
  fi
}

# --- Userscope helpers ---
list_user_homes(){
  dscl . -readall /Users NFSHomeDirectory UniqueID 2>/dev/null \
  | awk '/^NFSHomeDirectory:/{h=$2} /^UniqueID:/{uid=$2; if (uid>=500) print h}' \
  | sort -u | grep -E '^/Users/[^/]+' | grep -vE '^/Users/(Shared|Guest)$'
}
expand_user_path(){
  local tpl="$1" home="$2"
  printf '%s' "${tpl//%USER_HOME%/$home}"
}

# --- Uninstall engine (runs after label case sets arrays) ---
do_uninstall(){
  # sanity for arrays
  (( ${#app_paths[@]} == 0 ))   && cleanupAndExit 1 "Label missing app_paths" ERROR
  [[ -z "${bundle_id:-}" ]]     && cleanupAndExit 1 "Label missing bundle_id" ERROR
  [[ -z "${app_name:-}" ]]      && app_name="$bundle_id"

  # optional notification at start
  [[ "${NOTIFY:-silent}" != "silent" && "${NOTIFY:-silent}" != "none" && "${NOTIFY:-silent}" != "error" ]] \
    && displaynotification "Removing ${app_name}…" "Uninstallomator"

  # Kill/quit processes (basic)
  blockingProcesses=("${blockingProcesses[@]:-}" "${app_name}")
  checkRunningProcesses

  # unload launch items
  local p
  for p in "${agents[@]:-}";  do [[ -n "$p" ]] && unload_launch "$p"; done
  for p in "${daemons[@]:-}"; do [[ -n "$p" ]] && unload_launch "$p"; done

  # remove app bundles and system files
  found=0
  for p in "${app_paths[@]}"; do [[ -n "$p" && -e "$p" ]] && found=1; done
  if (( found == 0 )); then cleanupAndExit 0 "$app_name not found in defined app paths" ERROR; fi
  for p in "${app_paths[@]}"; do [[ -n "$p" ]] && confirm_rm "$p"; done
  for p in "${files[@]:-}";   do [[ -n "$p" ]] && confirm_rm "$p"; done

  # per-user files
  if [[ "${USERSCOPE:-0}" -eq 1 ]]; then
    local uh tgt
    while IFS= read -r uh; do
      for p in "${user_files[@]:-}"; do
        [[ -z "$p" ]] && continue
        tgt="$(expand_user_path "$p" "$uh")"
        [[ -n "$tgt" ]] && confirm_rm "$tgt"
      done
    done < <(list_user_homes)
  else
    local cu_name; cu_name="$(get_current_user)"
   if [[ "$cu_name" == "loginwindow" || -z "$cu_name" ]]; then
     printlog "No user session; skipping per-user file removals (USERSCOPE=0)" INFO
   else
     local cu_home="/Users/$cu_name" tgt
    for p in "${user_files[@]:-}"; do
      [[ -z "$p" ]] && continue
      if [[ "$p" == %USER_HOME%* ]]; then
        tgt="$(expand_user_path "$p" "$cu_home")"
      elif [[ "$p" == ~/* ]]; then
        tgt="${p/#~\//$cu_home/}"
      else
        tgt="$p"
      fi
      [[ -n "$tgt" ]] && confirm_rm "$tgt"
    done
   fi
  fi

  # receipts
  local id
  for id in "${pkgs[@]:-}"; do [[ -n "$id" ]] && forget_pkg "$id"; done

  # success check: nothing blocking remains and app bundles are gone (best-effort)
  local any_left=0
  for p in "${app_paths[@]}"; do [[ -e "$p" ]] && any_left=1; done

  if (( any_left == 0 )); then
    [[ "${NOTIFY:-silent}" == "success" || "${NOTIFY:-silent}" == "all" ]] \
      && displaynotification "${app_name} removed." "Uninstall complete"
    printlog "Completed uninstall of ${app_name}" REQ
    return 0
  else
    [[ "$(get_current_user)" != "loginwindow" && "${NOTIFY:-silent}" == "all" ]] \
      && displaynotification "Failed to remove ${app_name}" "Uninstall failed"
    cleanupAndExit 1 "Some app bundles still present for ${app_name}" ERROR
  fi
}
# NOTE: check minimal macOS requirement
autoload -Uz is-at-least

installedOSVersion=$(sw_vers -productVersion)
if ! is-at-least "10.14" $installedOSVersion; then
    printlog "Uninstallomator requires at least macOS 10.14 Mojave." ERROR
    exit 98
fi

# MARK: argument parsing
if [[ $# -eq 0 ]]; then 
    if [[ -z $label ]]; then
        printlog "No label provided, printing labels" REQ
        grep -E '^[[:space:]]*[a-z0-9-]+\)[[:space:]]*$' "$0" | sed -E 's/^[[:space:]]*([a-z0-9-]+)\).*/\1/' | sort -u
        exit 0
    fi
elif [[ $1 == "/" ]]; then
    # jamf users sends '/' as the first argument
    printlog "Shifting arguments for Jamf" REQ
    shift 3
fi

# First argument is the label
label=$1

# lowercase the label
label=${label:l}

# MARK: Reading rest of the arguments
argumentsArray=()
while [[ -n $1 ]]; do
    if [[ $1 =~ ".*\=.*" ]]; then
        # if an argument contains an = character, send it to eval
        printlog "setting variable from argument $1" INFO
        argumentsArray+=( $1 )
        eval $1
    fi
    # shift to next argument
    shift 1
done
printlog "Total items in argumentsArray: ${#argumentsArray[@]}" INFO
printlog "argumentsArray: ${argumentsArray[*]}" INFO

# MARK: Logging
log_location="/private/var/log/Uninstallomator.log"

# Check if we're in debug mode, if so then set logging to DEBUG, otherwise default to INFO
if [[ $DEBUG -ne 0 ]]; then
    LOGGING="DEBUG"
else
    LOGGING="INFO"
fi

# Associate logging levels with a numerical value so that we are able to identify what
# should be removed. For example if the LOGGING=ERROR only printlog statements with the
# level REQ and ERROR will be displayed. LOGGING=DEBUG will show all printlog statements.
# If a printlog statement has no level set it's automatically assigned INFO.

# If we are able to detect an MDM URL (Jamf Pro) or another identifier for a customer/instance we grab it here, this is useful if we're centrally logging multiple MDM instances.
if [[ -f /Library/Preferences/com.jamfsoftware.jamf.plist ]]; then
    mdmURL=$(defaults read /Library/Preferences/com.jamfsoftware.jamf.plist jss_url)
elif [[ -n "$MDMProfileName" ]]; then
    mdmURL=$(sudo profiles show | grep -A3 "$MDMProfileName" | sed -n -e 's/^.*organization: //p')
else
    mdmURL="Unknown"
fi

# Generate a session key for this run, this is useful to idenify streams when we're centrally logging.
SESSION=$RANDOM

# MARK: START
printlog "################## Start Uninstallomator" REQ
printlog "################## Version: $VERSION" INFO
printlog "################## Date: $VERSIONDATE" INFO
printlog "################## $label" INFO

# Check for DEBUG mode
if [[ $DEBUG -gt 0 ]]; then
    printlog "DEBUG mode $DEBUG enabled." DEBUG
fi

# NOTE: check for root
if [[ $EUID -ne 0 && "$DEBUG" -eq 0 ]]; then
    # not running as root
    cleanupAndExit 6 "not running as root, exiting" ERROR
fi

# MARK: labels in case statement
case $label in
longversion)
    # print the script version
    printlog "Uninstallomator: version $VERSION ($VERSIONDATE)" REQ
    exit 0
    ;;
valuesfromarguments)
    # no action necessary, all values should be provided in arguments
    ;;

# label descriptions start here

adobeacrobat)
    app_name="Acrobat"
    bundle_id="com.adobe.Acrobat.Pro"
    app_paths=(
      "/Applications/Adobe Acrobat DC/Adobe Acrobat.app"
    )
    pkgs=()
    files=(
      "/Library/Application Support/adobe/Acrobat"
      "/Library/Application Support/adobe/Color/Profiles"
      "/Library/Application Support/adobe/Acrobat/DC"
      "/Library/Application Support/adobe/Acrobat DC Helper Frameworks"
      "/Library/Application Support/adobe/Acrobat DC Helper Frameworks/adobe_zxpsignlib"
      "/Library/Application Support/adobe/Acrobat DC Helper Frameworks/IMSLib"
      "/Library/Application Support/adobe/ARMDC/Registered Products"
    )
    user_files=(
      "%USER_HOME%/Library/Application Support/Acrobat"
      "%USER_HOME%/Library/Preferences/com.adobe.Acrobat.Pro.plist"
      "%USER_HOME%/Library/Caches/com.adobe.Acrobat.Pro"
      "%USER_HOME%/Library/Logs/Acrobat"
    )
    agents=(
      "/Library/LaunchAgents/com.adobe.ccxprocess.plist"
    )
    daemons=()
    profiles=()
;;
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
      "/Library/Application Support/adobe/Reader"
      "/Library/Application Support/adobe/Reader/DC"
      "/Library/Application Support/adobe/WebExtnUtils/DC_Reader"
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
charles)
    app_name="Charles"
    bundle_id="com.xk72.Charles"
    app_paths=(
      "/Applications/Charles.app"
    )
    pkgs=()
    files=(
      "/Library/PrivilegedHelperTools/com.xk72.charles.ProxyHelper"
    )
    user_files=(
      "%USER_HOME%/Library/Application Support/Charles"
      "%USER_HOME%/Library/Preferences/com.xk72.Charles.plist"
      "%USER_HOME%/Library/Caches/com.xk72.Charles"
      "%USER_HOME%/Library/Logs/Charles"
    )
    agents=()
    daemons=(
      "/Library/LaunchDaemons/com.xk72.charles.ProxyHelper.plist"
    )
    profiles=()
;;
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
microsoftcompanyportal)
    app_name="Company Portal"
    bundle_id="com.microsoft.CompanyPortalMac"
    app_paths=(
      "/Applications/Company Portal.app"
    )
    pkgs=(
      "com.microsoft.CompanyPortalMac"
    )
    files=()
    user_files=(
      "%USER_HOME%/Library/Application Support/Company Portal"
      "%USER_HOME%/Library/Preferences/com.microsoft.CompanyPortalMac.plist"
      "%USER_HOME%/Library/Caches/com.microsoft.CompanyPortalMac"
      "%USER_HOME%/Library/Logs/Company Portal"
    )
    agents=()
    daemons=()
    profiles=()
;;
microsoftedge)
    app_name="Edge"
    bundle_id="com.microsoft.edgemac"
    app_paths=(
      "/Applications/Microsoft Edge.app"
    )
    pkgs=(
      "com.microsoft.edgemac"
    )
    files=(
      "/Library/microsoft/Edge"
      "/Library/Application Support/microsoft/EdgeUpdater"
      "/Library/Application Support/microsoft/EdgeUpdater/118.0.2088.86"
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
      "/Library/LaunchDaemons/com.jamf.appinstallers.MicrosoftEdge.plist"
    )
    profiles=()
;;
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
*)
    # unknown label
    #printlog "unknown label $label"
    cleanupAndExit 1 "unknown label $label" ERROR
    ;;
esac

# MARK: reading arguments again
printlog "Reading arguments again: ${argumentsArray[*]}" INFO
for argument in ${argumentsArray[@]}; do
    printlog "argument: $argument" DEBUG
    eval $argument
done

# Verify we have everything we need
if [[ -z $app_name ]]; then
    printlog "Need to provide 'app_name'" ERROR
    exit 1
fi

if (( ${#app_paths[@]} == 0 )); then
    printlog "Need to provide 'app_path'" ERROR
    exit 1
fi

if [[ -z $bundle_id ]]; then
    printlog "Need to provide 'bundle_id'" ERROR
    exit 1
fi

# MARK: application uninstall starts here

# Debug output of all variables in label
printlog "app_name: $app_name" DEBUG
printlog "bundle_id: $bundle_id" DEBUG
printlog "app_paths: ${app_paths[*]}" DEBUG
printlog "pkgs: ${pkgs[*]}" DEBUG
printlog "files: ${files[*]}" DEBUG
printlog "user_files: ${user_files[*]}" DEBUG
printlog "agents: ${agents[*]}" DEBUG
printlog "daemons: ${daemons[*]}" DEBUG
printlog "profiles: ${profiles[*]}" DEBUG

printlog "NOTIFY=${NOTIFY}"
printlog "LOGGING=${LOGGING}"

# NOTE: Finding LOGO to use in dialogs
case $LOGO in
    appstore)
        # Apple App Store on Mac
        if [[ $(sw_vers -buildVersion) > "19" ]]; then
            LOGO="/System/Applications/App Store.app/Contents/Resources/AppIcon.icns"
        else
            LOGO="/Applications/App Store.app/Contents/Resources/AppIcon.icns"
        fi
        ;;
    jamf)
        # Jamf Pro
        LOGO="/Library/Application Support/JAMF/Jamf.app/Contents/Resources/AppIcon.icns"
        ;;
    mosyleb)
        # Mosyle Business
        LOGO="/Applications/Self-Service.app/Contents/Resources/AppIcon.icns"
        if [[ -z $MDMProfileName ]]; then; MDMProfileName="Mosyle Corporation MDM"; fi
        ;;
    mosylem)
        # Mosyle Manager (education)
        LOGO="/Applications/Manager.app/Contents/Resources/AppIcon.icns"
        if [[ -z $MDMProfileName ]]; then; MDMProfileName="Mosyle Corporation MDM"; fi
        ;;
    addigy)
        # Addigy
        LOGO="/Library/Addigy/macmanage/MacManage.app/Contents/Resources/atom.icns"
        if [[ -z $MDMProfileName ]]; then; MDMProfileName="MDM Profile"; fi
        ;;
    microsoft)
        # Microsoft Endpoint Manager (Intune)
        if [[ -d "/Library/Intune/Microsoft Intune Agent.app" ]]; then
            LOGO="/Library/Intune/Microsoft Intune Agent.app/Contents/Resources/AppIcon.icns"
        elif [[ -d "/Applications/Company Portal.app" ]]; then
            LOGO="/Applications/Company Portal.app/Contents/Resources/AppIcon.icns"
        fi
        if [[ -z $MDMProfileName ]]; then; MDMProfileName="Management Profile"; fi
        ;;
    ws1)
        # Workspace ONE (AirWatch)
        LOGO="/Applications/Workspace ONE Intelligent Hub.app/Contents/Resources/AppIcon.icns"
        if [[ -z $MDMProfileName ]]; then; MDMProfileName="Device Manager"; fi
        ;;
    kandji)
        # Kandji
        LOGO="/Applications/Kandji Self Service.app/Contents/Resources/AppIcon.icns"
        if [[ -z $MDMProfileName ]]; then; MDMProfileName="MDM Profile"; fi
        ;;
    filewave)
        # FileWave
        LOGO="/usr/local/sbin/FileWave.app/Contents/Resources/fwGUI.app/Contents/Resources/kiosk.icns"
        if [[ -z $MDMProfileName ]]; then; MDMProfileName="FileWave MDM Configuration"; fi
        ;;
esac
if [[ ! -a "${LOGO}" ]]; then
    if [[ $(sw_vers -buildVersion) > "19" ]]; then
        LOGO="/System/Applications/App Store.app/Contents/Resources/AppIcon.icns"
    else
        LOGO="/Applications/App Store.app/Contents/Resources/AppIcon.icns"
    fi
fi
printlog "LOGO=${LOGO}" INFO

if (( ${#blockingProcesses[@]} == 0 )); then
    printlog "no blocking processes defined" INFO
fi

# MARK: when user is logged in, and app is running, prompt user to quit app

if [[ $(get_current_user) != "loginwindow" ]]; then
    if (( ${#blockingProcesses[@]} > 0 )); then
        if [[ ${blockingProcesses[1]} != "NONE" ]]; then
            checkRunningProcesses
        fi
    fi
fi


# MARK: uninstall the app
printlog "Uninstalling ${app_name} (${bundle_id})" INFO
do_uninstall || cleanupAndExit 1 "Failed uninstall: ${app_name}" ERROR

# All Done
cleanupAndExit 0 "All done!" REQ
