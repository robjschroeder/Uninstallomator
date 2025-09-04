acrobat-reader)
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
      "/Library/Application Support/adobe"
    )
    user_files=(
      "%USER_HOME%/Library/Application Support/Acrobat Reader"
      "%USER_HOME%/Library/Preferences/com.adobe.Reader.plist"
      "%USER_HOME%/Library/Caches/com.adobe.Reader"
      "%USER_HOME%/Library/Logs/Acrobat Reader"
    )
    agents=(
      "/Library/LaunchAgents/com.adobe.AdobeCreativeCloud.plist"
      "/Library/LaunchAgents/com.adobe.ccxprocess.plist"
      "/Library/LaunchAgents/com.adobe.GC.Invoker-1.0.plist"
      "/Library/LaunchAgents/com.adobe.ARMDCHelper.cc24aef4a1b90ed56a725c38014c95072f92651fb65e1bf9c8e43c37a23d420d.plist"
    )
    daemons=(
      "/Library/LaunchDaemons/com.adobe.agsservice.plist"
      "/Library/LaunchDaemons/com.adobe.ARMDC.SMJobBlessHelper.plist"
      "/Library/LaunchDaemons/com.adobe.ARMDC.Communicator.plist"
      "/Library/LaunchDaemons/com.adobe.acc.installer.v2.plist"
    )
    profiles=()
;;
