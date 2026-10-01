#!/usr/bin/env python3
"""Measure an actual compiled app. PNG file size and decoded estimates stay separate."""
import json, sys, struct
from pathlib import Path
app = Path(sys.argv[1])
assert app.is_dir() and (app / 'Info.plist').exists(), 'Provide a compiled app directory'
files = [p for p in app.rglob('*') if p.is_file()]
atlases = {}
for atlas in sorted(app.glob('*.atlasc')):
    pages = []
    for p in sorted(atlas.rglob('*.png')):
        data = p.read_bytes()
        w,h = struct.unpack('>II',data[16:24])
        pages.append({'name':p.name,'width':w,'height':h,'fileBytes':len(data),'rgbaEstimateBytes':w*h*4})
    atlases[atlas.name] = {'fileBytes':sum(p.stat().st_size for p in atlas.rglob('*') if p.is_file()), 'pages':pages}
print(json.dumps({'bundleFileCount':len(files),'bundleBytes':sum(p.stat().st_size for p in files),'atlases':atlases,
                  'note':'RGBA estimates exclude driver allocation, mipmaps, executable/heap and framework overhead; simulator RSS is a different host metric.'},indent=2))
