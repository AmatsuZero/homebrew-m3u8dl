class NM3u8dlRe < Formula
  desc "Cross-platform stream downloader for MPD/M3U8/ISM (DASH/HLS/MSS)"
  homepage "https://github.com/nilaoda/N_m3u8DL-RE"
  version "0.5.1-beta"
  license "MIT"

  depends_on "ffmpeg"

  on_macos do
    if Hardware::CPU.arm?
      url "https://github.com/nilaoda/N_m3u8DL-RE/releases/download/v0.5.1-beta/N_m3u8DL-RE_v0.5.1-beta_osx-arm64_20251029.tar.gz"
      sha256 "537866d7d03c9aed04c910014bceae26a3db494c1d1edae9c59ddaaa29b0a1c7"
    else
      url "https://github.com/nilaoda/N_m3u8DL-RE/releases/download/v0.5.1-beta/N_m3u8DL-RE_v0.5.1-beta_osx-x64_20251029.tar.gz"
      sha256 "fb0d9fd6c18b08a5c55e49f60d3c219471196bd05bf15e58f318a44da500f65a"
    end
  end

  on_linux do
    if Hardware::CPU.arm?
      url "https://github.com/nilaoda/N_m3u8DL-RE/releases/download/v0.5.1-beta/N_m3u8DL-RE_v0.5.1-beta_linux-arm64_20251029.tar.gz"
      sha256 "b9cce9978e94fd8ce509ee86a6543cccffeb0ee5b7b7aeff1314104265ac65ad"
    else
      url "https://github.com/nilaoda/N_m3u8DL-RE/releases/download/v0.5.1-beta/N_m3u8DL-RE_v0.5.1-beta_linux-x64_20251029.tar.gz"
      sha256 "2acce91b64af3ee676a32d1002e1382840d81f430e1b7f8d5b151ce1eb6fb590"
    end
  end

  def install
    bin.install "N_m3u8DL-RE"
  end

  test do
    assert_match "0.5.1", shell_output("#{bin}/N_m3u8DL-RE --version 2>&1")
  end
end
