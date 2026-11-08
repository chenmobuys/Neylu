"""Ensure development entry points stay outside distributed application sources."""
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[1]

class DistributionScopeTests(unittest.TestCase):
    def test_production_sources_do_not_contain_development_launch_modes(self):
        forbidden = ["--screenshot-mode", "--screenshot-dark", "--show-details", "--show-updates",
                     "--show-menu-settings", "--legacy-material", "--panel-report", "--diagnose", "applyScreenshotFixture"]
        for source in ROOT.joinpath("Sources").glob("*.swift"):
            for token in forbidden:
                self.assertNotIn(token, source.read_text(), str(source))
        self.assertFalse(ROOT.joinpath("Sources/ScreenshotFixtures.swift").exists())
        self.assertTrue(ROOT.joinpath("Tests/Support/ScreenshotFixtures.swift").is_file())
        renderer = ROOT.joinpath("scripts/render-docs.sh").read_text()
        self.assertIn("-D NEYLU_PREVIEW", renderer)
        self.assertIn("Tests/Support/ScreenshotFixtures.swift", renderer)
        self.assertNotIn("NEYLU_PREVIEW", ROOT.joinpath("build.sh").read_text())
