#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
FRONTEND_DIR="$PROJECT_DIR/frontend"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}=======================================${NC}"
echo -e "${GREEN}  Starting Tree7 TTS Frontend${NC}"
echo -e "${GREEN}=======================================${NC}"
echo ""

# Find Flutter SDK
find_flutter() {
    # Check common locations
    local flutter_paths=(
        "$HOME/flutter/bin/flutter"
        "$HOME/Library/Application Support/flutter/bin/flutter"
        "/usr/local/flutter/bin/flutter"
        "/opt/flutter/bin/flutter"
        "$HOME/development/flutter/bin/flutter"
    )
    
    for path in "${flutter_paths[@]}"; do
        if [ -f "$path" ]; then
            echo "$path"
            return
        fi
    done
    
    # Check PATH
    if command -v flutter &> /dev/null; then
        command -v flutter
        return
    fi
    
    # Check in user's existing projects
    if [ -d "$HOME/workspace/flutter_apps/BAK/sloth_bot" ]; then
        # Try to find Flutter from existing project
        local flutter_bin=$(dirname "$(dirname "$(find "$HOME/Library/Application Support" -name "flutter" -type d 2>/dev/null | head -1)")")/bin/flutter 2>/dev/null || true
        if [ -f "$flutter_bin" ]; then
            echo "$flutter_bin"
            return
        fi
    fi
    
    echo ""
}

FLUTTER_CMD=$(find_flutter)

if [ -z "$FLUTTER_CMD" ] || [ ! -f "$FLUTTER_CMD" ]; then
    echo -e "${RED}Error: Flutter SDK not found!${NC}"
    echo ""
    echo -e "${YELLOW}Please check the following:${NC}"
    echo "1. Ensure Flutter is installed on your system"
    echo "2. Add Flutter to your PATH environment variable"
    echo "3. Or install Flutter from: https://docs.flutter.dev/get-started/install"
    echo ""
    echo -e "${YELLOW}Common Flutter installation paths:${NC}"
    echo "  - ~/flutter"
    echo "  - ~/development/flutter"
    echo "  - /usr/local/flutter"
    echo ""
    echo -e "${YELLOW}To add Flutter to PATH:${NC}"
    echo "  Add this line to your ~/.zshrc or ~/.bash_profile:"
    echo "  export PATH=\$HOME/flutter/bin:\$PATH"
    echo ""
    echo -e "${YELLOW}Then run:${NC}"
    echo "  source ~/.zshrc  # or ~/.bash_profile"
    echo ""
    exit 1
fi

echo -e "${GREEN}Found Flutter at: $FLUTTER_CMD${NC}"
echo ""

FLUTTER_SDK_DIR=$(dirname "$(dirname "$FLUTTER_CMD")")
export PATH="$FLUTTER_SDK_DIR/bin:$PATH"

echo -e "${YELLOW}Flutter version:${NC}"
flutter --version
echo ""

cd "$FRONTEND_DIR"

# Check if project is complete
check_project_structure() {
    local missing_dirs=()
    
    # Check for essential directories
    if [ ! -d "macos" ] && [ ! -d "android" ] && [ ! -d "ios" ] && [ ! -d "web" ] && [ ! -d "linux" ] && [ ! -d "windows" ]; then
        echo -e "${YELLOW}Warning: Project appears to be missing platform directories.${NC}"
        echo -e "${YELLOW}This is normal if you haven't run 'flutter create' yet.${NC}"
        return 1
    fi
    return 0
}

if ! check_project_structure; then
    echo ""
    echo -e "${YELLOW}Would you like to initialize the Flutter project? (y/n)${NC}"
    read -r response
    if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        echo ""
        echo -e "${YELLOW}Initializing Flutter project...${NC}"
        echo -e "${YELLOW}This will create platform directories (macos, android, ios, etc.)${NC}"
        echo ""
        
        # Backup current files
        mkdir -p "$PROJECT_DIR/temp_backup"
        cp -r "$FRONTEND_DIR/lib" "$PROJECT_DIR/temp_backup/" 2>/dev/null || true
        cp "$FRONTEND_DIR/pubspec.yaml" "$PROJECT_DIR/temp_backup/" 2>/dev/null || true
        cp "$FRONTEND_DIR/analysis_options.yaml" "$PROJECT_DIR/temp_backup/" 2>/dev/null || true
        
        # Create new Flutter project in temp directory
        cd "$PROJECT_DIR"
        flutter create --org com.tree7 --project-name tree7_frontend temp_frontend
        
        # Move platform directories
        for dir in android ios macos linux windows web test; do
            if [ -d "temp_frontend/$dir" ]; then
                mv "temp_frontend/$dir" "$FRONTEND_DIR/"
            fi
        done
        
        # Move other necessary files
        for file in .metadata .packages; do
            if [ -f "temp_frontend/$file" ]; then
                mv "temp_frontend/$file" "$FRONTEND_DIR/"
            fi
        done
        
        # Cleanup
        rm -rf temp_frontend
        rm -rf temp_backup
        
        echo ""
        echo -e "${GREEN}Project initialized successfully!${NC}"
        echo ""
    else
        echo ""
        echo -e "${YELLOW}Skipping project initialization.${NC}"
        echo -e "${YELLOW}To manually initialize later, run:${NC}"
        echo "  cd $FRONTEND_DIR"
        echo "  flutter create ."
        echo ""
    fi
fi

cd "$FRONTEND_DIR"

echo -e "${YELLOW}Running 'flutter pub get' to install dependencies...${NC}"
flutter pub get
echo ""

echo -e "${GREEN}=======================================${NC}"
echo -e "${GREEN}  Ready to run!${NC}"
echo -e "${GREEN}=======================================${NC}"
echo ""
echo -e "${YELLOW}Available devices:${NC}"
flutter devices
echo ""
echo -e "${YELLOW}To run the app:${NC}"
echo "  cd $FRONTEND_DIR"
echo "  flutter run"
echo ""
echo -e "${YELLOW}Or run on a specific device:${NC}"
echo "  flutter run -d macos"
echo "  flutter run -d chrome"
echo "  flutter run -d <device_id>"
echo ""
echo -e "${YELLOW}Note:${NC}"
echo "  - Ensure the backend is running first (./scripts/start_backend.sh)"
echo "  - If running on a real device/emulator, update the backend URL in lib/main.dart"
echo "  - Currently set to: http://localhost:8080"
echo ""

echo -e "${YELLOW}Would you like to run the app now? (y/n)${NC}"
read -r run_now
if [[ "$run_now" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    echo ""
    echo -e "${YELLOW}Starting Flutter app...${NC}"
    flutter run
fi
