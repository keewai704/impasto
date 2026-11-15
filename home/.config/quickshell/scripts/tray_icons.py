#!/usr/bin/env python3
# ╭──────────────────────────────────────────────────────────────────────────╮
# │                                                                          │
# │   T R A Y   I C O N S                                                    │
# │   the system icon theme's panel icons · light ones, for a dark bar       │
# │                                                                          │
# │   github.com/andreumassanet/impasto                                      │
# │                                                                          │
# ╰──────────────────────────────────────────────────────────────────────────╯

"""Print the panel icons of the icon theme the system is set to, one path a line.

The theme is the one GNOME's settings name, else GTK 3's settings.ini. Its
`22x22/panel` folder is used if it has one (Papirus and its variants do), else
the first theme it inherits that has one. Themes are looked up in XDG data
order, so a profile on NixOS is searched as `/usr/share` is on Arch. Nothing is
printed when no theme in the chain has panel icons; the tray then draws each
item's own icon.
"""

import configparser
import os
import subprocess
import sys

PANEL = os.path.join("22x22", "panel")


def data_dirs():
    home = os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share")
    rest = os.environ.get("XDG_DATA_DIRS") or "/usr/local/share:/usr/share"
    return [home, os.path.expanduser("~/.icons")] + [d for d in rest.split(":") if d]


def configured_theme():
    try:
        out = subprocess.run(
            ["gsettings", "get", "org.gnome.desktop.interface", "icon-theme"],
            capture_output=True, text=True, timeout=3).stdout.strip().strip("'")
        if out:
            return out
    except (OSError, subprocess.SubprocessError):
        pass
    config = os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config")
    parser = configparser.ConfigParser(interpolation=None)
    try:
        parser.read(os.path.join(config, "gtk-3.0", "settings.ini"), encoding="utf-8")
        return parser.get("Settings", "gtk-icon-theme-name", fallback="").strip()
    except configparser.Error:
        return ""


def theme_dirs(theme):
    for base in data_dirs():
        path = base if base.endswith(".icons") else os.path.join(base, "icons")
        path = os.path.join(path, theme)
        if os.path.isdir(path):
            yield path


def inherited(theme):
    parser = configparser.ConfigParser(interpolation=None)
    for path in theme_dirs(theme):
        index = os.path.join(path, "index.theme")
        if not os.path.isfile(index):
            continue
        try:
            parser.read(index, encoding="utf-8")
        except configparser.Error:
            return []
        value = parser.get("Icon Theme", "Inherits", fallback="")
        return [name.strip() for name in value.split(",") if name.strip()]
    return []


def panel_folder(theme):
    queue, seen = [theme], set()
    while queue:
        name = queue.pop(0)
        if not name or name in seen:
            continue
        seen.add(name)
        for path in theme_dirs(name):
            panel = os.path.join(path, PANEL)
            if os.path.isdir(panel):
                return panel
        queue.extend(inherited(name))
    return None


def main():
    panel = panel_folder(configured_theme())
    if panel is None:
        return 0
    for entry in sorted(os.listdir(panel)):
        if entry.endswith(".svg"):
            sys.stdout.write(os.path.join(panel, entry) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
