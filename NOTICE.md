# Notices

## WhatThePort

Porto is an independent rebuild of WhatThePort. The code in this repository is new, but the website's design follows whattheport.dev, and the following material comes from, or is adapted from, the WhatThePort project:

- The scene and wallpaper photography in `web/public/scenes` and `web/public/wallpapers` (re-encoded as AVIF and WebP).
- The interface translations in `app/Sources/Porto/Resources/*.lproj` and `web/lib/i18n/strings.json` (adapted to Porto's names and copy).
- The topics of the guides in `web/content/guides`.

WhatThePort is distributed under the MIT License:

```
MIT License

Copyright (c) 2026 Tomjohn Design LLC

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
```

## Third-party software and fonts

| Component | License | Where |
| --- | --- | --- |
| Geist and Geist Mono (Vercel) | SIL Open Font License 1.1 | `app/Resources/Fonts/OFL.txt`, `web/public/fonts/OFL.txt` |
| Sparkle 2 | MIT | Bundled as `Sparkle.framework`; its license ships inside the framework |
| Next.js, React, marked | MIT | `web/node_modules` |
