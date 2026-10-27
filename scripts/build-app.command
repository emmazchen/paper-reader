#!/bin/zsh
set -eu
cd "${0:A:h:h}"
project_app="$PWD/Paper Reader.app"
installed_app="$HOME/Applications/Paper Reader.app"
build_binary=$(mktemp "$PWD/.PaperReader-build.XXXXXX")
trap 'rm -f "$build_binary"' EXIT
swiftc main.swift Search.swift CaptionDetector.swift BalancedSplitView.swift HighlightStore.swift -o "$build_binary" -framework AppKit -framework PDFKit -framework NaturalLanguage
mkdir -p "$project_app/Contents/MacOS"
cp resources/Info.plist "$project_app/Contents/Info.plist"
chmod +x "$build_binary"
mv -f "$build_binary" "$project_app/Contents/MacOS/PaperReader"
codesign --force --deep --sign - "$project_app"
if [[ ! -d "$installed_app" ]]; then
    mkdir -p "$HOME/Applications"
    ditto "$project_app" "$installed_app"
else
    # Replace atomically, so a running copy can finish using its old binary.
    cp "$project_app/Contents/MacOS/PaperReader" "$installed_app/Contents/MacOS/PaperReader.new"
    mv -f "$installed_app/Contents/MacOS/PaperReader.new" "$installed_app/Contents/MacOS/PaperReader"
    codesign --force --deep --sign - "$installed_app"
fi
print 'Updated project and Applications copies. Quit and reopen Paper Reader to load the update.'
