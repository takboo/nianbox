# NianBox artwork

The selected direction is D, a dark green 3D memory drawer with an ivory note and sage accents on terracotta. The user requested preserving the original 3D identity after rejecting a flat simplification. `AppIcon-source.png` is the imagegen master, saved in this repository. It is rendered into the standard 16–1024 px asset catalog sizes; the background is opaque and fills the square canvas so macOS can apply its current icon mask. The menu bar uses a reduced, monochrome paper/drawer template for small-size contrast. Preview variants stay outside Git.

Regenerate technical exports with:

```sh
swift Scripts/generate_app_icon.swift Branding/AppIcon-source.png NianBox/Resources/Assets.xcassets
```

Built-in imagegen edit prompt for the final master:

> Preserve the original 3D drawer, sage round knob, ivory folded note with sage dot and subtle isometric perspective. Refine the background and safe-area proportions for a macOS application icon, with a calm muted terracotta square, balanced soft light and breathing room. Keep the tactile 3D character; no text, labels, watermark or baked outer rounded frame. Do not use the rejected flat geometric redesign.

No third-party symbol is used as the application icon. This repository's MIT license applies to the exported assets.
