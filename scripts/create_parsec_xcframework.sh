#!/usr/bin/env bash
# Robust helper to create Frameworks/ParsecSDK.xcframework when possible.
# Behavior:
# - If ParsecSDK.xcframework already exists, do nothing.
# - If a ParsecSDK.xcodeproj exists inside the submodule, attempt to build macos & maccatalyst frameworks and create an xcframework.
# - Otherwise, try to find any .framework under the submodule and create an xcframework from that single framework.
# - If nothing found, print diagnostics and exit non-zero.

set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FRAMEWORKS_DIR="${ROOT_DIR}/Frameworks"
PARSEC_XC="${FRAMEWORKS_DIR}/ParsecSDK.xcframework"
PARSEC_SUBMODULE_DIR="${FRAMEWORKS_DIR}/ParsecSDK.framework"

echo "create_parsec_xcframework.sh: ROOT_DIR=${ROOT_DIR}"
echo "Checking for existing ${PARSEC_XC}..."
if [[ -d "${PARSEC_XC}" ]]; then
  echo "Parsec xcframework already exists at ${PARSEC_XC}; skipping creation."
  exit 0
fi

# If there is an Xcode project in the submodule (common case), build both slices and create xcframework
if [[ -f "${PARSEC_SUBMODULE_DIR}/ParsecSDK.xcodeproj/project.pbxproj" ]] || [[ -f "${PARSEC_SUBMODULE_DIR}/ParsecSDK.xcodeproj" ]]; then
  echo "Found ParsecSDK.xcodeproj inside submodule; attempting to build frameworks..."
  PROJECT_PATH="${PARSEC_SUBMODULE_DIR}/ParsecSDK.xcodeproj"
  BUILD_DIR="${ROOT_DIR}/build_parsec"
  rm -rf "${BUILD_DIR}" "${PARSEC_XC}"
  mkdir -p "${BUILD_DIR}"

  # Build macOS framework
  echo "Building macOS framework..."
  xcodebuild -project "${PROJECT_PATH}" -scheme ParsecSDK -configuration Release -sdk macosx BUILD_DIR="${BUILD_DIR}/macos" SKIP_INSTALL=NO BUILD_LIBRARY_FOR_DISTRIBUTION=YES || {
    echo "macOS build failed; see xcodebuild output above."
  }

  # Build Mac Catalyst framework
  echo "Building Mac Catalyst framework..."
  xcodebuild -project "${PROJECT_PATH}" -scheme ParsecSDK -configuration Release -destination 'platform=macOS,variant=Mac Catalyst' BUILD_DIR="${BUILD_DIR}/maccatalyst" SKIP_INSTALL=NO BUILD_LIBRARY_FOR_DISTRIBUTION=YES || {
    echo "Mac Catalyst build failed; continuing to next step if macOS succeeded."
  }

  # Attempt to create xcframework from whatever we built
  FRAME_ARGS=()
  if [[ -d "${BUILD_DIR}/macos/Release/ParsecSDK.framework" ]]; then
    FRAME_ARGS+=(-framework "${BUILD_DIR}/macos/Release/ParsecSDK.framework")
  fi
  if [[ -d "${BUILD_DIR}/maccatalyst/Release/ParsecSDK.framework" ]]; then
    FRAME_ARGS+=(-framework "${BUILD_DIR}/maccatalyst/Release/ParsecSDK.framework")
  fi

  if [[ ${#FRAME_ARGS[@]} -eq 0 ]]; then
    echo "No built frameworks found in build directories. Dumping contents:"
    ls -la "${BUILD_DIR}" || true
    echo "Failing xcframework creation."
    exit 1
  fi

  echo "Creating xcframework at ${PARSEC_XC}..."
  xcodebuild -create-xcframework "${FRAME_ARGS[@]}" -output "${PARSEC_XC}"
  echo "Created ${PARSEC_XC}"
  exit 0
fi

# No Xcode project found — try to find any .framework provided in the submodule (prebuilt)
echo "No Xcode project found in ${PARSEC_SUBMODULE_DIR}. Searching for any .framework files to wrap..."
FOUND_FRAME=$(find "${PARSEC_SUBMODULE_DIR}" -maxdepth 3 -name "*.framework" -print -quit || true)

if [[ -n "${FOUND_FRAME}" ]]; then
  echo "Found framework at: ${FOUND_FRAME}"
  echo "Creating xcframework from single framework..."
  rm -rf "${PARSEC_XC}"
  xcodebuild -create-xcframework -framework "${FOUND_FRAME}" -output "${PARSEC_XC}"
  echo "Created ${PARSEC_XC}"
  exit 0
fi

# Maybe the macOS-specific folder exists under the submodule (e.g. sdk/macos)
echo "Searching sdk/macos for build outputs..."
FOUND_FRAME2=$(find "${PARSEC_SUBMODULE_DIR}/.." -maxdepth 3 -name "*.framework" -print -quit || true)
if [[ -n "${FOUND_FRAME2}" ]]; then
  echo "Found framework at: ${FOUND_FRAME2}"
  echo "Creating xcframework from single framework..."
  rm -rf "${PARSEC_XC}"
  xcodebuild -create-xcframework -framework "${FOUND_FRAME2}" -output "${PARSEC_XC}"
  echo "Created ${PARSEC_XC}"
  exit 0
fi

# No usable framework found — print diagnostics to help you fix or provide artifacts
echo "ERROR: Could not find an Xcode project or any .framework to create ParsecSDK.xcframework."
echo "Please ensure the Parsec submodule provides either:"
echo " - an Xcode project at Frameworks/ParsecSDK.framework/ParsecSDK.xcodeproj (then script will build macos & maccatalyst), OR"
echo " - a prebuilt macOS framework somewhere under Frameworks/ParsecSDK.framework or sdk/macos."
echo ""
echo "Diagnostics: listing directories:"
echo "=== Frameworks/ParsecSDK.framework ==="
ls -la "${PARSEC_SUBMODULE_DIR}" || true
echo "=== Frameworks directory ==="
ls -la "${FRAMEWORKS_DIR}" || true
echo "=== sdk folder (if present) ==="
ls -la "${PARSEC_SUBMODULE_DIR}/../sdk" || true

exit 2
