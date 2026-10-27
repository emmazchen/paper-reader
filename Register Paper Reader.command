#!/bin/zsh
app_path="$HOME/Applications/Paper Reader.app"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$app_path"
if [[ $? -eq 0 ]]; then
    print 'Paper Reader registered. Open the PDF’s Open With menu again.'
else
    print 'macOS could not register the app. Launching it may let Finder discover it.'
fi
open "$app_path"
