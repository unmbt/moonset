#!/usr/bin/env bash
set -euo pipefail

# Installs and verifies the prebuilt moonset CLI binary, or registers a trusted
# local binary when INPUT_BINARY_PATH is set.
# Expected environment variables:
#   INPUT_VERSION, INPUT_BINARY_PATH, ACTION_REF, GH_TOKEN,
#   GITHUB_ACTION_REPOSITORY, RUNNER_OS, RUNNER_ARCH, RUNNER_TOOL_CACHE,
#   GITHUB_PATH, GITHUB_OUTPUT

if [ -n "${INPUT_BINARY_PATH:-}" ]; then
  if [ ! -f "$INPUT_BINARY_PATH" ]; then
    echo "moonset binary-path does not exist: $INPUT_BINARY_PATH" >&2
    exit 1
  fi
  chmod +x "$INPUT_BINARY_PATH" || true
  abs_bin="$(cd "$(dirname "$INPUT_BINARY_PATH")" && pwd)/$(basename "$INPUT_BINARY_PATH")"
  bin_dir="$(dirname "$abs_bin")"
  echo "$bin_dir" >> "$GITHUB_PATH"
  if [ -n "${GITHUB_OUTPUT:-}" ]; then
    echo "path=$abs_bin" >> "$GITHUB_OUTPUT"
    echo "version=local" >> "$GITHUB_OUTPUT"
  fi
  exit 0
fi

repo="${GITHUB_ACTION_REPOSITORY:-unmbt/moonset}"
tag="${INPUT_VERSION:-}"
if [ -z "$tag" ]; then
  case "${ACTION_REF:-}" in
    v[0-9]*) tag="$ACTION_REF" ;;
    *) tag="latest" ;;
  esac
fi

os="${RUNNER_OS:-$(uname -s)}"
arch="${RUNNER_ARCH:-$(uname -m)}"

case "$os" in
  Linux|linux) os_key="linux" ;;
  macOS|Darwin|darwin) os_key="darwin" ;;
  Windows|MINGW*|MSYS*|CYGWIN*) os_key="win32" ;;
  *)
    echo "Unsupported runner OS: $os" >&2
    exit 1
    ;;
esac

case "$arch" in
  X64|x86_64|amd64) arch_key="x64" ;;
  ARM64|arm64|aarch64) arch_key="arm64" ;;
  *)
    echo "Unsupported runner architecture: $arch" >&2
    exit 1
    ;;
esac

case "${os_key}-${arch_key}" in
  linux-x64) asset="moonset-linux-x64"; bin_name="moonset" ;;
  linux-arm64) asset="moonset-linux-arm64"; bin_name="moonset" ;;
  darwin-arm64) asset="moonset-darwin-arm64"; bin_name="moonset" ;;
  win32-x64) asset="moonset-win32-x64.exe"; bin_name="moonset.exe" ;;
  *)
    echo "No prebuilt moonset binary for ${os_key}-${arch_key}" >&2
    exit 1
    ;;
esac

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

if [ "$tag" = "latest" ]; then
  resolved_tag="$(gh release view -R "$repo" --json tagName --jq '.tagName')"
else
  resolved_tag="$tag"
fi

gh release download "$resolved_tag" -R "$repo" -p "$asset" -p "SHA256SUMS" -D "$tmp_dir"

(
  cd "$tmp_dir"
  grep -E "[[:space:]]${asset}\$" SHA256SUMS > verify.sha256
  if [ ! -s verify.sha256 ]; then
    echo "Asset $asset not found in SHA256SUMS" >&2
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

cache_root="${RUNNER_TOOL_CACHE:-$tmp_dir}/moonset/${resolved_tag}"
mkdir -p "$cache_root"
cp "$tmp_dir/$asset" "$cache_root/$bin_name"
chmod +x "$cache_root/$bin_name"

echo "$cache_root" >> "$GITHUB_PATH"
if [ -n "${GITHUB_OUTPUT:-}" ]; then
  echo "path=$cache_root/$bin_name" >> "$GITHUB_OUTPUT"
  echo "version=$resolved_tag" >> "$GITHUB_OUTPUT"
fi
