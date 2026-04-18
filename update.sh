#!/bin/bash
set -euo pipefail

REPO="nilaoda/N_m3u8DL-RE"
FORMULA="$(cd "$(dirname "$0")" && pwd)/Formula/n-m3u8dl-re.rb"
DOTNET_SDK_VERSION="10.0.101"

# .NET SDK 下载 URL 模板
DOTNET_SDK_BASE="https://builds.dotnet.microsoft.com/dotnet/Sdk/${DOTNET_SDK_VERSION}"

# 平台 -> asset 文件名中的关键词（用于二进制 release asset 匹配）
PLATFORMS=("osx-arm64" "osx-x64" "linux-arm64" "linux-x64")

# .NET SDK 平台映射（Homebrew 平台 -> SDK 文件名后缀）
declare -A SDK_PLATFORMS=(
  ["osx-arm64"]="osx-arm64"
  ["osx-x64"]="osx-x64"
  ["linux-arm64"]="linux-arm64"
  ["linux-x64"]="linux-x64"
)

info()  { printf "\033[34m==>\033[0m \033[1m%s\033[0m\n" "$*"; }
error() { printf "\033[31mError:\033[0m %s\n" "$*" >&2; exit 1; }

# ── 构建 curl 认证头（可选，避免 API 限流）─────────────────────────
auth_header=()
if [ -n "${GITHUB_TOKEN:-}" ]; then
  auth_header=(-H "Authorization: token ${GITHUB_TOKEN}")
fi

# ── 获取最新 release（含 pre-release）────────────────────────────
info "Fetching latest release from $REPO ..."
release_json=$(curl -sfL "${auth_header[@]+"${auth_header[@]}"}" \
  "https://api.github.com/repos/${REPO}/releases?per_page=5" \
  | tr -d '\000-\010\013\014\016-\037' \
  | jq '[.[] | select(.draft | not)] | .[0] | {tag_name, assets}') \
  || error "Failed to fetch release info (try setting GITHUB_TOKEN)"

tag=$(echo "$release_json" | jq -r '.tag_name')
[ "$tag" = "null" ] && error "Could not parse tag_name"

# 去掉 v 前缀得到 version
version="${tag#v}"

# ── 比较版本 ──────────────────────────────────────────────────────
current_version=$(grep -m1 'version "' "$FORMULA" | sed 's/.*version "//;s/"//')

if [ "$current_version" = "$version" ]; then
  info "Already up to date: $version"
  exit 0
fi

info "New version found: $current_version -> $version"

# ── 计算源码 tarball SHA256 ──────────────────────────────────────
source_url="https://github.com/${REPO}/archive/refs/tags/${tag}.tar.gz"
info "Downloading source tarball ..."
source_sha256=$(curl -sfL "${auth_header[@]+"${auth_header[@]}"}" "$source_url" | shasum -a 256 | awk '{print $1}')
echo "  Source SHA256: ${source_sha256}"

# ── 计算 .NET SDK 各平台 SHA256 ─────────────────────────────────
declare -A sdk_checksums
for platform in "${PLATFORMS[@]}"; do
  sdk_suffix="${SDK_PLATFORMS[$platform]}"
  sdk_url="${DOTNET_SDK_BASE}/dotnet-sdk-${DOTNET_SDK_VERSION}-${sdk_suffix}.tar.gz"
  info "Downloading .NET SDK (${sdk_suffix}) ..."
  sdk_checksums[$platform]=$(curl -sfL "$sdk_url" | shasum -a 256 | awk '{print $1}')
  echo "  SDK SHA256 [${platform}]: ${sdk_checksums[$platform]}"
done

# ── 从实际版本号中提取数字部分（用于 test block）──────────────────
# e.g. "0.5.1-beta" -> "0.5.1"
version_numeric=$(echo "$version" | grep -oE '^[0-9]+\.[0-9]+\.[0-9]+')

# ── 生成新 formula ───────────────────────────────────────────────
info "Updating formula ..."

cat > "$FORMULA" << RUBY
class NM3u8dlRe < Formula
  desc "Cross-platform stream downloader for MPD/M3U8/ISM (DASH/HLS/MSS)"
  homepage "https://github.com/${REPO}"
  version "${version}"
  license "MIT"

  url "${source_url}"
  sha256 "${source_sha256}"

  depends_on "ffmpeg"

  resource "dotnet-sdk" do
    on_macos do
      if Hardware::CPU.arm?
        url "${DOTNET_SDK_BASE}/dotnet-sdk-${DOTNET_SDK_VERSION}-osx-arm64.tar.gz"
        sha256 "${sdk_checksums[osx-arm64]}"
      else
        url "${DOTNET_SDK_BASE}/dotnet-sdk-${DOTNET_SDK_VERSION}-osx-x64.tar.gz"
        sha256 "${sdk_checksums[osx-x64]}"
      end
    end
    on_linux do
      if Hardware::CPU.arm?
        url "${DOTNET_SDK_BASE}/dotnet-sdk-${DOTNET_SDK_VERSION}-linux-arm64.tar.gz"
        sha256 "${sdk_checksums[linux-arm64]}"
      else
        url "${DOTNET_SDK_BASE}/dotnet-sdk-${DOTNET_SDK_VERSION}-linux-x64.tar.gz"
        sha256 "${sdk_checksums[linux-x64]}"
      end
    end
  end

  def install
    # Install .NET SDK to a temporary build directory
    dotnet_sdk_dir = buildpath/"dotnet-sdk"
    dotnet_sdk_dir.mkpath
    resource("dotnet-sdk").stage(dotnet_sdk_dir)

    ENV["DOTNET_ROOT"] = dotnet_sdk_dir.to_s
    ENV.prepend_path "PATH", dotnet_sdk_dir.to_s
    ENV["DOTNET_CLI_TELEMETRY_OPTOUT"] = "1"
    ENV["DOTNET_NOLOGO"] = "1"

    # Select runtime identifier based on current platform
    rid = if OS.mac?
      "osx-#{Hardware::CPU.arm? ? "arm64" : "x64"}"
    else
      "linux-#{Hardware::CPU.arm? ? "arm64" : "x64"}"
    end

    # Build (matching upstream CI workflow)
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
echo ""
echo "Next steps:"
echo "  brew install --build-from-source n-m3u8dl-re   # install from source"
echo "  git add -A && git commit -m 'n-m3u8dl-re: update to ${version}'"
