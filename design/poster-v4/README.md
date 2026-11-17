# README poster v4

`docs/poster.jpg` is rendered here. The panel is a real screenshot of MoniSwitch 2.2.0 on a 5K display, placed back on the wallpaper it was captured over, so the glass blends without a seam.

- `captures/` holds only the panel, HUD and a plain desktop strip used for color matching. Full-screen captures are not kept.
- `assets.py` builds the wallpaper canvas. It needs `screenshots/backgrounds/wallhaven-4k_24090.jpg` and `wallhaven-4k_26311.jpg` locally; those 4K sources are not committed.
- `make.py` renders variants with Chrome headless. The shipped poster is layout L1, Athelas, sand title color.
- `sheets.py` builds the font, color and layout comparison sheets.

Regenerate (needs Pillow and numpy):

```bash
python assets.py
python make.py '{"final":[["poster-final",{"layout":"L1","font":"athelas","color":"sand"}]]}'
```

Then export `out/poster-final.png` to `docs/poster.jpg` (JPEG, quality 90).
