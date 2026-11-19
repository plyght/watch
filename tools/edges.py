"""Traces a render's outlines into a transparent PNG for comparison sheets.

blender -b -P tools/edges.py -- RENDER.png OUT.png
"""
import sys
import bpy
import numpy as np

src, out = sys.argv[sys.argv.index("--") + 1:][:2]
img = bpy.data.images.load(src)
w, h = img.size
px = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)
lum = px[..., :3] @ np.array([0.2126, 0.7152, 0.0722], dtype=np.float32)
gx = np.zeros_like(lum)
gy = np.zeros_like(lum)
gx[1:-1, 1:-1] = (lum[1:-1, 2:] - lum[1:-1, :-2]) * 2 + (lum[2:, 2:] - lum[2:, :-2]) + (lum[:-2, 2:] - lum[:-2, :-2])
gy[1:-1, 1:-1] = (lum[2:, 1:-1] - lum[:-2, 1:-1]) * 2 + (lum[2:, 2:] - lum[:-2, 2:]) + (lum[2:, :-2] - lum[:-2, :-2])
mag = np.hypot(gx, gy)
edge = np.clip((mag - 0.18) / 0.25, 0, 1)
rgba = np.zeros((h, w, 4), dtype=np.float32)
rgba[..., 0] = 0.0
rgba[..., 1] = 0.9
rgba[..., 2] = 1.0
rgba[..., 3] = edge
o = bpy.data.images.new("edges", w, h, alpha=True)
o.pixels = rgba.ravel()
o.filepath_raw = out
o.file_format = "PNG"
o.save()
