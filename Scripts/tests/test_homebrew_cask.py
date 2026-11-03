import copy
import hashlib
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("cask", Path(__file__).parents[1] / "update_homebrew_cask.py")
cask = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cask)


class HomebrewCaskTests(unittest.TestCase):
    def metadata(self):
        return dict(tag_name="v0.3.0", draft=False, prerelease=False, published_at="2026-10-24T00:35:16Z",
                    html_url=cask.REPOSITORY + "/releases/tag/v0.3.0", assets=[
                        dict(name=n, state="uploaded", size=123,
                             browser_download_url=cask.REPOSITORY + "/releases/download/v0.3.0/" + n)
                        for n in ["NianBox-0.3.0-universal.dmg", "SHA256SUMS"]])

    def test_only_public_stable_releases_with_official_assets_are_accepted(self):
        self.assertEqual(cask.release_version(self.metadata()), "0.3.0")
        for patch in [dict(draft=True), dict(prerelease=True), dict(published_at=None),
                      dict(tag_name="v0.4.0-rc.1"), dict(html_url="https://example.com"), dict(assets=[])]:
            with self.subTest(patch=patch), self.assertRaises(ValueError):
                cask.release_version(self.metadata() | patch)
        metadata = copy.deepcopy(self.metadata())
        metadata["assets"][0]["browser_download_url"] = "https://example.com/app.dmg"
        with self.assertRaises(ValueError):
            cask.release_version(metadata)

    def test_corrupt_downloads_and_unsafe_checksum_names_are_rejected(self):
        dmg = b"isolated test DMG"
        digest = hashlib.sha256(dmg).hexdigest()
        line = digest + "  NianBox-0.3.0-universal.dmg\n"
        self.assertEqual(cask.verified_checksum("0.3.0", line, dmg), digest)
        for text, data in [(line, b"corrupt"), (line.replace("NianBox-", "../../NianBox-"), dmg),
                           (line + line, dmg), ("not a checksum", dmg)]:
            with self.subTest(text=text), self.assertRaises(ValueError):
                cask.verified_checksum("0.3.0", text, data)

    def test_cask_is_reproducible_and_preserves_data_and_security_settings(self):
        path = Path(__file__).parents[2] / "Casks/nianbox.rb"
        actual = path.read_text()
        import re
        version = re.search(r'  version "([^"]+)"', actual)[1]
        digest = re.search(r'  sha256 "([^"]+)"', actual)[1]
        self.assertEqual(actual, cask.render_cask(version, digest))
        for prohibited in ["auto_updates true", "zap ", "postflight", "preflight", "--no-quarantine",
                           "xattr", "launchctl", "quit:", "delete:", "trash:"]:
            self.assertNotIn(prohibited, actual)

    def test_maintenance_refuses_to_roll_back_a_newer_cask(self):
        existing = cask.render_cask("0.10.0", "a" * 64)
        with self.assertRaises(ValueError):
            cask.reject_downgrade(existing, "0.9.0")
        cask.reject_downgrade(existing, "0.10.0")
        cask.reject_downgrade(existing, "1.0.0")


if __name__ == "__main__":
    unittest.main()
