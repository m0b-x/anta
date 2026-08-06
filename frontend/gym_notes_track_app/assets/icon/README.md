# App icon pipeline

`source.png` is the original 1024×1024 artwork — a dark rounded-square icon
on an **opaque white square canvas** (the corners outside the rounded shape
are solid white, not transparent). That white shows through as ugly corners
on any platform/launcher whose own icon mask doesn't exactly match the
radius baked into the source, which is most of them. The other four files
here are derived from it to fix that, and are what `flutter_launcher_icons`
actually reads (see the `flutter_launcher_icons:` block in `pubspec.yaml`).

| File | Role |
| --- | --- |
| `icon_transparent.png` | `source.png` with the white flood-removed (`-fuzz 10% -transparent white`). Dark rounded shape + glyph, transparent corners. Intermediate only. |
| `adaptive_background.png` | A full-bleed 1024×1024 radial gradient, recreated (not cropped) from colors sampled off the source, so it has no baked corner radius — any mask shape can clip it cleanly. Used as `adaptive_icon_background` (Android) and as the base every other icon is composited onto. |
| `icon_master_flat.png` | `adaptive_background.png` with `icon_transparent.png` composited on top, flattened opaque (`-alpha off` — iOS rejects alpha). The rounded shape's own fill matches the regenerated gradient almost exactly, so the seam is invisible. This is the master square used for iOS/macOS/Windows/Web/legacy-Android. |
| `adaptive_foreground.png` | `icon_master_flat.png` scaled to 62% and padded transparent back to 1024×1024, so the glyph sits inside Android's ~66dp adaptive-icon safe zone. Used as `adaptive_icon_foreground`. `adaptive_icon_foreground_inset` is set to `0` in `pubspec.yaml` because this file already carries its own inset — the tool's default 16% would double it. |

## Regenerating after an art change

Replace `source.png`, then from `assets/icon/` (ImageMagick 7 — `magick`):

```sh
magick source.png -fuzz 10% -transparent white icon_transparent.png
magick -size 1024x1024 radial-gradient:"#B2A2D9-#1C1B1F" adaptive_background.png
magick adaptive_background.png icon_transparent.png -gravity center -composite -alpha off icon_master_flat.png
magick icon_master_flat.png -resize 62% -background none -gravity center -extent 1024x1024 adaptive_foreground.png
```

Re-sample the gradient's two colors from the new source if the palette
changed (a background-only point near the center and one near an edge/
corner), then from the app root:

```powershell
dart run flutter_launcher_icons
```
