# Third-party notices

Neylu links against frameworks and libraries supplied by macOS: AppKit, SwiftUI,
CoreText, SystemConfiguration, ServiceManagement, IOKit, DiskArbitration and SQLite.
No third-party runtime library is bundled.

## Stats — sensor mapping reference

The Intel and Apple M1–M5 CPU sensor-key mappings in `Sources/Temperature.swift` were informed by
[Stats](https://github.com/exelban/stats), specifically
[`Modules/Sensors/values.swift`](https://github.com/exelban/stats/blob/a0b1c12e8b2162721450962623cb80bf5ee09001/Modules/Sensors/values.swift).
Neylu's reader is read-only; Stats is not bundled. The upstream attribution and
license are retained below for that reference material.

MIT License

Copyright (c) 2019 Serhiy Mytrovtsiy

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

## Artwork

The default icon is the editable vector `Assets/AppIcon-v5-vector.svg`, reconstructed
for this project from an imagegen-assisted concept. Project-authored artwork is
included under the repository's MIT license. Historical raster concepts in
`Design/` are retained for provenance and excluded from Git source archives.
System SF Symbols are rendered by macOS and are not redistributed as standalone artwork.
