#!/usr/bin/env python3
# kde-macos-config -- scripts/make-wallpaper.py
# Generate the vendored desktop wallpaper.
#
# WHY A GENERATOR INSTEAD OF A BLOB: the previous wallpaper
# (wavy_lines_v01_5120x2880.png) was committed as an opaque binary with no EXIF,
# no ICC profile and no author, so nothing in the repository granted a licence for
# it. The repository is MIT, which made that a licensing landmine for anyone
# cloning it. This script removes the problem at the root: the image is derived
# from the constants below, so its provenance is checkable rather than asserted,
# and anyone can regenerate or restyle it.
#
# Deterministic: no RNG, no clock, no network. The same file in gives the same
# bytes out, so `sha256sum` is a meaningful check.
#
# Requires numpy + Pillow. These are needed to REGENERATE the wallpaper, not to
# use it - apply.sh consumes the committed PNG and never runs this.
#
#   ./scripts/make-wallpaper.py                      # write assets/wallpapers/
#   ./scripts/make-wallpaper.py --preview out.png    # small, fast proof sheet
#   ./scripts/make-wallpaper.py --check              # verify the committed PNG
#
# Design notes: soft-edged wavy slabs over a vertical light-to-dark gradient,
# matching the light-at-top / dark-at-bottom structure the macOS-style setup
# wants, with enough saturation to read as intentional rather than as a grey
# gradient. The content is low-frequency, so it is rendered at half resolution
# and upsampled; the result is visually identical and far cheaper to compute.
import argparse
import hashlib
import io
import pathlib
import sys

import numpy as np
from PIL import Image

WIDTH, HEIGHT = 5120, 2880
RENDER_SCALE = 2  # render at WIDTH/2 x HEIGHT/2, then upsample

# Vertical base gradient, top -> bottom (RGB 0-255).
GRADIENT = [
    (0.00, (0xF3, 0xB0, 0x7A)),  # warm amber light
    (0.22, (0xE8, 0x7A, 0x8C)),  # rose
    (0.45, (0xB4, 0x4A, 0xA8)),  # magenta
    (0.68, (0x5A, 0x3C, 0xB0)),  # violet
    (1.00, (0x1B, 0x1E, 0x4A)),  # deep indigo
]

# Wavy slabs painted over the gradient, in order. Each entry is
# (top offset, thickness, edge softness, colour, wave harmonics).
# A harmonic is (amplitude in fraction-of-height, wavelength in fractions of
# width, phase in radians).
SLABS = [
    (0.16, 0.16, 0.09, (0xFF, 0xC9, 0x6B), [(0.030, 0.85, 0.0), (0.014, 0.41, 1.7)]),
    (0.34, 0.20, 0.10, (0xF2, 0x6A, 0x7E), [(0.038, 1.15, 2.3), (0.017, 0.52, 0.4)]),
    (0.53, 0.22, 0.11, (0xC0, 0x45, 0xAE), [(0.034, 0.95, 4.1), (0.015, 0.44, 2.9)]),
    (0.72, 0.20, 0.10, (0x6E, 0x46, 0xC4), [(0.030, 1.25, 5.6), (0.013, 0.60, 1.2)]),
    (0.88, 0.16, 0.09, (0x33, 0x30, 0x7E), [(0.024, 1.05, 3.3), (0.011, 0.48, 5.0)]),
]


def _ramp(stops, t):
    """Piecewise-linear colour ramp. t is (H, W) in [0, 1] -> (H, W, 3) float."""
    out = np.zeros(t.shape + (3,), dtype=np.float64)
    for (p0, c0), (p1, c1) in zip(stops, stops[1:]):
        mask = (t >= p0) & (t <= p1)
        if not mask.any():
            continue
        span = p1 - p0
        f = np.zeros_like(t)
        f[mask] = (t[mask] - p0) / span if span else 0.0
        for ch in range(3):
            out[..., ch] = np.where(mask, c0[ch] + (c1[ch] - c0[ch]) * f, out[..., ch])
    out[t < stops[0][0]] = stops[0][1]
    out[t > stops[-1][0]] = stops[-1][1]
    return out


def _smoothstep(x):
    x = np.clip(x, 0.0, 1.0)
    return x * x * (3.0 - 2.0 * x)


def render(width=WIDTH, height=HEIGHT):
    w, h = width // RENDER_SCALE, height // RENDER_SCALE
    x = np.linspace(0.0, 1.0, w, dtype=np.float64)[None, :]
    y = np.linspace(0.0, 1.0, h, dtype=np.float64)[:, None]

    img = _ramp(GRADIENT, np.broadcast_to(y, (h, w)).copy())

    for top, thick, soft, colour, harmonics in SLABS:
        edge = np.full((h, w), float(top))
        for amp, wavelength, phase in harmonics:
            edge = edge + amp * np.sin(2.0 * np.pi * (x / wavelength) + phase)
        d = y - edge
        alpha = _smoothstep(d / soft) * _smoothstep((thick - d) / soft)
        col = np.array(colour, dtype=np.float64)[None, None, :]
        img = img * (1.0 - alpha[..., None]) + col * alpha[..., None]

    # Gentle top-lit bloom, and a very slight vignette to keep the dock legible.
    bloom = np.exp(-((y / 0.28) ** 2)) * 16.0
    img = img + bloom[..., None]
    vig = 1.0 - 0.16 * (((x - 0.5) * 2.0) ** 2 + ((y - 0.5) * 2.0) ** 2) / 2.0
    img = img * vig[..., None]

    out = Image.fromarray(
        np.clip(img, 0, 255).astype(np.uint8), mode="RGB"
    ).resize((width, height), Image.LANCZOS)
    return out


def main():
    ap = argparse.ArgumentParser(
        description="Generate the vendored kde-macos-config desktop wallpaper."
    )
    ap.add_argument("--preview", metavar="PATH", help="write a small proof sheet")
    ap.add_argument("--check", action="store_true", help="compare against the committed PNG")
    ap.add_argument("-o", "--output", help="output path (default: assets/wallpapers/...)")
    args = ap.parse_args()

    root = pathlib.Path(__file__).resolve().parent.parent
    default = root / "assets" / "wallpapers" / "wavy_lines_v02_5120x2880.png"

    if args.preview:
        render(1280, 720).save(args.preview)
        print(f"preview: {args.preview}")
        return 0

    out = pathlib.Path(args.output) if args.output else default

    if args.check:
        if not out.exists():
            print(f"missing: {out}", file=sys.stderr)
            return 1
        want = hashlib.sha256(out.read_bytes()).hexdigest()
        # Serialise to a buffer rather than keeping two 5K images in memory.
        buf = io.BytesIO()
        render().save(buf, format="PNG", optimize=True)
        got = hashlib.sha256(buf.getvalue()).hexdigest()
        if got == want:
            print(f"OK  {out.name} matches the generator output")
            return 0
        print(f"DRIFT  {out.name} does not match the generator output", file=sys.stderr)
        print(f"  committed: {want}\n  generated: {got}", file=sys.stderr)
        return 1

    out.parent.mkdir(parents=True, exist_ok=True)
    render().save(out, format="PNG", optimize=True)
    print(f"wrote {out} ({out.stat().st_size} bytes, {WIDTH}x{HEIGHT})")
    print(f"  sha256 {hashlib.sha256(out.read_bytes()).hexdigest()}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
