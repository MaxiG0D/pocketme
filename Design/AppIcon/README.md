# PocketMe app icon

Approved direction: warm taupe pocket holding an article, warm charcoal outline,
coral bookmark, paper background. The symbol is larger than the brainstorming
version, with a barely visible matte finish confined to the pocket.

## Sources and delivery

The four PNG masters in this folder were made with the built-in ImageGen tool
on 2026-10-26. These are raster masters, not editable vector artwork or an Icon
Composer project. Their original resolution is 1254 × 1254.

- `light.png`: opaque paper background and original warm palette.
- `dark.png`: opaque dark background, ivory article strokes, taupe and coral.
- `tinted.png`: neutral monochrome source for iOS's system tint treatment.
- `mac.png`: paper rounded-square tile with transparent outer margins.

Run `python3 Scripts/export_app_icons.py` from the repository root to reproduce
the shipping asset catalog. Only Apple's `sips` resizes the generated artwork;
the exporter does not redraw or synthesize the design.

Shipping files are in `App/Resources/Icons.xcassets/AppIcon.appiconset`:
three opaque 1024 × 1024 iOS appearance images, and the ten standard Mac
16/32/128/256/512 point images at 1× and 2×. Xcode compiles the Mac images into
AppIcon.icns. The app's XcodeGen setting selects `AppIcon`.

The iOS files have square backgrounds; the system applies the outer shape.
The Mac files already contain their rounded tile and transparent padding.
The release applet also uses this artwork. Its source PNG is
`Release/Resources/release-icon-1024.png`, copied from the 1024 pixel Mac export.
The exporter refreshes that copy automatically; rebuild the applet with
`Release/build_release_app.sh` afterward.

These use the asset catalog workflow to retain compatibility with the app's
iOS 18 / macOS 15 minimum versions. They do not add custom Liquid Glass layers.

## Final generation prompt set

All edits preserved the reference's pocket silhouette, curved opening, article
outline and three lines, bookmark and centered composition. All requested crisp
edges, no lettering, mockups, shadows, 3D, coarse grain or gradients.

1. Light: enlarge the approved symbol uniformly about 18%, to about 66% of the
   square canvas width; preserve taupe/charcoal/coral and full-bleed paper
   `#FAFAF8`; keep only nearly invisible matte microtexture in the pocket.
2. Dark: change colors only; `#141414` background and article interior,
   `#EDEDE8` article strokes, `#A69986` pocket, `#E2562B` bookmark; opaque square.
3. Tinted: change colors only to neutral grayscale; near-black background,
   pale gray article strokes, medium-light gray pocket, almost-white bookmark;
   opaque square for system tinting.
4. Mac: preserve the light artwork inside a paper rounded-square tile occupying
   about 80% of the canvas; continuous rounded corners, transparent outer
   margins, no tile shadow or border; scale symbol with the tile.

See `docs/qa/app-icon/README.md` for validation and the size preview.
