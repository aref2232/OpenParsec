#!/usr/bin/env bash
# Robust helper to create Frameworks/ParsecSDK.xcframework when possible.
# Behavior:
# - If ParsecSDK.xcframework already exists, do nothing.
# - If an Xcode project exists inside the submodule, attempt to build macos & maccatalyst frameworks and create an xcframework.
# - If prebuilt .framework exists, wrap it into an xcframework.
# - If a lib (dylib/so/a) exists, wrap it into an xcframework using headers (detect parsec.h).
# - Print diagnostics if nothing usable is found.
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

# Helper: find headers (parsec.h)
find_headers() {
  # Search common locations under the submodule and repo root
  local h
  h=$(find "${PARSEC_SUBMODULE_DIR}" "${ROOT_DIR}" -maxdepth 4 -type f -name 'parsec.h' -print -quit 2>/dev/null || true)
  if [[ -n "${h}" ]]; then
    echo "$(dirname "${h}")"
    return 0
  fi
  # try sdk/include or include
  for d in "${PARSEC_SUBMODULE_DIR}/sdk" "${PARSEC_SUBMODULE_DIR}/include" "${PARSEC_SUBMODULE_DIR}/sdk/macos" "${PARSEC_SUBMODULE_DIR}/.." ; do
    if [[ -d "${d}" && -n "$(ls -A "${d}" 2>/dev/null)" ]]; then
      # Does it contain parsec.h?
      if [[ -f "${d}/parsec.h" ]]; then
        echo "${d}"
        return 0
      fi
    fi
  done
  return 1
}

# If there is an Xcode project in the submodule, try to build
if [[ -d "${PARSEC_SUBMODULE_DIR}/ParsecSDK.xcodeproj" ]] || [[ -f "${PARSEC_SUBMODULE_DIR}/ParsecSDK.xcodeproj/project.pbxproj" ]]; then
  echo "Found ParsecSDK.xcodeproj inside submodule; attempting to build frameworks..."
  PROJECT_PATH="${PARSEC_SUBMODULE_DIR}/ParsecSDK.xcodeproj"
  BUILD_DIR="${ROOT_DIR}/build_parsec"
  rm -rf "${BUILD_DIR}" "${PARSEC_XC}"
  mkdir -p "${BUILD_DIR}"

  # Build macOS framework (best-effort)
  echo "Building macOS framework..."
  if xcodebuild -project "${PROJECT_PATH}" -scheme ParsecSDK -configuration Release -sdk macosx \
      BUILD_DIR="${BUILD_DIR}/macos" SKIP_INSTALL=NO BUILD_LIBRARY_FOR_DISTRIBUTION=YES; then
    echo "macOS build succeeded."
  else
    echo "macOS build failed; continuing to attempt Mac Catalyst and then look for prebuilt artifacts."
  fi

  # Build Mac Catalyst framework (best-effort)
  echo "Building Mac Catalyst framework..."
  if xcodebuild -project "${PROJECT_PATH}" -scheme ParsecSDK -configuration Release \
      -destination 'platform=macOS,variant=Mac Catalyst' BUILD_DIR="${BUILD_DIR}/maccatalyst" \
      SKIP_INSTALL=NO BUILD_LIBRARY_FOR_DISTRIBUTION=YES; then
    echo "Mac Catalyst build succeeded."
  else
    echo "Mac Catalyst build failed (this may be fine)."
  fi

  # Collect what we built
  FRAME_ARGS=()
  if [[ -d "${BUILD_DIR}/macos/Release/ParsecSDK.framework" ]]; then
    FRAME_ARGS+=(-framework "${BUILD_DIR}/macos/Release/ParsecSDK.framework")
  fi
  if [[ -d "${BUILD_DIR}/maccatalyst/Release/ParsecSDK.framework" ]]; then
    FRAME_ARGS+=(-framework "${BUILD_DIR}/maccatalyst/Release/ParsecSDK.framework")
  fi

  if [[ ${#FRAME_ARGS[@]} -gt 0 ]]; then
    echo "Creating xcframework at ${PARSEC_XC} from built frameworks..."
    xcodebuild -create-xcframework "${FRAME_ARGS[@]}" -output "${PARSEC_XC}"
    echo "Created ${PARSEC_XC}"
    exit 0
  else
    echo "No built frameworks were found after building. Dumping build dir for debugging:"
    ls -la "${BUILD_DIR}" || true
    # fall through to search for prebuilt frameworks
  fi
fi

# No Xcode project built. Try to find any .framework file under the submodule to wrap
echo "No Xcode project found or no build outputs; searching for prebuilt framework or library..."
FOUND_FRAME=$(find "${PARSEC_SUBMODULE_DIR}" -maxdepth 4 -type d -name "*.framework" -print -quit 2>/dev/null || true)
if [[ -n "${FOUND_FRAME}" ]]; then
  echo "Found framework at: ${FOUND_FRAME}"
  echo "Attempting to create xcframework from single framework..."
  rm -rf "${PARSEC_XC}"
  if xcodebuild -create-xcframework -framework "${FOUND_FRAME}" -output "${PARSEC_XC}"; then
    echo "Created ${PARSEC_XC}"
    exit 0
  else
    echo "Failed to create xcframework from ${FOUND_FRAME} (binary may be missing or header layout unexpected)."
    # continue to search for libraries/dylibs
  fi
fi

# Look for libraries (.dylib, .so, .a)
FOUND_LIB=$(find "${PARSEC_SUBMODULE_DIR}" -maxdepth 4 -type f \( -name '*.dylib' -o -name '*.so' -o -name '*.a' \) -print -quit 2>/dev/null || true)
if [[ -n "${FOUND_LIB}" ]]; then
  echo "Found library at: ${FOUND_LIB}"
  HDR_DIR=$(find_headers || true)
  if [[ -n "${HDR_DIR}" ]]; then
    echo "Using headers found at: ${HDR_DIR}"
    rm -rf "${PARSEC_XC}"
    echo "Creating xcframework from library..."
    xcodebuild -create-xcframework -library "${FOUND_LIB}" -headers "${HDR_DIR}" -output "${PARSEC_XC}" && {
      echo "Created ${PARSEC_XC}"
      exit 0
    } || {
      echo "Failed to create xcframework from library. xcodebuild output above."
      # continue to diagnostics
    }
  else
    echo "Found a library but could not locate headers (parsec.h). Please provide headers or point to include directory."
  fi
fi

# Try to find parsec.h anywhere (helpful diagnostic)
echo "Diagnostics: attempting to locate parsec.h..."
PARSEC_H=$(find "${PARSEC_SUBMODULE_DIR}" -maxdepth 6 -type f -name 'parsec.h' -print -quit 2>/dev/null || true)
echo "parsec.h location: ${PARSEC_H:-NOT FOUND}"

# Final diagnostics dump to help you fix the submodule
echo "ERROR: Could not find any usable built framework or library to create ParsecSDK.xcframework."
echo "Please either:"
echo "  * Build the Parsec SDK macOS artifacts in the submodule (Xcode project or build system), or"
echo "  * Replace the submodule with a prebuilt ParsecSDK.xcframework containing macos-x86_64 or maccatalyst slices."
echo ""
echo "Diagnostics listing (submodule root):"
ls -la "${PARSEC_SUBMODULE_DIR}" || true
echo "Recursive listing (short):"
find "${PARSEC_SUBMODULE_DIR}" -maxdepth 4 -print || true

exit 2
