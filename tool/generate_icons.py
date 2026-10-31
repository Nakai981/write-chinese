"""Generate all app icons. Requires: pip install resvg-py Pillow.

Glyph outlines: Hanzi Writer Data 2.0.1 / Make Me a Hanzi, Arphic Public
License (assets/ARPHICPL.TXT). No external font is required.
"""
import io
import json
from pathlib import Path
import resvg_py
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
data = json.loads((ROOT / 'assets/logo_character.json').read_text(encoding='utf-8-sig'))
paths = ''.join(f'<path d="{stroke}"/>' for stroke in data['strokes'])
glyph = f'<g transform="translate(194 790) scale(.62 -.62)" fill="#173E3A">{paths}</g>'
svg = f'''<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
<title>Mực — Chinese handwriting</title>
<rect width="1024" height="1024" fill="#FAFCFB"/>
<rect x="120" y="120" width="784" height="784" rx="130" fill="#FFFFFF" stroke="#E1ECE7" stroke-width="6"/>
<path d="M512 160V864M160 512H864" stroke="#E9F1ED" stroke-width="4" stroke-dasharray="12 16"/>
{glyph}
<rect x="744" y="756" width="76" height="76" rx="14" fill="#187B78"/>
<path d="M765 778H799M782 778V810M765 795H799" stroke="#FFFFFF" stroke-width="7" stroke-linecap="round"/>
</svg>'''
(ROOT / 'assets/logo.svg').write_text(svg, encoding='utf-8')
master = Image.open(io.BytesIO(resvg_py.svg_to_bytes(svg_string=svg))).convert('RGB')

def save(path, size, image=master):
    target = ROOT / path
    target.parent.mkdir(parents=True, exist_ok=True)
    image.resize((size, size), Image.Resampling.LANCZOS).save(target)

save('assets/logo.png', 1024)
for density, size in {'mdpi':48,'hdpi':72,'xhdpi':96,'xxhdpi':144,'xxxhdpi':192}.items():
    save(f'android/app/src/main/res/mipmap-{density}/ic_launcher.png', size)
catalog = ROOT / 'ios/Runner/Assets.xcassets/AppIcon.appiconset'
for entry in json.loads((catalog / 'Contents.json').read_text())['images']:
    size = round(float(entry['size'].split('x')[0]) * float(entry['scale'].rstrip('x')))
    save(catalog.relative_to(ROOT) / entry['filename'], size)
for size in [192, 512]:
    save(f'web/icons/Icon-{size}.png', size)
    save(f'web/icons/Icon-maskable-{size}.png', size)
save('web/favicon.png', 48)

foreground = f'<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024">{glyph}</svg>'
foreground_dir = ROOT / 'android/app/src/main/res/drawable-nodpi'
foreground_dir.mkdir(exist_ok=True)
(foreground_dir / 'ic_launcher_foreground.png').write_bytes(resvg_py.svg_to_bytes(svg_string=foreground))
adaptive = ROOT / 'android/app/src/main/res/mipmap-anydpi-v26'
adaptive.mkdir(exist_ok=True)
(adaptive / 'ic_launcher.xml').write_text('''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/icon_background"/>
    <foreground android:drawable="@drawable/ic_launcher_foreground"/>
    <monochrome android:drawable="@drawable/ic_launcher_monochrome"/>
</adaptive-icon>
''', encoding='utf-8')
vector = f'''<vector xmlns:android="http://schemas.android.com/apk/res/android" android:width="108dp" android:height="108dp" android:viewportWidth="1024" android:viewportHeight="1024">
<group android:translateX="194" android:translateY="790" android:scaleX=".62" android:scaleY="-.62">
{''.join(f'<path android:fillColor="#FF000000" android:pathData="{stroke}"/>' for stroke in data['strokes'])}
</group></vector>'''
(ROOT / 'android/app/src/main/res/drawable/ic_launcher_monochrome.xml').write_text(vector, encoding='utf-8')
(ROOT / 'android/app/src/main/res/values/icon_colors.xml').write_text('<resources><color name="icon_background">#FAFCFB</color></resources>\n', encoding='utf-8')
print('Generated master, Android adaptive/themed, iOS and web icons.')
