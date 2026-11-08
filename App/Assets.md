# F1 logo

`Assets.xcassets/F1Logo.imageset/f1-logo.svg` comes from Formula 1's official website:
https://www.formula1.com/assets/home/_next/static/media/f1-logo.43a01c6b.svg

Retrieved November 7, 2026. The SVG viewport is cropped to the artwork for the app
bar; the original path, colour and registered trademark symbol are preserved.
The vector image is bundled for offline use on macOS and iOS.

The F1 logo is a trademark of Formula One Licensing BV. Formula Live remains an
unofficial companion.

After a macOS build, verify the bundled rendition with:

```sh
swift Scripts/verify-logo.swift /path/to/FormulaLive.app
```
