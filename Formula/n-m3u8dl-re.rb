class NM3u8dlRe < Formula
  desc "Cross-platform stream downloader for MPD/M3U8/ISM (DASH/HLS/MSS)"
  homepage "https://github.com/nilaoda/N_m3u8DL-RE"
  version "0.5.1-beta"
  license "MIT"

  url "https://github.com/nilaoda/N_m3u8DL-RE/archive/refs/tags/v0.5.1-beta.tar.gz"
  sha256 "55559fec4deef7e40a4d45eebb699865f01d04f7e72110ce5d11b4ca3e655a93"

  depends_on "ffmpeg"

  resource "dotnet-sdk" do
    on_macos do
      if Hardware::CPU.arm?
        url "https://builds.dotnet.microsoft.com/dotnet/Sdk/10.0.101/dotnet-sdk-10.0.101-osx-arm64.tar.gz"
        sha256 "c7d343f7e5e4f5a5d61fb47fc1475ff041cb1ce18e0734fe1a2c05723f04a9ed"
      else
        url "https://builds.dotnet.microsoft.com/dotnet/Sdk/10.0.101/dotnet-sdk-10.0.101-osx-x64.tar.gz"
        sha256 "8313cc166fdf1458070f32aba6d3045fee8ca11ca4e36314146919c5be401480"
      end
    end
    on_linux do
      if Hardware::CPU.arm?
        url "https://builds.dotnet.microsoft.com/dotnet/Sdk/10.0.101/dotnet-sdk-10.0.101-linux-arm64.tar.gz"
        sha256 "bfc5ab09b5cfe1061888a45ad7b4696816b2804dfb9629020aa44e632aedebe0"
      else
        url "https://builds.dotnet.microsoft.com/dotnet/Sdk/10.0.101/dotnet-sdk-10.0.101-linux-x64.tar.gz"
        sha256 "2ba84c4f3238f4c24da2d9f6c950903e6ecbf2970aa7d1d34cbf83f24c8cdfcb"
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
    assert_match "0.5.1", shell_output("#{bin}/N_m3u8DL-RE --version 2>&1")
  end
end
