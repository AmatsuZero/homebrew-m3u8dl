#!/bin/bash
set -uo pipefail

REPO="nilaoda/N_m3u8DL-RE"
FORMULA="$(cd "$(dirname "$0")" && pwd)/Formula/n-m3u8dl-re.rb"
DOTNET_SDK_VERSION="10.0.101"
DOTNET_SDK_BASE="https://builds.dotnet.microsoft.com/dotnet/Sdk/${DOTNET_SDK_VERSION}"

info()  { printf "\033[34m==>\033[0m \033[1m%s\033[0m\n" "$*"; }
err()   { printf "\033[31mError:\033[0m %s\n" "$*" >&2; exit 1; }

# ── curl wrapper with optional GitHub auth ────────────────────────
_curl() {
  if [ -n "${GITHUB_TOKEN:-}" ]; then
    curl -sfL -H "Authorization: token ${GITHUB_TOKEN}" "$@"
  else
    curl -sfL "$@"
  fi
}

# ── Run command, capture output, exit on failure ──────────────────
# Usage: run_cmd cmd [args...] > "$output_file"
# On failure, prints stderr and exits via err().
run_cmd() {
  local _tmp; _tmp=$(mktemp /tmp/update.XXXXXX)
  if "$@" > "$_tmp" 2>&1; then
    cat "$_tmp"
  else
    err "$(cat "$_tmp")"
  fi
  rm -f "$_tmp"
}

# ── Get latest release ────────────────────────────────────────────
info "Fetching latest release from $REPO ..."
release_raw=$(run_cmd _curl "https://api.github.com/repos/${REPO}/releases?per_page=5")
release_json=$(echo "$release_raw" | tr -d '\000-\010\013\014\016-\037' | jq '[.[] | select(.draft | not)] | .[0] | {tag_name, assets}')
[ -z "$release_json" ] && err "Failed to parse release info"
tag=$(echo "$release_json" | jq -r '.tag_name')
[ "$tag" = "null" ] && err "Could not parse tag_name"
version="${tag#v}"

# ── Compare version ───────────────────────────────────────────────
# Extract version from URL pattern: .../tags/v<version>.tar.gz
current_version=$(grep -oE 'refs/tags/v[^"]+\.tar\.gz' "$FORMULA" | sed 's|refs/tags/v||; s|\.tar\.gz||')
if [ "$current_version" = "$version" ]; then
  info "Already up to date: $version"
  exit 0
fi
info "New version found: $current_version -> $version"

# ── Source tarball SHA256 ─────────────────────────────────────────
source_url="https://github.com/${REPO}/archive/refs/tags/${tag}.tar.gz"
info "Downloading source tarball ..."
source_sha256=$(run_cmd _curl -o - "$source_url" | shasum -a 256 | awk '{print $1}')
echo "  Source SHA256: ${source_sha256}"

# ── .NET SDK SHA256 for each platform ─────────────────────────────
info "Downloading .NET SDK (osx-arm64) ..."
sdk_osx_arm64_sha256=$(run_cmd curl -sfL -o - "${DOTNET_SDK_BASE}/dotnet-sdk-${DOTNET_SDK_VERSION}-osx-arm64.tar.gz" | shasum -a 256 | awk '{print $1}')
echo "  SDK SHA256 [osx-arm64]: ${sdk_osx_arm64_sha256}"

info "Downloading .NET SDK (osx-x64) ..."
sdk_osx_x64_sha256=$(run_cmd curl -sfL -o - "${DOTNET_SDK_BASE}/dotnet-sdk-${DOTNET_SDK_VERSION}-osx-x64.tar.gz" | shasum -a 256 | awk '{print $1}')
echo "  SDK SHA256 [osx-x64]: ${sdk_osx_x64_sha256}"

info "Downloading .NET SDK (linux-arm64) ..."
sdk_linux_arm64_sha256=$(run_cmd curl -sfL -o - "${DOTNET_SDK_BASE}/dotnet-sdk-${DOTNET_SDK_VERSION}-linux-arm64.tar.gz" | shasum -a 256 | awk '{print $1}')
echo "  SDK SHA256 [linux-arm64]: ${sdk_linux_arm64_sha256}"

