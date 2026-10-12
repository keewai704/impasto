#!/usr/bin/env python3
"""HyprFlux wallpaper effects (MIT), prepared for the island's wallpaper service."""

import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile


EFFECTS = {
    "none": ("No Effects", []),
    "black-white": ("Black & White", ["-colorspace", "gray", "-sigmoidal-contrast", "10,40%"]),
    "blurred": ("Blurred", ["-blur", "0x10"]),
    "charcoal": ("Charcoal", ["-charcoal", "0x5"]),
    "edge-detect": ("Edge Detect", ["-edge", "1"]),
    "emboss": ("Emboss", ["-emboss", "0x5"]),
    "frame-raised": ("Frame Raised", ["+raise", "150"]),
    "frame-sunk": ("Frame Sunk", ["-raise", "150"]),
    "negate": ("Negate", ["-negate"]),
    "oil-paint": ("Oil Paint", ["-paint", "4"]),
    "posterize": ("Posterize", ["-posterize", "4"]),
    "polaroid": ("Polaroid", ["-polaroid", "0"]),
    "sepia-tone": ("Sepia Tone", ["-sepia-tone", "65%"]),
    "solarize": ("Solarize", ["-solarize", "80%"]),
    "sharpen": ("Sharpen", ["-sharpen", "0x5"]),
    "vignette": ("Vignette", ["-vignette", "0x3"]),
    "vignette-black": ("Vignette Black", ["-background", "black", "-vignette", "0x3"]),
    "zoomed": ("Zoomed", ["-gravity", "Center", "-crop", "80%x80%+0+0", "+repage"]),
}

STATE = Path(os.environ.get("XDG_STATE_HOME") or Path.home() / ".local/state") / "island"
CACHE = Path(os.environ.get("XDG_CACHE_HOME") or Path.home() / ".cache") / "island/effects"


def read_state():
    try:
        state = json.loads((STATE / "effect.json").read_text())
        return state if isinstance(state, dict) else {}
    except (OSError, ValueError):
        return {}


def source_of(current, motion=""):
    state = read_state()
    if state.get("output") == current:
        return state["source"], state.get("chosen", state["source"])
    if Path(current).parent == CACHE:
        try:
            source = (STATE / "effect-source").read_text().strip()
            if source:
                return source, source
        except OSError:
            pass
    return current, motion or current


def prepare(effect, current, motion=""):
    if effect not in EFFECTS:
        raise ValueError(f"Unknown wallpaper effect: {effect}")
    source, chosen = source_of(current, motion)
    image = Path(source)
    if not source or not image.is_file():
        raise ValueError("No wallpaper to process")
    if effect == "none":
        if not Path(chosen).is_file():
            raise ValueError("Original wallpaper not found")
        return chosen

    stat = image.stat()
    key = hashlib.sha256(f"{image.resolve()}:{stat.st_mtime_ns}:{stat.st_size}:{effect}".encode()).hexdigest()
    CACHE.mkdir(parents=True, exist_ok=True)
    output = CACHE / f"{key}.png"
    if not output.is_file():
        with tempfile.NamedTemporaryFile(suffix=".png", dir=CACHE, delete=False) as temporary:
            pending = Path(temporary.name)
        try:
            subprocess.run(["magick", str(image.resolve()), *EFFECTS[effect][1], str(pending)],
                           check=True, capture_output=True)
            os.replace(pending, output)
        finally:
            pending.unlink(missing_ok=True)

    STATE.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(mode="w", dir=STATE, delete=False) as temporary:
        json.dump({"source": source, "chosen": chosen, "output": str(output), "effect": effect}, temporary)
    os.replace(temporary.name, STATE / "effect.json")
    return str(output)


def main():
    action = sys.argv[1] if len(sys.argv) > 1 else "list"
    current = sys.argv[2] if len(sys.argv) > 2 else ""
    if action == "list":
        state = read_state()
        print(json.dumps({
            "effects": [{"id": key, "name": value[0]} for key, value in EFFECTS.items()],
            "current": state.get("effect", "none") if state.get("output") == current else "none",
        }))
        return
    if len(sys.argv) not in (3, 4):
        raise ValueError("usage: wallpaper_effect.py <effect> <wallpaper> [motion]")
    print(prepare(action, current, sys.argv[3] if len(sys.argv) == 4 else ""))


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError, subprocess.SubprocessError) as error:
        detail = error.stderr.decode(errors="replace").strip() if isinstance(error, subprocess.CalledProcessError) else str(error)
        sys.stderr.write(f"Could not prepare wallpaper effect: {detail}\n")
        sys.exit(1)
