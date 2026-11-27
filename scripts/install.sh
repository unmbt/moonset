#!/usr/bin/env bash
set -euo pipefail

REPO="unmbt/moonset"
INSTALL_DIR="$HOME/.unmbt"
BIN_NAME="moonset"
BIN_PATH="$INSTALL_DIR/$BIN_NAME"
REQUESTED_VERSION="${MOONSET_VERSION:-}"

while [ "$#" -gt 0 ]; do
  case "$1" in
    uninstall|--uninstall)
      echo "Uninstalling $BIN_NAME..."
      rm -f "$BIN_PATH"
      echo "Uninstalled successfully."
      exit 0
      ;;
    --version)
      if [ "$#" -lt 2 ]; then
        echo "Missing value for --version" >&2
        exit 1
      fi
      REQUESTED_VERSION="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

# Detect OS and Architecture
OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
ARCH="$(uname -m)"

case "$OS" in
  linux) OS_KEY="linux" ;;
  darwin) OS_KEY="darwin" ;;
  *)
    echo "Unsupported OS: $OS" >&2
    exit 1
    ;;
esac

case "$ARCH" in
  x86_64|amd64) ARCH_KEY="x64" ;;
  aarch64|arm64) ARCH_KEY="arm64" ;;
  *)
    echo "Unsupported architecture: $ARCH" >&2
    exit 1
    ;;
esac

case "${OS_KEY}-${ARCH_KEY}" in
  linux-x64) ASSET_NAME="moonset-linux-x64" ;;
  linux-arm64) ASSET_NAME="moonset-linux-arm64" ;;
  darwin-arm64) ASSET_NAME="moonset-darwin-arm64" ;;
  *)
    echo "No prebuilt moonset binary for ${OS_KEY}-${ARCH_KEY}" >&2
    exit 1
    ;;
esac

if [ -n "$REQUESTED_VERSION" ]; then
  case "$REQUESTED_VERSION" in
    v*) TARGET_TAG="$REQUESTED_VERSION" ;;
    *) TARGET_TAG="v$REQUESTED_VERSION" ;;
  esac
  RELEASE_API="https://api.github.com/repos/$REPO/releases/tags/$TARGET_TAG"
else
  RELEASE_API="https://api.github.com/repos/$REPO/releases/latest"
fi

echo "Fetching release info from GitHub..."
if ! RELEASE_JSON=$(curl --fail --silent --show-error --location -H "User-Agent: moonset-installer" "$RELEASE_API"); then
  echo "Failed to fetch release info. Please check your network or verify a Release exists." >&2
  exit 1
fi

RELEASE_TAG=$(printf '%s\n' "$RELEASE_JSON" | grep '"tag_name":' | head -n 1 | sed -E 's/.*"([^"]+)".*/\1/')
TARGET_VERSION="${RELEASE_TAG#v}"
DOWNLOAD_URL=$(printf '%s\n' "$RELEASE_JSON" | grep "browser_download_url" | grep "/${ASSET_NAME}\"" | head -n 1 | cut -d '"' -f 4)
CHECKSUM_URL=$(printf '%s\n' "$RELEASE_JSON" | grep "browser_download_url" | grep "/SHA256SUMS\"" | head -n 1 | cut -d '"' -f 4)

if [ -z "$TARGET_VERSION" ] || [ -z "$DOWNLOAD_URL" ] || [ -z "$CHECKSUM_URL" ]; then
  echo "Failed to locate $ASSET_NAME or SHA256SUMS in release $RELEASE_TAG." >&2
  exit 1
fi

if [ -f "$BIN_PATH" ]; then
  CURRENT_RAW="$("$BIN_PATH" -V 2>/dev/null || "$BIN_PATH" --version 2>/dev/null || echo "unknown")"
  CURRENT_VERSION="${CURRENT_RAW#moonset }"
  if [ "$CURRENT_VERSION" = "$TARGET_VERSION" ]; then
    echo "✨ You already have moonset v$TARGET_VERSION installed at $BIN_PATH."
    exit 0
  else
    echo "🚀 Updating moonset from $CURRENT_VERSION to $TARGET_VERSION..."
  fi
