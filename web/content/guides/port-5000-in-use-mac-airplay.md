---
title: Why port 5000 is taken on your Mac, and why Flask shows 403 Forbidden
description: macOS’s AirPlay Receiver listens on ports 5000 and 7000, so Flask either refuses to start or localhost:5000 answers 403 Forbidden. How to confirm it, switch it off, or move your app.
published: 2026-09-29
updated: 2026-09-29
order: 8
keywords: port 5000 already in use mac, port 5000 controlcenter, airplay receiver port 5000, flask 403 forbidden localhost mac, flask port 5000 mac, port 7000 in use mac, AirTunes 403 forbidden
---

Flask’s development server defaults to port 5000. On a Mac with AirPlay Receiver switched on, so does macOS: the ControlCenter process listens on ports 5000 and 7000, on every interface, so your other Apple devices can stream to the Mac. Depending on how your app binds, you’ll run into one of two symptoms.

**The server won’t start.** Anything that binds to all interfaces collides head-on. `flask run --host 0.0.0.0` stops with Werkzeug’s own diagnosis:

```text
Address already in use
Port 5000 is in use by another program. Either identify and stop that program, or start the server with a different port.
On macOS, try disabling the 'AirPlay Receiver' service from System Preferences -> General -> AirDrop & Handoff.
```

**The server starts, but the browser gets 403 Forbidden.** Plain `flask run` binds only to `127.0.0.1`, and macOS allows that alongside ControlCenter’s wildcard listener. Flask prints `Running on http://127.0.0.1:5000`, and that address works. But `http://localhost:5000` is usually tried over IPv6 first, and on IPv6, port 5000 belongs to ControlCenter, which answers with an empty 403. Nothing in Flask’s output hints at a problem, because from Flask’s point of view nothing is wrong. We reproduced exactly this with Flask 3.1: `127.0.0.1:5000` returned the app, `localhost:5000` returned AirPlay’s 403.

## Why the 403 case has no error

`EADDRINUSE` only fires when the exact same address and port are taken. A server bound to `127.0.0.1` doesn’t collide with a listener on the `*` wildcard, so macOS lets both exist and the address in your browser decides which one answers. The same effect catches Vite and Next.js users on other ports; [EADDRINUSE, explained](/guides/eaddrinuse-address-already-in-use) covers it in detail.

## Two quick checks

```bash
lsof +c 0 -nP -iTCP:5000 -sTCP:LISTEN
```

```text
COMMAND        PID USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME
ControlCenter  655 alex   11u  IPv4 0x1bb09e7d3c21f4a6      0t0  TCP *:5000 (LISTEN)
ControlCenter  655 alex   12u  IPv6 0x8f03c2e1a9d74b50      0t0  TCP *:5000 (LISTEN)
```

`+c 0` prints the full command name; without it you’ll see `ControlCe`. If Flask is running too, a third line shows its Python process (for example `python3.12`) on `127.0.0.1:5000`. You can also ask the listener what it is:

```bash
curl -sI http://localhost:5000/
```

```text
HTTP/1.1 403 Forbidden
Content-Length: 0
Server: AirTunes/980.77.5
```

AirTunes is AirPlay’s server. Port 7000 answers the same way. Don’t kill ControlCenter to get the port back: it also runs Control Center and other parts of the menu bar, and the setting that opens the port stays on. The switch is in System Settings.

If `lsof` shows something other than ControlCenter on port 5000, you have an ordinary port conflict instead, and [port 3000 already in use](/guides/port-3000-already-in-use-mac) applies to any port number.

## Give the port back to your apps

Open System Settings → General → AirDrop & Continuity and turn off AirPlay Receiver. Older versions of macOS call the pane AirDrop & Handoff, which is the name Werkzeug’s message still uses. Afterwards, run the `lsof` command again: ControlCenter should no longer be listening on 5000 or 7000.

The trade-off is that your iPhone, iPad and other Macs can’t AirPlay to this Mac until you turn it back on. If you never use that, this is the cleanest fix.

## Run Flask somewhere else

For a single run:

```bash
flask --app app run --port 5001
```

Or set it once in your shell, and every `flask run` picks it up:

```bash
export FLASK_RUN_PORT=5001
```

If you start the development server from code, pass the port to `app.run`:

```python
if __name__ == "__main__":
    app.run(port=5001)
```

The same goes for any other tool that defaults to 5000 or 7000: give it a different port, and write that port into the project’s scripts so everyone uses it.

## Keep both, and type 127.0.0.1

If you want to keep both AirPlay Receiver and port 5000, open `http://127.0.0.1:5000` instead of `http://localhost:5000`. It works because Flask is bound to exactly that address. It’s fragile, though. OAuth redirect URLs, CORS allow-lists and teammates’ bookmarks tend to say `localhost`, and every one of those will land on AirPlay instead of your app.

## How Porto helps

Porto keeps your own dev servers in the menu bar with their port, project and git branch. By default it watches ports 3000 to 65535 and Python servers among other runtimes (`python`, `python3` and versioned names such as `python3.12`, plus `uvicorn` and `gunicorn`), so a Flask app you moved to 5001 shows up with its project name, and you can see at a glance which port it actually got. Both the port range and the process list can be changed in Settings → Ports & processes.

[Download Porto](/Porto.dmg), or read [what to do when port 3000 is already in use](/guides/port-3000-already-in-use-mac).
