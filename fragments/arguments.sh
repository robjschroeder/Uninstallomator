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
