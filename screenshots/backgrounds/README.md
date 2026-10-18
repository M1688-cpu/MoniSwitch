# Hero background assets

`hero.jpg` is the only background image referenced by `docs/index.html`
(the large rounded board behind the floating app windows).

## What is used

- **Chosen source:** `wallhaven-4k_24090.jpg` — a night desert under a starry sky.
- **Processed file:** `hero.jpg` — 3200 × 1600 (2:1), sRGB JPEG, quality 84,
  stripped metadata, about 400 KB.
- **Crop:** a 2:1 band biased slightly above the centre of the 5120 × 2880 source,
  resized to 3200 × 1600. The stage uses `object-fit: cover` and
  `object-position: 50% 52%`, so the stars and the dune ridge stay in frame.

The other candidate (`wallhaven-4k_26311.jpg`, the pale/day desert) is kept for
reference but is not loaded by the page. It was rejected because its sky is almost
exactly the page paper colour, so the board had no edge and the light screenshots
lost separation.

## Replacing it

Drop a new image at the same path with the same filename; no code change is
needed. If you use a different filename, update both places in
`docs/index.html`:

1. `<link rel="preload" as="image" href="screenshots/backgrounds/hero.jpg">`
2. `<img class="stage-bg" src="screenshots/backgrounds/hero.jpg">`

Recommended source image:

- 2:1 aspect ratio, at least 3200 × 1600 (3840 × 1920 is ideal), sRGB.
- Low-to-mid luminance with a clear dune / mountain / cloud band; avoid a flat,
  near-white sky (it disappears into `#f3f2ea`).
- Horizon in the lower third; large soft negative space in the upper half for
  the three floating windows.
- No people, text, logos, monitors, or busy foreground branches; no HDR look,
  no heavy vignette.
- Keep the file under ~1.5 MB (JPEG quality 80–86 or WebP).
- Keep the credits/licensing note for the source. The two `wallhaven-4k_*.jpg`
  files were supplied by the site owner; confirm their licence before publishing
  the page publicly.

The page's dune/star composition is intentionally dark. If you prefer a light
board later, use a low-saturation landscape with a mid-tone sky (not near-white)
so the white app windows keep a visible edge.
