import configparser
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import sys
import tempfile
import subprocess
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


class ThemeTemplateTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.templates = self.root / "templates"
        self.rendered = self.root / "rendered"
        self.templates.mkdir()
        paths = patch.multiple(theme, THEME_TEMPLATES_DIR=str(self.templates),
                               RENDERED_THEMES_DIR=str(self.rendered),
                               PALETTE_FILE=str(self.root / "palette.json"))
        paths.start()
        self.addCleanup(paths.stop)
        self.colors = {"accent": "#123456", "text": "#ffffff"}

    def test_templates_keep_layout_and_sources_while_palette_changes(self):
        source = self.root / "managed.css"
        source.write_text("@import url(base.css);\n:root { --accent: #@impasto-accent@; "
                          "--rgb: @impasto-accent-rgb@; font-family: Existing; }")
        (self.templates / "client.css").symlink_to(source)
        theme.export_theme_templates(self.colors)
        result = self.rendered / "client.css"
        watched_inode = result.stat().st_ino
        app_config = self.root / "quick.css"
        app_config.symlink_to(result)
        self.colors["accent"] = "#654321"
        theme.export_theme_templates(self.colors)
        self.assertTrue(app_config.is_symlink())
        self.assertEqual(result.stat().st_ino, watched_inode)
        self.assertIn("--accent: #654321; --rgb: 101, 67, 33;", app_config.read_text())
        self.assertIn("font-family: Existing", app_config.read_text())
        self.assertIn("@import url(base.css);", app_config.read_text())
        self.assertIn("@impasto-accent@", source.read_text())
        self.assertEqual(json.loads((self.root / "palette.json").read_text()), self.colors)
        modified = result.stat().st_mtime_ns
        theme.export_theme_templates(self.colors)
        self.assertEqual(result.stat().st_mtime_ns, modified)

    def test_invalid_palette_leaves_the_previous_theme_intact(self):
        (self.templates / "client.css").write_text("body { color: #@impasto-accent@; }")
        theme.render_theme_templates(self.colors)
        previous = (self.rendered / "client.css").read_text()
        with contextlib.redirect_stderr(io.StringIO()) as errors:
            theme.render_theme_templates({"accent": "red; invalid CSS"})
        self.assertIn("Missing or invalid palette colour", errors.getvalue())
        self.assertEqual((self.rendered / "client.css").read_text(), previous)

    def test_fcitx_reloads_once_for_changed_files_and_tolerates_timeout(self):
        (self.templates / "fcitx5").mkdir()
        for name in ("theme.conf", "panel.svg"):
            (self.templates / "fcitx5" / name).write_text("#@impasto-accent@")
        with patch.object(theme.shutil, "which", return_value="fcitx5-remote"), \
                patch.object(theme.subprocess, "run") as reload:
            theme.render_theme_templates(self.colors)
            theme.render_theme_templates(self.colors)
            self.assertEqual(reload.call_count, 1)
            self.colors["accent"] = "#654321"
            reload.side_effect = subprocess.TimeoutExpired("fcitx5-remote", 5)
            with contextlib.redirect_stderr(io.StringIO()) as errors:
                theme.render_theme_templates(self.colors)
            self.assertIn("Cannot reload fcitx5 theme", errors.getvalue())
        self.assertEqual((self.rendered / "fcitx5/panel.svg").read_text(), "#654321")

    def test_activation_prefers_saved_palette_over_fallback(self):
        (self.templates / "client.css").write_text("#@impasto-accent@")
        fallback = self.root / "fallback.json"
        fallback.write_text(json.dumps({"accent": "#abcdef"}))
        with patch.object(sys, "argv", ["theme_manager.py", "render-themes", str(fallback)]):
            theme.main()
            self.assertEqual((self.rendered / "client.css").read_text(), "#abcdef")
            theme.export_theme_templates(self.colors)
            theme.main()
        self.assertEqual((self.rendered / "client.css").read_text(), "#123456")


if __name__ == "__main__":
    unittest.main()
