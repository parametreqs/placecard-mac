#!/bin/zsh
set -eu
cd "${0:A:h}"
swift build -c release --arch arm64
binary_dir=$(swift build -c release --arch arm64 --show-bin-path)
app="dist/PlaceCard Mac.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary_dir/PlaceCardMac" "$app/Contents/MacOS/PlaceCardMac"
/usr/bin/strip -S "$app/Contents/MacOS/PlaceCardMac"
cp LICENSE "$app/Contents/Resources/LICENSE"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>io.github.parametreqs.PlaceCardMac</string>
<key>CFBundleName</key><string>PlaceCard Mac</string>
<key>CFBundleDisplayName</key><string>PlaceCard for Mac</string>
<key>CFBundleExecutable</key><string>PlaceCardMac</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.3.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - --identifier io.github.parametreqs.PlaceCardMac "$app"
codesign --verify --strict "$app"
ditto -c -k --sequesterRsrc --keepParent "$app" "dist/PlaceCard-Mac-arm64.zip"
(cd dist && shasum -a 256 PlaceCard-Mac-arm64.zip > SHA256SUMS.txt)
print "Built $PWD/$app"
