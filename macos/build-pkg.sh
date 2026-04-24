#!/usr/bin/env bash
# Build the macOS .pkg installer.
# Run this on a macOS machine.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"
DIST_DIR="$PROJECT_ROOT/dist"
VERSION="1.0.10"
SCRIPTS_DIR="$BUILD_DIR/scripts"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR/payload/usr/local/lib/agent-pack"
mkdir -p "$DIST_DIR"
mkdir -p "$SCRIPTS_DIR"

# Copy project files into payload
cp -R "$PROJECT_ROOT/shared" "$BUILD_DIR/payload/usr/local/lib/agent-pack/shared"
cp -R "$PROJECT_ROOT/config" "$BUILD_DIR/payload/usr/local/lib/agent-pack/config"
mkdir -p "$BUILD_DIR/payload/usr/local/lib/agent-pack/linux"
cp -R "$PROJECT_ROOT/linux/lib" "$BUILD_DIR/payload/usr/local/lib/agent-pack/linux/lib"
mkdir -p "$BUILD_DIR/payload/usr/local/lib/agent-pack/macos"
cp -R "$PROJECT_ROOT/macos/lib/." "$BUILD_DIR/payload/usr/local/lib/agent-pack/macos/"
chmod 755 "$BUILD_DIR/payload/usr/local/lib/agent-pack/shared/verify-llm-curl.sh"
chmod 755 "$BUILD_DIR/payload/usr/local/lib/agent-pack/macos/gui-setup.sh"
chmod 755 "$BUILD_DIR/payload/usr/local/lib/agent-pack/macos/product-session.sh"

# pkgbuild requires runnable preinstall/postinstall scripts. Stage them in a
# temp directory with executable permissions so the macOS package runs
# reliably regardless of repo mode bits.
cp "$SCRIPT_DIR/scripts/preinstall.sh" "$SCRIPTS_DIR/preinstall"
cp "$SCRIPT_DIR/scripts/postinstall.sh" "$SCRIPTS_DIR/postinstall"
cp "$PROJECT_ROOT/macos/lib/gui-wizard.swift" "$SCRIPTS_DIR/gui-wizard.swift"
cp "$PROJECT_ROOT/config/defaults.json" "$SCRIPTS_DIR/defaults.json"
cp "$PROJECT_ROOT/shared/verify-llm-curl.sh" "$SCRIPTS_DIR/verify-llm-curl.sh"
chmod 644 "$SCRIPTS_DIR/gui-wizard.swift" "$SCRIPTS_DIR/defaults.json"
chmod 755 "$SCRIPTS_DIR/verify-llm-curl.sh"
chmod 755 "$SCRIPTS_DIR/preinstall" "$SCRIPTS_DIR/postinstall"

# Build component package
pkgbuild \
    --root "$BUILD_DIR/payload" \
    --scripts "$SCRIPTS_DIR" \
    --identifier "com.agentpack.pkg" \
    --version "$VERSION" \
    "$BUILD_DIR/AgentPack.pkg"

# Build product archive (final distributable .pkg)
productbuild \
    --distribution "$SCRIPT_DIR/distribution.xml" \
    --resources "$SCRIPT_DIR/resources" \
    --package-path "$BUILD_DIR" \
    "$DIST_DIR/AgentPack-$VERSION-macos-universal.pkg"

echo ""
echo "Built: $DIST_DIR/AgentPack-$VERSION-macos-universal.pkg"

# Cleanup
rm -rf "$BUILD_DIR"
