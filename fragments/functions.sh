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