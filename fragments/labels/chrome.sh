chrome)
    app_name="Chrome"
    bundle_id="com.google.Chrome"
    app_paths=(
      "/Applications/Google Chrome.app"
    )
    pkgs=(
      "com.google.Chrome"
    )
    files=(
      "/Library/Application Support/google"
      "/Library/google"
    )
    user_files=(
      "%USER_HOME%/Library/Application Support/Chrome"
      "%USER_HOME%/Library/Preferences/com.google.Chrome.plist"
      "%USER_HOME%/Library/Caches/com.google.Chrome"
      "%USER_HOME%/Library/Logs/Chrome"
    )
    agents=(
      "/Library/LaunchAgents/com.google.keystone.xpcservice.plist"
      "/Library/LaunchAgents/com.google.keystone.agent.plist"
    )
    daemons=(
      "/Library/LaunchDaemons/com.google.GoogleUpdater.wake.system.plist"
      "/Library/LaunchDaemons/com.google.keystone.daemon.plist"
    )
    profiles=()
;;
