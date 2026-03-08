#!/bin/bash
# Sync HapiCore canonical sources to iOS and macOS app targets.
# Run after editing files in packages/HapiCore/Sources/HapiCore/

set -euo pipefail
cd "$(dirname "$0")/.."

CORE="packages/HapiCore/Sources/HapiCore"
IOS="ios/HapiClient/Sources"
MAC="macos/HapiClient/Sources"

FILES=(
    "Models/Models.swift"
    "Models/MessageStatus.swift"
    "Networking/APIClient.swift"
    "Networking/SSEClient.swift"
    "Networking/SyncCoordinator.swift"
    "Storage/LocalStore.swift"
    "Storage/MessageMerger.swift"
    "Utilities/Keychain.swift"
    "Utilities/TokenManager.swift"
    "ViewModels/AppState.swift"
    "ViewModels/ChatViewModel.swift"
    "ViewModels/SessionsViewModel.swift"
)

echo "Syncing ${#FILES[@]} files from HapiCore → iOS + macOS..."

for f in "${FILES[@]}"; do
    if [ ! -f "$CORE/$f" ]; then
        echo "  SKIP  $f (not found in HapiCore)"
        continue
    fi
    cp "$CORE/$f" "$IOS/$f"
    cp "$CORE/$f" "$MAC/$f"
    echo "  OK    $f"
done

echo "Done. Run 'cd packages/HapiCore && swift test' to verify."
