#!/usr/bin/env python3
"""Generate the app icon: Resources/AppIcon.svg (vector master) and
Resources/AppIcon.icns (every macOS size, rendered natively from the vector).

The design is a frosted-glass manuscript page: lines of body text with
in-text citations as raspberry pills (one of them flagged with a red dotted
underline, as the app flags a citation with no reference), a "References"
heading, and a short reference list whose entries carry green match dots
(and one red), joined to their citations by faint threads; sealed with a
raspberry badge carrying a white tick. It is drawn in the macOS 26 Liquid
Glass style, in the "Blush" palette (pale rose to raspberry), and follows
the icons of QDVC Progress, Response Letter, Meetings, Nice Mail,
Bibliotheca and GTD EML for macOS, so the apps look like a family.

Geometry follows Apple's macOS icon template: a 1024x1024 canvas holding an
824x824 tile (100 px transparent margin) with a 185.4 px continuous-curvature
("squircle") corner, plus a soft drop shadow. The corner is the curve UIKit
draws for continuous corners, as reverse-engineered and published by PaintCode
(https://www.paintcodeapp.com/blogpost/code-for-ios-7-rounded-rectangles).

Usage:

    python3 tools/make_icon.py            # writes Resources/AppIcon.{svg,icns}
    python3 tools/make_icon.py --preview  # also writes build/icon-preview.png

Requires rsvg-convert (macOS: `brew install librsvg`; Debian/Ubuntu:
`apt install librsvg2-bin`). No other dependencies; the .icns is written
directly, so Apple's iconutil is not needed.
"""

import argparse
import struct
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RESOURCES = ROOT / "Resources"

# ---------------------------------------------------------------------------
# Palette ("Blush"). The deep tone also tints the card's shadows, so the
# white glass stays distinct from the pale background.

BG_TOP = "#FFF0F5"
BG_DEEP = "#D46A92"

# The page: body text, citations, the References heading.
TEXT_INK = "#9C8591"
HEADING_INK = "#5E3A4C"
CITATION = "#C93B70"
# The app's own colours (Sources/QDVCCitationsCheck/AppModel.swift):
# red for citations and references that don't match up.
MISSING = "#FF3B30"
MATCHED = "#34C759"

# The seal: a raspberry sphere with a white tick.
FACE_LIGHT, FACE_MID, FACE_DARK = "#F7A3C2", "#C93B70", "#7A1842"
FEATURES = "#FFFFFF"

# ---------------------------------------------------------------------------
# Apple's template geometry.

TILE_ORIGIN, TILE_SIZE, CORNER_RADIUS = 100, 824, 185.4
SHADOW_BLUR_RADIUS, SHADOW_OFFSET_Y, SHADOW_OPACITY = 28, 12, 0.5

# Continuous-corner segments around the top-right corner, in units of the
# radius: (distance from the right edge, distance from the top edge).
_CORNER = [
    ("L", (1.52866471, 0.0)),
    ("C", (1.08849323, 0.0), (0.86840689, 0.0), (0.66993427, 0.06549600)),
    ("L", (0.63149399, 0.07491100)),
    ("C", (0.37282392, 0.16905899), (0.16906013, 0.37282401), (0.07491176, 0.63149399)),
    ("C", (0.0, 0.86840701), (0.0, 1.08849299), (0.0, 1.52866483)),
]


def continuous_rounded_rect(x, y, w, h, r):
    """SVG path of a rounded rectangle with Apple's continuous corners."""
    r = min(r, min(w, h) / 2 / 1.52866483)
    corners = [
        lambda u, v: (x + w - u * r, y + v * r),        # top-right
        lambda u, v: (x + w - v * r, y + h - u * r),    # bottom-right
        lambda u, v: (x + u * r, y + h - v * r),        # bottom-left
        lambda u, v: (x + v * r, y + u * r),            # top-left
    ]

    def fmt(p):
        return f"{p[0]:.2f},{p[1]:.2f}"

    d = [f"M{fmt((x + 1.52866483 * r, y))}"]
    for corner in corners:
        for seg in _CORNER:
            if seg[0] == "L":
                d.append("L" + fmt(corner(*seg[1])))
            else:
                d.append("C" + " ".join(fmt(corner(*p)) for p in seg[1:]))
    d.append("Z")
    return " ".join(d)


