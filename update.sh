#!/bin/bash
set -euo pipefail

REPO="nilaoda/N_m3u8DL-RE"
FORMULA="$(cd "$(dirname "$0")" && pwd)/Formula/n-m3u8dl-re.rb"

# 平台 -> asset 文件名中的关键词
PLATFORMS=("osx-arm64" "osx-x64" "linux-arm64" "linux-x64")

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

# ── 查找各平台 asset URL ─────────────────────────────────────────
declare -A asset_urls
assets=$(echo "$release_json" | jq -r '.assets[].browser_download_url')

for platform in "${PLATFORMS[@]}"; do
  url=$(echo "$assets" | grep "${platform}" | grep '\.tar\.gz$' | head -1)
  [ -z "$url" ] && error "No asset found for platform: $platform"
  asset_urls[$platform]="$url"
done

# ── 下载并计算 SHA256 ────────────────────────────────────────────
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

declare -A checksums
for platform in "${PLATFORMS[@]}"; do
  url="${asset_urls[$platform]}"
  filename=$(basename "$url")
  info "Downloading $filename ..."
  curl -sfL "${auth_header[@]+"${auth_header[@]}"}" -o "$tmpdir/$filename" "$url" \
    || error "Download failed: $url"
  checksums[$platform]=$(shasum -a 256 "$tmpdir/$filename" | awk '{print $1}')
  echo "  SHA256: ${checksums[$platform]}"
done

# ── 从实际 asset 文件名中提取版本号的数字部分（用于 test block）──
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

  depends_on "ffmpeg"

  on_macos do
    if Hardware::CPU.arm?
      url "${asset_urls[osx-arm64]}"
      sha256 "${checksums[osx-arm64]}"
    else
      url "${asset_urls[osx-x64]}"
      sha256 "${checksums[osx-x64]}"
    end
  end

  on_linux do
    if Hardware::CPU.arm?
      url "${asset_urls[linux-arm64]}"
      sha256 "${checksums[linux-arm64]}"
    else
      url "${asset_urls[linux-x64]}"
      sha256 "${checksums[linux-x64]}"
    end
  end

  def install
    bin.install "N_m3u8DL-RE"
  end

  test do
    assert_match "${version_numeric}", shell_output("#{bin}/N_m3u8DL-RE --version 2>&1")
  end
end
RUBY

info "Formula updated to ${version}"
echo ""
echo "Next steps:"
echo "  brew upgrade n-m3u8dl-re   # upgrade locally"
echo "  git add -A && git commit -m 'n-m3u8dl-re: update to ${version}'"
