#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
MODELS_DIR="$PROJECT_DIR/models"
KOKORO_DIR="$MODELS_DIR/kokoro"
ESPEAK_DIR="$MODELS_DIR/espeak-ng-data"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}=======================================${NC}"
echo -e "${GREEN}  Tree7 TTS - Model Download Script  ${NC}"
echo -e "${GREEN}=======================================${NC}"
echo ""

# Check for required tools
check_command() {
    if ! command -v "$1" &> /dev/null; then
        echo -e "${RED}Error: $1 is required but not installed.${NC}"
        exit 1
    fi
}

check_command wget
check_command tar

# Create directories
mkdir -p "$KOKORO_DIR"
mkdir -p "$ESPEAK_DIR"

echo -e "${YELLOW}Download directories:${NC}"
echo "  - Model files: $KOKORO_DIR"
echo "  - eSpeak data:  $ESPEAK_DIR"
echo ""

# Base URLs
HUGGINGFACE_BASE="https://huggingface.co/onnx-community/Kokoro-82M-v1.0-ONNX/resolve/main"
MODELSCOPE_BASE="https://modelscope.cn/models/onnx-community/Kokoro-82M-ONNX/resolve/master"

# Use ModelScope as primary source (as requested)
BASE_URL="$MODELSCOPE_BASE"

download_file() {
    local url="$1"
    local output="$2"
    local desc="$3"
    
    echo -e "${YELLOW}Downloading $desc...${NC}"
    echo "  URL: $url"
    echo "  Output: $output"
    
    if [ -f "$output" ]; then
        echo -e "${YELLOW}  File already exists, skipping download.${NC}"
        return 0
    fi
    
    wget --progress=bar:force -O "$output" "$url"
    echo -e "${GREEN}  Done!${NC}"
    echo ""
}

# ====================
# Download Kokoro Model
# ====================
echo -e "${GREEN}Step 1: Downloading Kokoro-82M ONNX Model${NC}"
echo ""

# ONNX Model (quantized version for smaller size)
download_file \
    "$BASE_URL/onnx/model_q8f16.onnx" \
    "$KOKORO_DIR/model.onnx" \
    "Kokoro ONNX Model (quantized)"

# Alternatively, download full precision model:
# download_file \
#     "$BASE_URL/onnx/model.onnx" \
#     "$KOKORO_DIR/model.onnx" \
#     "Kokoro ONNX Model (full precision)"

# Tokens file
download_file \
    "$BASE_URL/tokens.txt" \
    "$KOKORO_DIR/tokens.txt" \
    "Tokens file"

# Config file
download_file \
    "$BASE_URL/config.json" \
    "$KOKORO_DIR/config.json" \
    "Config file"

# ====================
# Download Voice Files
# ====================
echo -e "${GREEN}Step 2: Downloading Voice Files${NC}"
echo ""

# Combined voices.bin (contains all voices)
download_file \
    "$BASE_URL/voices.bin" \
    "$KOKORO_DIR/voices.bin" \
    "Combined voices.bin"

# Alternatively, download individual voices:
# Chinese voices
# download_file \
#     "$BASE_URL/voices/zf_xiaoyan.bin" \
#     "$KOKORO_DIR/zf_xiaoyan.bin" \
#     "Chinese female voice (xiaoyan)"

# download_file \
#     "$BASE_URL/voices/zf_xiaobei.bin" \
#     "$KOKORO_DIR/zf_xiaobei.bin" \
#     "Chinese female voice (xiaobei)"

# English voices
# download_file \
#     "$BASE_URL/voices/af_sky.bin" \
#     "$KOKORO_DIR/af_sky.bin" \
#     "English female voice (sky)"

# download_file \
#     "$BASE_URL/voices/am_sam.bin" \
#     "$KOKORO_DIR/am_sam.bin" \
#     "English male voice (sam)"

# ====================
# Download Lexicon Files
# ====================
echo -e "${GREEN}Step 3: Downloading Lexicon Files${NC}"
echo ""

