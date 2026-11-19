"""Converts 16-bit PGMs to PNG previews: blender -b -P tools/pgm_preview.py -- IN.pgm... OUT_DIR"""
import os, sys
import bpy
import numpy as np

argv = sys.argv[sys.argv.index("--") + 1:]
out_dir = argv[-1]
for path in argv[:-1]:
    with open(path, "rb") as f:
        data = f.read()
    parts = data.split(b"\n", 3)
    w, h = map(int, parts[1].split())
    a = np.frombuffer(parts[3], dtype=">u2").reshape(h, w).astype(np.float32) / 65535.0
    img = bpy.data.images.new("p", w, h)
    rgba = np.dstack([a, a, a, np.ones_like(a)])[::-1].ravel()
    img.pixels = rgba
    img.filepath_raw = os.path.join(out_dir, os.path.basename(path).replace(".pgm", ".png"))
    img.file_format = "PNG"
    img.save()
