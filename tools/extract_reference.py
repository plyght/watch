"""Derives height maps from the reference product photo.

Run:  blender -b -P tools/extract_reference.py -- PHOTO OUT_DIR

The photo is calibrated against the case: bezel outer diameter 43 mm, dial
centre at CENTRE_PX, MM_PER_PX (measured on the 900 px image and scaled).
Outputs 16-bit PGMs the Zig generator loads:
  dial-height.pgm     1024 x 1024 over [-18, 18] mm, 1 = top of the relief
  plaque-N.pgm        512 x 290 per engraved bracelet plaque
"""

import os
import sys

import bpy
import numpy as np

SCALE_900 = 0.09556  # mm per px on the 900 px image
CENTRE_900 = (451.0, 424.5)


def load(path):
    img = bpy.data.images.load(path)
    w, h = img.size
    px = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)[::-1, :, :3]
    lum = px @ np.array([0.2126, 0.7152, 0.0722], dtype=np.float32)
    k = w / 900.0
    return lum, (CENTRE_900[0] * k, CENTRE_900[1] * k), SCALE_900 / k


def sample(lum, xs, ys):
    """Bilinear sample at pixel coordinates."""
    h, w = lum.shape
    xs = np.clip(xs, 0, w - 1.001)
    ys = np.clip(ys, 0, h - 1.001)
    x0 = np.floor(xs).astype(int)
    y0 = np.floor(ys).astype(int)
    fx = xs - x0
    fy = ys - y0
    a = lum[y0, x0] * (1 - fx) + lum[y0, x0 + 1] * fx
    b = lum[y0 + 1, x0] * (1 - fx) + lum[y0 + 1, x0 + 1] * fx
    return a * (1 - fy) + b * fy


def to_px(centre, mmpx, x_mm, y_mm):
    return centre[0] + x_mm / mmpx, centre[1] - y_mm / mmpx


def blur(a, radius):
    """Separable box blur, applied three times (close to Gaussian)."""
    for _ in range(3):
        for axis in (0, 1):
            k = 2 * radius + 1
            pad = np.pad(a, [(radius, radius) if i == axis else (0, 0) for i in range(2)], mode="edge")
            c = np.cumsum(pad, axis=axis, dtype=np.float64)
            c = np.concatenate([np.zeros_like(np.take(c, [0], axis=axis)), c], axis=axis)
            a = ((np.take(c, range(k, c.shape[axis]), axis=axis) - np.take(c, range(0, c.shape[axis] - k), axis=axis)) / k).astype(np.float32)
    return a


def save_pgm(path, a):
    a16 = (np.clip(a, 0, 1) * 65535 + 0.5).astype(">u2")
    with open(path, "wb") as f:
        f.write(f"P5\n{a.shape[1]} {a.shape[0]}\n65535\n".encode())
        f.write(a16.tobytes())


def covered(X, Y):
    """Where the hands, hub and cartridge hide the dial in the reference photo
    (it reads 1:38:03; hands measured on the calibrated grid)."""
    def hand(deg, length, half_w, tail):
        a = np.radians(deg)
        along = X * np.sin(a) + Y * np.cos(a)
        across = X * np.cos(a) - Y * np.sin(a)
        return (along > -tail) & (along < length) & (np.abs(across) < half_w)
    mask = hand(49, 8.9, 1.25, 2.6) | hand(228, 14.0, 1.15, 2.6) | hand(16, 13.2, 0.6, 3.8) | hand(20, 13.2, 0.6, 3.8)
    mask |= np.hypot(X, Y) < 1.6
    mask |= np.hypot(X, Y + 11.25) < 5.1
    return mask


def dial(lum, centre, mmpx, out):
    n, half = 1024, 18.0
    t = (np.arange(n) + 0.5) / n * 2 * half - half
    X, Y = np.meshgrid(t, -t)  # row 0 is the top (y = +18)

    def at(rot_deg, mirror=1):
        a = np.radians(rot_deg)
        xm = mirror * X
        xr = xm * np.cos(a) - Y * np.sin(a)
        yr = xm * np.sin(a) + Y * np.cos(a)
        return sample(lum, *to_px(centre, mmpx, xr, yr)), covered(xr, yr)

    # The real photo everywhere; where the hands or cartridge cover it, borrow
    # the same spot from the nearest uncovered sector (the dial repeats every
    # 60 degrees, mirrored).
    img, hole = at(0)
    for rot in (60, -60, 120, -120, 180):
        for mirror in (1, -1):
            alt, alt_hole = at(rot, mirror)
            fill = hole & ~alt_hole
            img = np.where(fill, alt, img)
            hole = hole & alt_hole

    r = np.hypot(X, Y)
    windows = np.zeros_like(r, dtype=bool)
    for k in range(6):
        a = np.radians(60 * k)
        windows |= np.hypot(X - 12.0 * np.sin(a), Y - 12.0 * np.cos(a)) < 4.3
    zone = (r < 17.3) & ~windows
    p = np.percentile(img[zone], [10, 30, 50, 70, 90])
    print("dial luminance percentiles 10/30/50/70/90:", np.round(p, 3))
    lo, hi = p[1], p[1] + 0.6 * (p[3] - p[1])
    metal = np.clip((img - lo) / max(hi - lo, 1e-3), 0, 1)
    metal = metal * metal * (3 - 2 * metal)
    detail = np.clip((img - hi) / max(p[4] - hi, 1e-3), 0, 1)
    height = metal * (0.85 + 0.15 * blur(detail, 2))
    # Keep the cylinder exactly as photographed (its scalloped outline is the
    # point); only clear the stray readings past its furthest lobe, where the
    # black ground picks up light from the bezel. That band is the padding.
    height = blur(height, 2) * np.clip((17.0 - r) / 0.08, 0, 1)
    save_pgm(os.path.join(out, "dial-height.pgm"), height)
    save_pgm(os.path.join(out, "dial-photo.pgm"), np.clip(img / max(p[4] * 1.3, 1e-3), 0, 1))


def plaque(lum, centre, mmpx, out, name, y0, y1, half=4.75):
    w, h = 512, 290
    xs = np.linspace(-half, half, w)
    ys = np.linspace(y1, y0, h)  # v runs along the band away from the case
    if y0 < 0:
        ys = np.linspace(y1, y0, h)[::-1]
    X, Y = np.meshgrid(xs, ys)
    px, py = to_px(centre, mmpx, X, Y)
    a = sample(lum, px, py)
    lo, hi = np.percentile(a, 4), np.percentile(a, 98)
    a = np.clip((a - lo) / (hi - lo), 0, 1) ** 0.8
    save_pgm(os.path.join(out, name), blur(a, 1))


def main():
    argv = sys.argv[sys.argv.index("--") + 1:]
    photo, out = argv[0], argv[1]
    os.makedirs(out, exist_ok=True)
    lum, centre, mmpx = load(photo)
    print("centre", centre, "mm/px", mmpx)
    dial(lum, centre, mmpx, out)
    # Plaques that face the camera most squarely (y ranges in mm on the photo).
    plaque(lum, centre, mmpx, out, "plaque-1.pgm", -26.9, -21.2)
    plaque(lum, centre, mmpx, out, "plaque-2.pgm", -32.6, -28.0)
    plaque(lum, centre, mmpx, out, "plaque-3.pgm", 26.3, 30.6)


main()