TILE = continuous_rounded_rect(TILE_ORIGIN, TILE_ORIGIN, TILE_SIZE, TILE_SIZE, CORNER_RADIUS)

# The card (x, y, width, height) and the seal's radius. The seal sits on the
# card's lower right corner.
CARD = (204, 220, 576, 540)
SEAL_RADIUS = 118


def _hex2rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def _mix(a, b, t):
    ra, rb = _hex2rgb(a), _hex2rgb(b)
    return "#%02X%02X%02X" % tuple(round(x + (y - x) * t) for x, y in zip(ra, rb))


# Body text, line by line: ("t", width) is a run of text, ("c", width) a
# citation pill, ("m", width) a citation with no reference.
BODY = [
    [("t", 196), ("c", 120), ("t", 118)],
    [("t", 92), ("c", 136), ("t", 206)],
    [("t", 150), ("m", 128), ("t", 94)],
]

# Reference entries: (width of the text, matched?).
REFS = [(380, True), (318, True), (210, False)]


def _card():
    """The frosted-glass manuscript page. Returns (elements, seal centre)."""
    x, y, w, h = CARD
    left = x + 58
    gap = 16
    parts = [f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="56" fill="url(#glass)"/>']

    # Body text with citation pills; remember where the good pills are.
    pills = []
    line_y = y + 76
    for row in BODY:
        cx = left
        for kind, width in row:
            if kind == "t":
                parts.append(f'<rect x="{cx}" y="{line_y - 10}" width="{width}" height="20" rx="10" '
                             f'fill="{TEXT_INK}" fill-opacity="0.45"/>')
            else:
                parts.append(f'<rect x="{cx}" y="{line_y - 16}" width="{width}" height="32" rx="16" '
                             f'fill="{CITATION}"/>')
                # the citation's parentheses, as white ticks inside the pill
                for px, sweep in ((cx + 16, 0), (cx + width - 16, 1)):
                    d = (f'M{px + (4 if sweep == 0 else -4)},{line_y - 9} '
                         f'Q{px - (4 if sweep == 0 else -4)},{line_y} {px + (4 if sweep == 0 else -4)},{line_y + 9}')
                    parts.append(f'<path d="{d}" fill="none" stroke="#FFFFFF" stroke-opacity="0.9" '
                                 'stroke-width="4" stroke-linecap="round"/>')
                parts.append(f'<rect x="{cx + 30}" y="{line_y - 3}" width="{width - 60}" height="6" rx="3" '
                             'fill="#FFFFFF" fill-opacity="0.75"/>')
                if kind == "m":
                    parts.append(f'<line x1="{cx + 6}" y1="{line_y + 26}" x2="{cx + width - 6}" y2="{line_y + 26}" '
                                 f'stroke="{MISSING}" stroke-width="7" stroke-linecap="round" '
                                 'stroke-dasharray="0.1 14"/>')
                else:
                    pills.append((cx + width / 2, line_y + 16))
            cx += width + gap
        line_y += 64

    # The References heading.
    head_y = line_y + 14
    parts.append(f'<rect x="{left}" y="{head_y - 13}" width="168" height="26" rx="13" fill="{HEADING_INK}"/>')

    # Reference entries with their match dots.
    dots = []
    ref_y = head_y + 62
    for width, matched in REFS:
        parts.append(f'<circle cx="{left + 12}" cy="{ref_y}" r="12" fill="{MATCHED if matched else MISSING}"/>')
        parts.append(f'<rect x="{left + 38}" y="{ref_y - 10}" width="{width}" height="20" rx="10" '
                     f'fill="{TEXT_INK}" fill-opacity="0.45"/>')
        if matched:
            dots.append((left + 12, ref_y - 12))
        ref_y += 54

    # Threads from each good citation to its reference.
    threads = []
    for (px, py), (dx, dy) in zip(pills, dots):
        # Out to the left margin, then down to the reference's dot.
        threads.append(f'<path d="M{px:.0f},{py} C{px:.0f},{py + 26} {dx},{py + 4} {dx},{py + 40} L{dx},{dy}" '
                       f'fill="none" stroke="{CITATION}" stroke-opacity="0.30" stroke-width="4" '
                       'stroke-dasharray="2 10" stroke-linecap="round"/>')
    # Threads go under the text, just above the glass.
    parts[1:1] = threads

    # glass rim
    parts.append(f'<rect x="{x + 2}" y="{y + 2}" width="{w - 4}" height="{h - 4}" rx="54" fill="none" '
                 'stroke="url(#rim)" stroke-width="4"/>')
    return parts, (x + w - 50, y + h - 44)


def _seal(cx, cy, r):
    """A glossy raspberry seal with a white tick, in a white ring."""
    s = r * 0.5
    tick = (f"{cx - s * 0.95:.1f},{cy + s * 0.02:.1f} {cx - s * 0.25:.1f},{cy + s * 0.70:.1f} "
            f"{cx + s * 1.0:.1f},{cy - s * 0.72:.1f}")
    return [
        f'<circle cx="{cx}" cy="{cy}" r="{r + 10}" fill="#FFFFFF" opacity="0.9"/>',
        f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="url(#face)"/>',
        f'<polyline points="{tick}" fill="none" stroke="{FEATURES}" stroke-width="{r * 0.17:.1f}" '
        'stroke-linecap="round" stroke-linejoin="round"/>',
        # specular highlight
        f'<ellipse cx="{cx - r * 0.30:.1f}" cy="{cy - r * 0.55:.1f}" rx="{r * 0.38:.1f}" '
        f'ry="{r * 0.18:.1f}" fill="#FFFFFF" opacity="0.40"/>',
    ]


def icon_svg():
    sigma = SHADOW_BLUR_RADIUS / 2
    defs = [
        f'<linearGradient id="bg" x1="0" y1="0" x2="0.35" y2="1">'
        f'<stop offset="0" stop-color="{BG_TOP}"/><stop offset="1" stop-color="{BG_DEEP}"/></linearGradient>',
        '<radialGradient id="glow" cx="0.30" cy="0.18" r="0.75">'
        '<stop offset="0" stop-color="#FFFFFF" stop-opacity="0.34"/>'
        '<stop offset="1" stop-color="#FFFFFF" stop-opacity="0"/></radialGradient>',
        '<linearGradient id="sheen" x1="0" y1="0" x2="0" y2="1">'
        '<stop offset="0" stop-color="#FFFFFF" stop-opacity="0.22"/>'
        '<stop offset="0.40" stop-color="#FFFFFF" stop-opacity="0.03"/>'
        '<stop offset="1" stop-color="#FFFFFF" stop-opacity="0"/></linearGradient>',
        '<linearGradient id="rim" x1="0" y1="0" x2="0" y2="1">'
        '<stop offset="0" stop-color="#FFFFFF" stop-opacity="0.9"/>'
        '<stop offset="0.5" stop-color="#FFFFFF" stop-opacity="0.3"/>'
        '<stop offset="1" stop-color="#FFFFFF" stop-opacity="0.6"/></linearGradient>',
        '<linearGradient id="edge" x1="0" y1="0" x2="0" y2="1">'
        '<stop offset="0" stop-color="#FFFFFF" stop-opacity="0.75"/>'
        '<stop offset="0.5" stop-color="#FFFFFF" stop-opacity="0.12"/>'
        '<stop offset="1" stop-color="#FFFFFF" stop-opacity="0.35"/></linearGradient>',
        '<linearGradient id="glass" x1="0" y1="0" x2="0" y2="1">'
        '<stop offset="0" stop-color="#FFFFFF" stop-opacity="0.78"/>'
        f'<stop offset="1" stop-color="{_mix("#FFFFFF", BG_DEEP, 0.25)}" stop-opacity="0.55"/></linearGradient>',
        '<linearGradient id="glassflap" x1="0" y1="0" x2="0" y2="1">'
        '<stop offset="0" stop-color="#FFFFFF" stop-opacity="0.95"/>'
        '<stop offset="1" stop-color="#FFFFFF" stop-opacity="0.62"/></linearGradient>',
        '<radialGradient id="face" cx="0.38" cy="0.30" r="0.8">'
        f'<stop offset="0" stop-color="{FACE_LIGHT}"/><stop offset="0.55" stop-color="{FACE_MID}"/>'
        f'<stop offset="1" stop-color="{FACE_DARK}"/></radialGradient>',
        f'<clipPath id="clip"><path d="{TILE}"/></clipPath>',
        # Apple template shadow: black, 28 px blur radius, 12 px down, 50 %.
        '<filter id="shadow" x="-20%" y="-20%" width="140%" height="140%">'
        f'<feGaussianBlur in="SourceAlpha" stdDeviation="{sigma}"/><feOffset dy="{SHADOW_OFFSET_Y}"/>'
        f'<feComponentTransfer><feFuncA type="linear" slope="{SHADOW_OPACITY}"/></feComponentTransfer>'
        '<feMerge><feMergeNode/><feMergeNode in="SourceGraphic"/></feMerge></filter>',
        # Tinted shadow under the card and seal.
        '<filter id="objshadow" x="-30%" y="-30%" width="160%" height="160%">'
        '<feGaussianBlur in="SourceAlpha" stdDeviation="14"/><feOffset dx="0" dy="16"/>'
        f'<feFlood flood-color="{BG_DEEP}" flood-opacity="0.55"/><feComposite operator="in" in2="SourceAlpha"/>'
        '<feMerge><feMergeNode/><feMergeNode in="SourceGraphic"/></feMerge></filter>',
    ]
    card, (cx, cy) = _card()
    objects = card + _seal(cx, cy, SEAL_RADIUS)
    parts = [
        f'<g filter="url(#shadow)"><path d="{TILE}" fill="url(#bg)"/></g>',
        '<g clip-path="url(#clip)">',
        '<rect x="100" y="100" width="824" height="824" fill="url(#glow)"/>',
        '<g filter="url(#objshadow)">', *objects, '</g>',
        '<rect x="100" y="100" width="824" height="824" fill="url(#sheen)"/>',
        '</g>',
        f'<path d="{TILE}" fill="none" stroke="url(#edge)" stroke-width="6"/>',
    ]
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">'
            f'<defs>{"".join(defs)}</defs>{"".join(parts)}</svg>\n')


