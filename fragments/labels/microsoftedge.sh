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
