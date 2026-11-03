cask "nianbox" do
  version "0.3.0"
  sha256 "89ce3e36887e7456dc9a181364fdbd4886ee39518293e0d775461fcc1590f8b7"

  url "https://github.com/takboo/nianbox/releases/download/v#{version}/NianBox-#{version}-universal.dmg"
  name "NianBox"
  desc "Corner panel for offline notes and tasks with a self-hosted sync server"
  homepage "https://github.com/takboo/nianbox"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :sonoma

  app "NianBox.app"

  caveats <<~EOS
    This build is ad-hoc signed and is not notarized by Apple.
    Review macOS Privacy & Security if the first downloaded launch is blocked.
    Save unfinished drafts and quit NianBox before upgrading.
    Local tasks, pending changes, settings, and credentials are preserved on uninstall.
  EOS
end