# ---------------------------------------------------------------------------
# .icns writing. These are the element types `iconutil` emits for a standard
# .iconset; all of them hold PNG data.

ICNS_ELEMENTS = [
    ("icp4", 16), ("ic11", 32), ("icp5", 32), ("ic12", 64),
    ("ic07", 128), ("ic13", 256), ("ic08", 256), ("ic14", 512),
    ("ic09", 512), ("ic10", 1024),
]


def render_png(svg_path, size, out_path):
    subprocess.run(["rsvg-convert", "-w", str(size), "-h", str(size), str(svg_path), "-o", str(out_path)],
                   check=True)


def write_icns(pngs_by_size, out_path):
    chunks = b""
    for code, size in ICNS_ELEMENTS:
        data = pngs_by_size[size]
        chunks += code.encode("ascii") + struct.pack(">I", len(data) + 8) + data
    out_path.write_bytes(b"icns" + struct.pack(">I", len(chunks) + 8) + chunks)


def main():
    parser = argparse.ArgumentParser(description="Generate Resources/AppIcon.svg and AppIcon.icns.")
    parser.add_argument("--preview", action="store_true",
                        help="also write build/icon-preview.png (1024 px)")
    args = parser.parse_args()

    try:
        subprocess.run(["rsvg-convert", "--version"], check=True, capture_output=True)
    except (OSError, subprocess.CalledProcessError):
        sys.exit("error: rsvg-convert not found (macOS: brew install librsvg)")

    RESOURCES.mkdir(exist_ok=True)
    svg_path = RESOURCES / "AppIcon.svg"
    svg_path.write_text(icon_svg())

    with tempfile.TemporaryDirectory() as tmp:
        pngs = {}
        for size in sorted({s for _, s in ICNS_ELEMENTS}):
            png = Path(tmp) / f"icon_{size}.png"
            render_png(svg_path, size, png)
            pngs[size] = png.read_bytes()
        write_icns(pngs, RESOURCES / "AppIcon.icns")

    if args.preview:
        (ROOT / "build").mkdir(exist_ok=True)
        render_png(svg_path, 1024, ROOT / "build" / "icon-preview.png")
    print(f"Wrote {svg_path.relative_to(ROOT)} and Resources/AppIcon.icns")


if __name__ == "__main__":
    main()
