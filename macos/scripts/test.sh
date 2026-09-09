#!/usr/bin/env bash
# Run the test suite.
#
# Three flags are required because this project builds with the Command Line Tools and no Xcode:
#
#   -F <CLT Frameworks>            Testing.framework lives here, not in the SDK, so SPM does not
#                                  add it to the search path on its own.
#   -disable-cross-import-overlays Importing Testing and Foundation in the same file auto-loads
#                                  the cross-import overlay _Testing_Foundation. CLT ships that
#                                  framework's dylib but NOT its .swiftmodule, so the load fails
#                                  with "no such module '_Testing_Foundation'". Disabling overlay
#                                  auto-loading sidesteps it; nothing here needs the overlay.
#   -rpath <CLT Frameworks>        Otherwise the built test bundle links Testing at @rpath and
#                                  dyld cannot find it at run time.
#
# XCTest is not an option at all: XCTest.framework is not part of the CLT SDK. See TESTING.md.
set -euo pipefail

FRAMEWORKS="/Library/Developer/CommandLineTools/Library/Developer/Frameworks"
cd "$(dirname "$0")/.."

if [[ ! -d "$FRAMEWORKS/Testing.framework" ]]; then
    echo "error: Testing.framework not found at $FRAMEWORKS" >&2
    echo "       Install the Command Line Tools: xcode-select --install" >&2
    exit 1
fi

exec swift test \
    -Xswiftc -F -Xswiftc "$FRAMEWORKS" \
    -Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays \
    -Xlinker -rpath -Xlinker "$FRAMEWORKS" \
    "$@"