else
  echo "🚀 Installing moonset v$TARGET_VERSION..."
fi

mkdir -p "$INSTALL_DIR"

TMP_DIR="$(mktemp -d "${INSTALL_DIR}/${BIN_NAME}.download.XXXXXX")"
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

echo "Downloading $ASSET_NAME and SHA256SUMS..."
if ! curl --fail --show-error --location --output "$TMP_DIR/$ASSET_NAME" "$DOWNLOAD_URL"; then
  echo "Failed to download $ASSET_NAME. The existing installation was not changed." >&2
  exit 1
fi
if ! curl --fail --show-error --location --output "$TMP_DIR/SHA256SUMS" "$CHECKSUM_URL"; then
  echo "Failed to download SHA256SUMS. The existing installation was not changed." >&2
  exit 1
fi

if [ ! -s "$TMP_DIR/$ASSET_NAME" ]; then
  echo "Downloaded file is empty: $ASSET_NAME" >&2
  exit 1
fi

(
  cd "$TMP_DIR"
  tr -d '\r' < SHA256SUMS | awk -v asset="$ASSET_NAME" '($2 == asset || $2 == "*" asset) { print $1 "  " asset; found=1 } END { exit !found }' > verify.sha256
  if [ ! -s verify.sha256 ]; then
    echo "Asset $ASSET_NAME not found in SHA256SUMS" >&2
    exit 1
  fi
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum -c verify.sha256
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 -c verify.sha256
  else
    echo "Neither sha256sum nor shasum is available to verify binary" >&2
    exit 1
  fi
)

chmod +x "$TMP_DIR/$ASSET_NAME"
mv -f "$TMP_DIR/$ASSET_NAME" "$BIN_PATH"

echo ""
echo "✅ Installed $BIN_NAME v$TARGET_VERSION successfully to $BIN_PATH"

export_path_line="export PATH=\"\$HOME/.unmbt:\$PATH\""
add_to_path() {
  local rc_file="$1"
  local create_if_missing="${2:-false}"
  if [ ! -f "$rc_file" ]; then
    if [ "$create_if_missing" = "true" ]; then
      touch "$rc_file"
    else
      return 1
    fi
  fi
  if ! grep -Fq "\$HOME/.unmbt" "$rc_file"; then
    echo "" >> "$rc_file"
    echo "$export_path_line" >> "$rc_file"
    echo "✅ Automatically added ~/.unmbt to $rc_file"
  fi
  return 0
}

added_to_path=false
shell_name="${SHELL:-}"
if [ -n "${ZSH_VERSION:-}" ]; then
  add_to_path "$HOME/.zshrc" true && added_to_path=true || true
else
  case "$shell_name" in
    *zsh*)
      add_to_path "$HOME/.zshrc" true && added_to_path=true || true
      ;;
    *bash*)
      if add_to_path "$HOME/.bashrc" false || add_to_path "$HOME/.bash_profile" false || add_to_path "$HOME/.bashrc" true; then
        added_to_path=true
      fi
      ;;
    *)
      if [ -n "${BASH_VERSION:-}" ]; then
        if add_to_path "$HOME/.bashrc" false || add_to_path "$HOME/.bash_profile" false || add_to_path "$HOME/.bashrc" true; then
          added_to_path=true
        fi
      else
        if add_to_path "$HOME/.zshrc" false || add_to_path "$HOME/.bashrc" false; then
          added_to_path=true
        fi
      fi
      ;;
  esac
fi

if [ "$added_to_path" = true ]; then
  echo "💡 Note: Please restart your terminal or run 'source ~/.bashrc' (or ~/.zshrc) for PATH changes to take effect."
else
  echo "⚠️  Could not automatically detect your shell configuration file."
  echo "💡 Ensure $INSTALL_DIR is in your PATH, e.g.:"
  echo "   echo '$export_path_line' >> ~/.bashrc"
fi
