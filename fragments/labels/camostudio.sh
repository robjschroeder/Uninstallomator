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
