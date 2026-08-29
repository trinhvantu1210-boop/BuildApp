#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Script: tools/build_ipa.sh
# Purpose: Build Unsigned/Signed IPA for PrMods (3105) from Xcode project
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

PROJECT_NAME="ThreeOneOSFive.xcodeproj"
SCHEME_NAME="Sellixa"
TARGET_NAME="Sellixa"
CONFIGURATION="Release"
SDK="iphoneos"
BUILD_DIR="${ROOT_DIR}/build"
OUT_IPA_NAME="PrMods.ipa"
SIGN_CFG=false
MIN_VERSION=""
REQUIRE_AUTH=1

print_usage() {
    cat <<EOF
Usage: ./tools/build_ipa.sh [OPTIONS]

Options:
    --configuration, -c <Release|Debug>   Build configuration (default: Release)
    --output, -o <filename.ipa>           Output IPA filename (default: PrMods.ipa)
    --build-dir <path>                    Output build directory (default: ./build)
    --sign-cfg                            Auto-run tools/sign_cfg.py to generate cfg.json
    --min-version <version>               Minimum allowed version for cfg.json (e.g. 1.2.9)
    --require-auth <0|1>                  require_auth flag for cfg.json (default: 1)
    --help, -h                            Show this help message

Example:
    ./tools/build_ipa.sh
    ./tools/build_ipa.sh --sign-cfg --min-version 1.2.9
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -c|--configuration)
            CONFIGURATION="$2"
            shift 2
            ;;
        -o|--output)
            OUT_IPA_NAME="$2"
            shift 2
            ;;
        --build-dir)
            BUILD_DIR="$2"
            shift 2
            ;;
        --sign-cfg)
            SIGN_CFG=true
            shift 1
            ;;
        --min-version)
            MIN_VERSION="$2"
            shift 2
            ;;
        --require-auth)
            REQUIRE_AUTH="$2"
            shift 2
            ;;
        -h|--help)
            print_usage
            exit 0
            ;;
        *)
            echo "❌ Unknown option: $1"
            print_usage
            exit 1
            ;;
    esac
done

cd "${ROOT_DIR}"

echo "=================================================="
echo "🚀 Starting IPA Build Process"
echo "   Project:       ${PROJECT_NAME}"
echo "   Scheme/Target: ${SCHEME_NAME}"
echo "   Configuration: ${CONFIGURATION}"
echo "   SDK:           ${SDK}"
echo "   Output Dir:    ${BUILD_DIR}"
echo "=================================================="

# Check if xcodebuild is available
if ! command -v xcodebuild &> /dev/null; then
    echo "❌ Error: 'xcodebuild' not found. This script requires macOS with Xcode installed."
    echo "💡 If you are on Windows/Linux, please use the GitHub Actions workflow (.github/workflows/build-ipa.yml)."
    exit 1
fi

# Clean previous build artifacts
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}/Payload"

DERIVED_DATA_PATH="${BUILD_DIR}/DerivedData"
ARCHIVE_PATH="${BUILD_DIR}/${SCHEME_NAME}.xcarchive"

echo ""
echo "📦 [1/4] Compiling app with xcodebuild..."

xcodebuild build \
    -project "${PROJECT_NAME}" \
    -scheme "${SCHEME_NAME}" \
    -configuration "${CONFIGURATION}" \
    -sdk "${SDK}" \
    -derivedDataPath "${DERIVED_DATA_PATH}" \
    HEADER_SEARCH_PATHS='$(SRCROOT)/ThreeOneOSFive $(inherited)' \
    ALWAYS_SEARCH_USER_PATHS=YES \
    GCC_TREAT_WARNINGS_AS_ERRORS=NO \
    SWIFT_TREAT_WARNINGS_AS_ERRORS=NO \
    GCC_WARN_64_TO_32_BIT_CONVERSION=NO \
    GCC_WARN_ABOUT_RETURN_TYPE=NO \
    GCC_WARN_UNINITIALIZED_AUTOS=NO \
    GCC_WARN_UNUSED_FUNCTION=NO \
    GCC_WARN_UNUSED_VARIABLE=NO \
    SWIFT_SUPPRESS_WARNINGS=YES \
    CODE_SIGN_IDENTITY="" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    AD_HOC_CODE_SIGNING_ALLOWED=YES

# Locate built .app
APP_PATH=$(find "${DERIVED_DATA_PATH}/Build/Products/${CONFIGURATION}-iphoneos" -name "*.app" -maxdepth 1 | head -n 1)

if [[ -z "${APP_PATH}" || ! -d "${APP_PATH}" ]]; then
    echo "❌ Error: Built .app bundle not found in ${DERIVED_DATA_PATH}/Build/Products/${CONFIGURATION}-iphoneos"
    exit 1
fi

echo "✅ Compiled app located at: ${APP_PATH}"

echo ""
echo "📁 [2/4] Packaging into Payload folder..."
cp -R "${APP_PATH}" "${BUILD_DIR}/Payload/"

APP_NAME="$(basename "${APP_PATH}")"
APP_IN_PAYLOAD="${BUILD_DIR}/Payload/${APP_NAME}"
BINARY_NAME="${APP_NAME%.app}"
APP_BINARY="${APP_IN_PAYLOAD}/${BINARY_NAME}"

echo ""
echo "🎁 [3/4] Creating IPA archive..."
cd "${BUILD_DIR}"
zip -qr -9 "${OUT_IPA_NAME}" Payload

FINAL_IPA_PATH="${BUILD_DIR}/${OUT_IPA_NAME}"
if [[ -f "${FINAL_IPA_PATH}" ]]; then
    IPA_SIZE=$(du -h "${FINAL_IPA_PATH}" | awk '{print $1}')
    IPA_SHA256=$(shasum -a 256 "${FINAL_IPA_PATH}" | awk '{print $1}')
    echo "✅ IPA created successfully: ${FINAL_IPA_PATH} (${IPA_SIZE})"
    echo "   SHA256: ${IPA_SHA256}"
else
    echo "❌ Error: Failed to create ${FINAL_IPA_PATH}"
    exit 1
fi

cd "${ROOT_DIR}"

if [[ "${SIGN_CFG}" == true ]]; then
    echo ""
    echo "🔐 [4/4] Generating signed cfg.json via tools/sign_cfg.py..."
    if [[ -f "${APP_BINARY}" && -f "tools/sign_cfg.py" ]]; then
        SIGN_CMD=(python3 tools/sign_cfg.py --binary "${APP_BINARY}" --require-auth "${REQUIRE_AUTH}" --out "${BUILD_DIR}/cfg.json")
        if [[ -n "${MIN_VERSION}" ]]; then
            SIGN_CMD+=(--min-version "${MIN_VERSION}")
        fi
        "${SIGN_CMD[@]}"
        echo "✅ cfg.json generated at ${BUILD_DIR}/cfg.json"
    else
        echo "⚠️ Warning: Binary ${APP_BINARY} or tools/sign_cfg.py not found. Skipping sign_cfg."
    fi
else
    echo ""
    echo "ℹ️ [4/4] Skipped sign_cfg (use --sign-cfg if needed)."
fi

echo ""
echo "=================================================="
echo "🎉 Build finished successfully!"
echo "   Output IPA: ${FINAL_IPA_PATH}"
if [[ -f "${BUILD_DIR}/cfg.json" ]]; then
    echo "   Output CFG: ${BUILD_DIR}/cfg.json"
fi
echo "=================================================="
