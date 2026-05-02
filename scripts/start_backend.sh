#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BACKEND_DIR="$PROJECT_DIR/backend"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}=======================================${NC}"
echo -e "${GREEN}  Starting Tree7 TTS Backend${NC}"
echo -e "${GREEN}=======================================${NC}"
echo ""

cd "$BACKEND_DIR"

echo -e "${YELLOW}Checking Go dependencies...${NC}"
if [ ! -d "go.sum" ]; then
    go mod tidy
fi

echo ""
echo -e "${YELLOW}Starting backend server on port 8080...${NC}"
echo -e "${YELLOW}API endpoints:${NC}"
echo "  - GET  http://localhost:8080/health"
echo "  - POST http://localhost:8080/api/tts"
echo "  - GET  http://localhost:8080/audio/*"
echo ""
echo -e "${YELLOW}Press Ctrl+C to stop the server${NC}"
echo ""

go run main.go