# Chinese lexicon
download_file \
    "$BASE_URL/lexicon-zh.txt" \
    "$KOKORO_DIR/lexicon-zh.txt" \
    "Chinese lexicon"

# English lexicon (US)
download_file \
    "$BASE_URL/lexicon-us-en.txt" \
    "$KOKORO_DIR/lexicon-us-en.txt" \
    "English (US) lexicon"

# English lexicon (UK)
download_file \
    "$BASE_URL/lexicon-gb-en.txt" \
    "$KOKORO_DIR/lexicon-gb-en.txt" \
    "English (UK) lexicon"

# ====================
# Download espeak-ng-data
# ====================
echo -e "${GREEN}Step 4: Downloading espeak-ng-data${NC}"
echo ""

# Download espeak-ng-data from sherpa-onnx releases
ESPEAK_VERSION="1.0.0"
ESPEAK_URL="https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/espeak-ng-data.tar.bz2"

ESPEAK_TAR="$MODELS_DIR/espeak-ng-data.tar.bz2"

if [ ! -d "$ESPEAK_DIR" ] || [ -z "$(ls -A "$ESPEAK_DIR")" ]; then
    echo -e "${YELLOW}Downloading espeak-ng-data...${NC}"
    wget --progress=bar:force -O "$ESPEAK_TAR" "$ESPEAK_URL"
    
    echo -e "${YELLOW}Extracting espeak-ng-data...${NC}"
    cd "$MODELS_DIR" && tar -xjf "$ESPEAK_TAR"
    rm "$ESPEAK_TAR"
    echo -e "${GREEN}  Done!${NC}"
else
    echo -e "${YELLOW}  espeak-ng-data already exists, skipping.${NC}"
fi

# ====================
# Verify downloads
# ====================
echo ""
echo -e "${GREEN}=======================================${NC}"
echo -e "${GREEN}  Verifying Downloads${NC}"
echo -e "${GREEN}=======================================${NC}"
echo ""

verify_file() {
    if [ -f "$1" ]; then
        local size=$(du -h "$1" | cut -f1)
        echo -e "${GREEN}✓ $2: $size${NC}"
        return 0
    else
        echo -e "${RED}✗ $2: MISSING${NC}"
        return 1
    fi
}

verify_file "$KOKORO_DIR/model.onnx" "ONNX Model"
verify_file "$KOKORO_DIR/tokens.txt" "Tokens file"
verify_file "$KOKORO_DIR/voices.bin" "Voices file"
verify_file "$KOKORO_DIR/lexicon-zh.txt" "Chinese lexicon"
verify_file "$KOKORO_DIR/lexicon-us-en.txt" "English lexicon"
verify_file "$KOKORO_DIR/config.json" "Config file"

if [ -d "$ESPEAK_DIR" ] && [ -n "$(ls -A "$ESPEAK_DIR")" ]; then
    echo -e "${GREEN}✓ espeak-ng-data: $(ls "$ESPEAK_DIR" | wc -l) files${NC}"
else
    echo -e "${RED}✗ espeak-ng-data: MISSING${NC}"
fi

echo ""
echo -e "${GREEN}=======================================${NC}"
echo -e "${GREEN}  Download Complete!${NC}"
echo -e "${GREEN}=======================================${NC}"
echo ""
echo -e "${YELLOW}Model files location:${NC}"
echo "  $KOKORO_DIR"
echo ""
echo -e "${YELLOW}eSpeak data location:${NC}"
echo "  $ESPEAK_DIR"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "  1. Install Go dependencies:"
echo "     cd $PROJECT_DIR/backend && go mod tidy"
echo ""
echo "  2. Install ONNX Runtime:"
echo "     macOS: brew install onnxruntime"
echo "     Linux: see script comments for instructions"
echo ""
echo "  3. Start the backend:"
echo "     cd $PROJECT_DIR/backend && go run main.go"
echo ""
echo "  4. Start the Flutter app:"
echo "     cd $PROJECT_DIR/frontend && flutter pub get && flutter run"
echo ""
