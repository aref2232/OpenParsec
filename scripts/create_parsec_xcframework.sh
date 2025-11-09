#!/usr/bin/env bash
# Build ParsecSDK.xcframework containing macOS and Mac Catalyst slices.
# Usage: ./scripts/create_parsec_xcframework.sh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${ROOT_DIR}/build_parsec"
OUT_DIR="${ROOT_DIR}/Frameworks"
XCFRAMEWORK_OUT="${OUT_DIR}/ParsecSDK.xcframework"

rm -rf "${BUILD_DIR}" "${XCFRAMEWORK_OUT}"
mkdir -p "${BUILD_DIR}"

echo "Building ParsecSDK for macOS..."
# Adjust scheme/project name if submodule's scheme differs
xcodebuild -project "${ROOT_DIR}/Frameworks/ParsecSDK.framework/ParsecSDK.xcodeproj" \
  -scheme ParsecSDK -configuration Release \
  -sdk macosx BUILD_DIR="${BUILD_DIR}/macos" SKIP_INSTALL=NO BUILD_LIBRARY_FOR_DISTRIBUTION=YES

echo "Building ParsecSDK for Mac Catalyst..."
xcodebuild -project "${ROOT_DIR}/Frameworks/ParsecSDK.framework/ParsecSDK.xcodeproj" \
  -scheme ParsecSDK -configuration Release \
  -destination 'platform=macOS,variant=Mac Catalyst' BUILD_DIR="${BUILD_DIR}/maccatalyst" SKIP_INSTALL=NO BUILD_LIBRARY_FOR_DISTRIBUTION=YES

# Create xcframework — adjust produced paths if necessary
xcodebuild -create-xcframework \
  -framework "${BUILD_DIR}/macos/Release/ParsecSDK.framework" \
  -framework "${BUILD_DIR}/maccatalyst/Release/ParsecSDK.framework" \
  -output "${XCFRAMEWORK_OUT}"

echo "Created ${XCFRAMEWORK_OUT}"
