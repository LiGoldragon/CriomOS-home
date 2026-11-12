#!/usr/bin/env python3
"""Verify the pinned libnewt/NMT grammar and both pinned Ghostty palettes."""

import sys

NEWT_ROLES = {
    "root", "border", "window", "shadow", "title", "button", "actbutton",
    "checkbox", "actcheckbox", "entry", "label", "listbox", "actlistbox",
    "textbox", "acttextbox", "helpline", "roottext", "emptyscale", "fullscale",
    "disentry", "compactbutton", "actsellistbox", "sellistbox",
}
ACTIVE_ROLES = {
    "actbutton", "actcheckbox", "actlistbox", "acttextbox", "actsellistbox",
    "sellistbox",
}
NMT_ROLES = {"badLabel", "plainLabel", "disabledButton", "textboxWithBackground"}

SLOTS = {
    "black": 0, "red": 1, "green": 2, "brown": 3, "blue": 4,
    "magenta": 5, "cyan": 6, "lightgray": 7, "gray": 8,
    "brightred": 9, "brightgreen": 10, "yellow": 11, "brightblue": 12,
    "brightmagenta": 13, "brightcyan": 14, "white": 15,
}

# Exact slot values generated from modules/home/{ignis,ignis-light}.yaml by
# modules/home/profiles/min/chroma.nix.  Light slot 0 intentionally follows
# base05, so terminal semantic defaults are used for ordinary surfaces.
DARK = [
    "000000", "ff0066", "00cc44", "f5c000", "e040a0", "bb44ee", "cc44ff",
    "d0d0d0", "505050", "ff0066", "00cc44", "f5c000", "e040a0", "bb44ee",
    "cc44ff", "ffffff",
]
LIGHT = [
    "3d3530", "cc0044", "1a8a30", "b89000", "b03080", "8822bb", "9930cc",
    "3d3530", "887a70", "cc0044", "1a8a30", "b89000", "b03080", "8822bb",
    "9930cc", "1a1510",
]


def parse(path):
    result = {}
    with open(path, encoding="utf-8") as stream:
        for item in stream.read().split(";"):
            name, pair = item.split("=", 1)
            foreground, background = pair.split(",", 1)
            assert name not in result
            result[name] = (foreground, background)
    return result


def luminance(hex_colour):
    channels = [int(hex_colour[index:index + 2], 16) / 255 for index in (0, 2, 4)]
    linear = [value / 12.92 if value <= 0.04045 else ((value + 0.055) / 1.055) ** 2.4 for value in channels]
    return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]


def contrast(first, second):
    lighter, darker = sorted((luminance(first), luminance(second)), reverse=True)
    return (lighter + 0.05) / (darker + 0.05)


newt = parse(sys.argv[1])
nmt = parse(sys.argv[2])
assert set(newt) == NEWT_ROLES
assert set(nmt) == NMT_ROLES
assert all(pair == ("default", "default") for role, pair in newt.items() if role not in ACTIVE_ROLES)
assert all(pair == ("white", "gray") for role, pair in newt.items() if role in ACTIVE_ROLES)
assert all(pair == ("default", "default") for pair in nmt.values())
assert SLOTS == dict(zip(SLOTS, range(16)))

foreground, background = SLOTS["white"], SLOTS["gray"]
dark_contrast = contrast(DARK[foreground], DARK[background])
light_contrast = contrast(LIGHT[foreground], LIGHT[background])
assert dark_contrast >= 4.0, dark_contrast
assert light_contrast >= 4.0, light_contrast
print(f"white(15)/gray(8): dark {dark_contrast:.2f}:1; light {light_contrast:.2f}:1")
