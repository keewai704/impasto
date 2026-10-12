import configparser
import contextlib
import importlib.util
import io
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch


SCRIPTS = Path(__file__).resolve().parents[1] / "home/.config/quickshell/scripts"
sys.path.insert(0, str(SCRIPTS))
spec = importlib.util.spec_from_file_location("theme_manager", SCRIPTS / "theme_manager.py")
theme = importlib.util.module_from_spec(spec)
spec.loader.exec_module(theme)


class ThemeIntegrationTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.state = self.root / "state"
        self.gtk3 = self.root / "gtk-3.0"
        self.gtk4 = self.root / "gtk-4.0"
        self.qt = self.root / "qt6ct"
        for directory in (self.gtk3, self.gtk4, self.qt):
            directory.mkdir()
        paths = patch.multiple(
            theme,
            STATE_DIR=str(self.state),
            GTK_COLORS_FILE=str(self.state / "gtk-colors.css"),
            GTK3_DIR=str(self.gtk3),
            GTK4_DIR=str(self.gtk4),
            GTK3_CSS_FILE=str(self.gtk3 / "gtk.css"),
            GTK4_CSS_FILE=str(self.gtk4 / "gtk.css"),
            QT6CT_CONFIG_FILE=str(self.qt / "qt6ct.conf"),
            QT6CT_COLORS_FILE=str(self.state / "qt-palette.conf"),
        )
        paths.start()
        self.addCleanup(paths.stop)
        self.colors = {
            "background": "#101010", "surface": "#202020", "border": "#303030",
            "text": "#ffffff", "textMuted": "#cccccc", "accent": "#123456",
            "accentText": "#ffffff",
        }

    def export(self):
        theme.write_gtk_theme(self.colors)
        with patch.object(theme.shutil, "which", return_value="/usr/bin/qt6ct"):
            theme.write_qt6ct_theme(self.colors)

    def test_managed_configs_stay_linked_while_fragments_update(self):
        configs = [self.gtk3 / "gtk.css", self.gtk4 / "gtk.css", self.qt / "qt6ct.conf"]
        for index, path in enumerate(configs):
            path.symlink_to(f"/nix/store/impasto-test-{index}")
        stderr = io.StringIO()
        with contextlib.redirect_stderr(stderr):
            self.export()
            self.colors["accent"] = "#654321"
            self.export()
        self.assertEqual(stderr.getvalue(), "")
        for index, path in enumerate(configs):
            self.assertTrue(path.is_symlink())
            self.assertEqual(str(path.readlink()), f"/nix/store/impasto-test-{index}")
        self.assertIn("@define-color accent_bg_color #654321;",
                      (self.state / "gtk-colors.css").read_text())
        palette = configparser.ConfigParser()
        palette.read(self.state / "qt-palette.conf")
        for group in ("active_colors", "inactive_colors"):
            self.assertIn("#ff654321", palette["ColorScheme"][group])

    def test_unmanaged_configs_still_use_impasto(self):
        self.export()
        self.assertIn("#123456", (self.gtk3 / "gtk.css").read_text())
        self.assertIn("#123456", (self.gtk4 / "gtk.css").read_text())
        config = configparser.ConfigParser()
        config.read(self.qt / "qt6ct.conf")
        self.assertEqual(config["Appearance"]["style"], "Fusion")
        self.assertTrue(Path(config["Appearance"]["color_scheme_path"]).is_file())

    def test_qt5_can_use_palette_without_qt6ct(self):
        with patch.object(theme.shutil, "which", return_value=None):
            theme.write_qt6ct_theme(self.colors)
        self.assertTrue((self.state / "qt-palette.conf").is_file())
        self.assertFalse((self.qt / "qt6ct.conf").exists())


if __name__ == "__main__":
    unittest.main()