info "Downloading .NET SDK (linux-x64) ..."
sdk_linux_x64_sha256=$(run_cmd curl -sfL -o - "${DOTNET_SDK_BASE}/dotnet-sdk-${DOTNET_SDK_VERSION}-linux-x64.tar.gz" | shasum -a 256 | awk '{print $1}')
echo "  SDK SHA256 [linux-x64]: ${sdk_linux_x64_sha256}"

# ── Extract numeric version for test block ────────────────────────
version_numeric=$(echo "$version" | grep -oE '^[0-9]+\.[0-9]+\.[0-9]+')

# ── Generate formula ──────────────────────────────────────────────
info "Updating formula ..."

cat > "$FORMULA" << RUBY
class NM3u8dlRe < Formula
  desc "Cross-platform stream downloader for MPD/M3U8/ISM (DASH/HLS/MSS)"
  homepage "https://github.com/${REPO}"
  license "MIT"

  url "${source_url}"
  sha256 "${source_sha256}"

  depends_on "ffmpeg"

  resource "dotnet-sdk" do
    on_macos do
      if Hardware::CPU.arm?
        url "${DOTNET_SDK_BASE}/dotnet-sdk-${DOTNET_SDK_VERSION}-osx-arm64.tar.gz"
        sha256 "${sdk_osx_arm64_sha256}"
      else
        url "${DOTNET_SDK_BASE}/dotnet-sdk-${DOTNET_SDK_VERSION}-osx-x64.tar.gz"
        sha256 "${sdk_osx_x64_sha256}"
      end
    end
    on_linux do
      if Hardware::CPU.arm?
        url "${DOTNET_SDK_BASE}/dotnet-sdk-${DOTNET_SDK_VERSION}-linux-arm64.tar.gz"
        sha256 "${sdk_linux_arm64_sha256}"
      else
        url "${DOTNET_SDK_BASE}/dotnet-sdk-${DOTNET_SDK_VERSION}-linux-x64.tar.gz"
        sha256 "${sdk_linux_x64_sha256}"
      end
    end
  end

  def install
    dotnet_sdk_dir = buildpath/"dotnet-sdk"
    dotnet_sdk_dir.mkpath
    resource("dotnet-sdk").stage(dotnet_sdk_dir)

    ENV["DOTNET_ROOT"] = dotnet_sdk_dir.to_s
    ENV.prepend_path "PATH", dotnet_sdk_dir.to_s
    ENV["DOTNET_CLI_TELEMETRY_OPTOUT"] = "1"
    ENV["DOTNET_NOLOGO"] = "1"

    rid = if OS.mac?
      "osx-#{Hardware::CPU.arm? ? "arm64" : "x64"}"
    else
      "linux-#{Hardware::CPU.arm? ? "arm64" : "x64"}"
    end

    system dotnet_sdk_dir/"dotnet", "publish",
           "src/N_m3u8DL-RE",
           "-r", rid,
           "-c", "Release",
           "-o", buildpath/"output"

    bin.install buildpath/"output/N_m3u8DL-RE"
  end

  test do
    assert_match "${version_numeric}", shell_output("#{bin}/N_m3u8DL-RE --version 2>&1")
  end
end
RUBY

info "Formula updated to ${version}"

# ── Update README version ─────────────────────────────────────────
README="$(cd "$(dirname "$0")" && pwd)/README.md"
if [ -f "$README" ]; then
  sed -i '' -E "s/(\| \`n-m3u8dl-re\` \|.*\| )[^ ]+ \|$/\1${version} |/" "$README" 2>/dev/null || \
  sed -i    -E "s/(\| \`n-m3u8dl-re\` \|.*\| )[^ ]+ \|$/\1${version} |/" "$README"
fi

echo ""
echo "Next steps:"
echo "  brew install --build-from-source n-m3u8dl-re   # install from source"
echo "  git add -A && git commit -m 'n-m3u8dl-re: update to ${version}'"
