#!/usr/bin/env bash
# Build the macOS .pkg installer.
# Run this on a macOS machine.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"
DIST_DIR="$PROJECT_ROOT/dist"
VERSION="1.0.0"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR/payload/usr/local/lib/agent-pack"
mkdir -p "$DIST_DIR"

# Copy project files into payload
cp -R "$PROJECT_ROOT/shared" "$BUILD_DIR/payload/usr/local/lib/agent-pack/shared"
cp -R "$PROJECT_ROOT/config" "$BUILD_DIR/payload/usr/local/lib/agent-pack/config"
mkdir -p "$BUILD_DIR/payload/usr/local/lib/agent-pack/linux"
cp -R "$PROJECT_ROOT/linux/lib" "$BUILD_DIR/payload/usr/local/lib/agent-pack/linux/lib"

# Build component package
pkgbuild \
    --root "$BUILD_DIR/payload" \
    --scripts "$SCRIPT_DIR/scripts" \
    --identifier "com.agentpack.pkg" \
    --version "$VERSION" \
    "$BUILD_DIR/AgentPack.pkg"

# Build product archive (final distributable .pkg)
productbuild \
    --distribution "$SCRIPT_DIR/distribution.xml" \
    --resources "$SCRIPT_DIR/resources" \
    --package-path "$BUILD_DIR" \
    "$DIST_DIR/AgentPack-$VERSION.pkg"

echo ""
echo "Built: $DIST_DIR/AgentPack-$VERSION.pkg"

# Cleanup
rm -rf "$BUILD_DIR"
