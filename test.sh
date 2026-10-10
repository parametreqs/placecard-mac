#!/bin/zsh
set -eu
cd "${0:A:h}"
# Explicit plugin discovery works around missing TestingMacros discovery in the macOS 27 CLT build backend.
swift_compiler=$(xcrun --find swiftc)
toolchain_bin=${swift_compiler:h}
if [[ -d "$toolchain_bin/../lib/swift/host/plugins/testing" ]]; then
    swift test --disable-xctest -Xswiftc -external-plugin-path -Xswiftc "$toolchain_bin/../lib/swift/host/plugins/testing#$toolchain_bin/swift-plugin-server"
else
    swift test --disable-xctest
fi
python3 Tests/serial_integration.py 'dist/PlaceCard Mac.app/Contents/MacOS/PlaceCardMac'
