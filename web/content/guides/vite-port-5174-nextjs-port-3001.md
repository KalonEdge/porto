---
title: Vite on 5174 and Next.js on 3001? The old server is still running
description: When Vite reports port 5173 in use and Next.js falls back to 3001, an earlier dev server is still alive. How to find it, stop it, and make Vite and Next.js fail loudly instead of drifting.
published: 2026-09-29
updated: 2026-09-29
order: 6
keywords: port 5173 is in use trying another one, vite port 5174, vite strictPort, port 3000 is in use trying 3001 instead, next.js using available port 3001 instead, next dev port already in use, dev server started on wrong port
---

A dev server that comes up on the wrong port is telling you something: an older one is still alive. Vite reports it like this when 5173 is taken:

```text
Port 5173 is in use, trying another one...

  VITE v7.3.2  ready in 261 ms

  ➜  Local:   http://localhost:5174/
```

Next.js 15.5 and 16 print this when 3000 is taken and you haven’t chosen a port:

```text
⚠ Port 3000 is in use by process 48213, using available port 3001 instead.
```

Older releases (Next.js 14 and 15.0) word it as `Port 3000 is in use, trying 3001 instead.`

Neither message is an error, and that’s the problem. Both tools found their default port busy and moved up by one, so the server you just started is fine, but whatever holds the original port is still running. Usually that’s an earlier copy of the same project, serving yesterday’s code to whichever tab you left open.

## Why drifting is worse than an error

- Bookmarks, OAuth redirect URLs and API clients still point at the old port, so it’s easy to test the old server without noticing.
- Hot reload works in the new tab and does nothing in the old one, so your edits appear to vanish depending on which tab you look at.
- Two copies use twice the memory, and they may both write to the same local database or cache.

## Track down the older copy

```bash
lsof -nP -iTCP:5173 -sTCP:LISTEN
```

Take the PID from that output (Next.js 15.5 and later usually put it in the warning for you), then ask what it is and where it runs:

```bash
ps -o pid,ppid,etime,command -p 48213
lsof -a -p 48213 -d cwd
```

For Next.js you’ll often see `next-server (v16.2.10)`: that’s the process Next.js runs your app in, and its parent is the `next dev` command. Stop the pair together (Ctrl-C in its terminal, or the process-group approach in [port 3000 already in use](/guides/port-3000-already-in-use-mac)), then start your server again on the port it should have had.

## Vite: turn on strictPort

Turn on `strictPort` in `vite.config.js`:

```js
import { defineConfig } from 'vite'

export default defineConfig({
  server: {
    port: 5173,
    strictPort: true,
  },
})
```

Or pass `--strictPort` on the command line; `vite preview` accepts it too. With it, a busy port stops the server:

```text
error when starting dev server:
Error: Port 5173 is already in use
```

## Next.js: name the port

Next.js only searches for a free port when you haven’t chosen one. Give it a port explicitly, with `-p` or the `PORT` environment variable, and a busy port becomes an error:

```json
{
  "scripts": {
    "dev": "next dev -p 3000"
  }
}
```

```text
⨯ Failed to start server
Error: listen EADDRINUSE: address already in use :::3000
```

## When neither tool warns you

Both frameworks only notice a conflict when the other server holds exactly the same address. Vite listens on `localhost`, which a current Node.js on macOS resolves to the IPv6 address `::1`. `next dev` listens on all interfaces (`::`). A server bound only to IPv4 `127.0.0.1` blocks neither of them. In our tests, Vite and Next.js both started on a port that another server was already using on `127.0.0.1`, without a word.

You then have two servers on one port number, and which one you reach depends on the address you type: `localhost` usually goes to IPv6 first, `127.0.0.1` never does. `lsof -nP -iTCP:5173 -sTCP:LISTEN` gives it away with two lines, one on `127.0.0.1:5173` and one on `[::1]:5173` or `*:5173`. [EADDRINUSE, explained](/guides/eaddrinuse-address-already-in-use) goes into why macOS allows this.

## What each tool does when its port is taken

| Tool | Default | Choose a port with | When the port is busy |
| --- | --- | --- | --- |
| Vite dev server | 5173 | `--port`, `server.port` | Tries the next port, unless `strictPort` is set |
| Vite preview | 4173 | `--port`, `preview.port` | Same, with `--strictPort` or `preview.strictPort` |
| Next.js dev | 3000 | `-p`, `PORT` | Tries up to ten more ports if you didn’t choose one; otherwise exits |
| Flask | 5000 | `--port`, `FLASK_RUN_PORT` | Exits with an error |
| uvicorn | 8000 | `--port` | Exits with an error |
| Python `http.server` | 8000 | Port argument, e.g. `python3 -m http.server 8001` | Exits with an error |

To pass a flag through an npm script without editing it, put it after `--`, as in `npm run dev -- --port 5180`.

Flask’s 5000 has its own complication on a Mac: macOS’s AirPlay Receiver uses the same port. [Why port 5000 is taken on your Mac](/guides/port-5000-in-use-mac-airplay) explains what to do about it.

## How Porto helps

Porto lists every dev server on your Mac with its port, project, git branch and uptime, so the server still sitting on 5173 or 3000 is visible before you start another one. Stop ends it together with its whole process tree. From the terminal, `porto list` shows the same list. [Download Porto](/Porto.dmg), or read [how to see every dev server running on your Mac](/guides/see-every-dev-server-running-on-mac).
