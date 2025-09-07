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
