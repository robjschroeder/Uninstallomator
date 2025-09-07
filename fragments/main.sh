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