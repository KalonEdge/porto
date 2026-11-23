# Porto

Every dev server on your Mac, in the menu bar.

Porto is a native macOS menu bar app that finds every development server listening on your Mac, tells you which project, branch and coding agent (Claude Code, Codex, Conductor) each one belongs to, watches their memory, and stops the ones you forgot. The same scanner runs in the terminal as `porto`.

```
app/   the Mac app and the `porto` command (Swift, SwiftUI, macOS 14+)
web/   the website: landing page, guides, llms.txt (Next.js 16)
```

## The app

```bash
cd app
swift run Porto            # the menu bar app
swift run Porto --tui      # the terminal UI
swift run Porto --tui list --json
swift test                 # 23 tests: translations, terminal input and layout, the scanner, onboarding
```

Build a signed app bundle and the website's disk image:

```bash
./build-app.sh             # .build/Porto.app (ad-hoc signed unless CODE_SIGN_IDENTITY is set)
./make-dmg.sh              # .build/Porto.dmg
cp .build/Porto.dmg ../web/public/Porto.dmg
```

Releases with notarization and signed automatic updates: [`app/UPDATES.md`](app/UPDATES.md).

**How it works.** Every scan (every 2 seconds by default) reads the process table and each watched process's sockets straight from the kernel through `libproc`, so there's no `lsof` to spawn. Only processes on the watch list (node, bun, python3.12, ruby, …, editable in Settings) are inspected, within the port range you choose. Projects come from each server's working directory (package.json, git branch, framework), agent sessions from the process tree and the agents' session files, and memory is the full process tree's footprint, the way Activity Monitor counts it.

**Terminal.** Settings → General → Terminal installs `/usr/local/bin/porto`, a link to the app's own binary. `porto` opens the full-screen TUI (keyboard and mouse), `porto list` prints a table and `porto list --json` gives scripts and agents the same data.

**Assets drawn from code.** The app icon, the website's touch icon and the disk image background are SwiftUI views, rendered with `Porto --render-icon <dir>` and `Porto --render-dmg-background dmg`. `Porto --snapshot <dir> [--appearance dark] [--ui-language de]` renders every popover page, Settings pane and onboarding step to PNG with live data.

## The website

```bash
cd web
npm install
npm run dev                # http://localhost:8186
npm run build && npm start # production, same port
```

| Script | What it does |
| --- | --- |
| `npm run typecheck` | TypeScript, after `npx next typegen` |
| `npm run sync:i18n` | Copies the popover demo's strings from the app's translation tables |
| `npm run assets` | Encodes AVIF and WebP versions of the photography |
| `npm run og` | Saves the share card (the dev-only `/og` page) to `public/og-image.png` |

Settings, all optional:

| Variable | Default | Used for |
| --- | --- | --- |
| `NEXT_PUBLIC_SITE_URL` | `http://localhost:8186` | Canonical URLs, sitemap, structured data |
| `NEXT_PUBLIC_GITHUB_REPO` | `KalonEdge/porto` | GitHub links and the star count |
| `NEXT_PUBLIC_AUTHOR_NAME`, `NEXT_PUBLIC_AUTHOR_URL` | `the Porto team` | Byline and footer link |
| `PORTO_DOWNLOAD_URL` | none | Where `/Porto.dmg` redirects when `public/Porto.dmg` isn't there |
| `TIP_URL` | none | Where `/tip` (the app's tip jar) redirects |

Every page has a Markdown twin for agents (`/index.md`, `/guides/<slug>.md`), plus `/llms.txt` and `/llms-full.txt`. The app's anonymous usage pings (`/usage/<feature>`, opt-out in Settings) get an empty `204` from `proxy.ts`, which records nothing itself.

## Credits

Porto is an independent rebuild of [WhatThePort](https://whattheport.dev) (MIT). See [NOTICE.md](NOTICE.md) for the material it shares and for third-party licenses.
