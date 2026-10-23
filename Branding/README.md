# NianBox artwork

The selected direction is D, a dark green 3D memory drawer with an ivory note and sage accents on terracotta. The user requested preserving the original 3D identity after rejecting a flat simplification. `AppIcon-source.png` is the built-in imagegen master, saved in this repository. It is rendered into the standard 16–1024 px asset catalog sizes. A rounded terracotta plate and transparent outer margin give macOS 14/15 a finished icon silhouette; the 3D subject sits inside the plate with breathing room. The menu bar uses a reduced, monochrome paper/drawer template for small-size contrast. Preview variants stay outside Git.

Regenerate technical exports with:

```sh
swift Scripts/generate_app_icon.swift Branding/AppIcon-source.png NianBox/Resources/Assets.xcassets
```

Built-in imagegen edit prompt for the final master:

> Preserve the original dark ink-green 3D drawer, sage round knob, ivory folded note with sage dot, viewpoint, lighting and tactile materials. Change only packaging and scale: a centered rounded-square terracotta plate occupies about 88 percent of the square canvas, with genuine transparency outside; the complete object occupies about 68 percent of the canvas, inside the plate with breathing room. Keep soft depth and contact shadow. No flat redesign, text, lettering, watermark, border or additional marks.

No third-party symbol is used as the application icon. This repository's MIT license applies to the exported assets.
