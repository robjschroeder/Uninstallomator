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
