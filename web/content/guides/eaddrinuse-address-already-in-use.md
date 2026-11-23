---
title: EADDRINUSE and address already in use on macOS, explained
description: What the address-in-use error means in Node.js, Python, Ruby, Go, Deno and Bun on a Mac, why a port can be taken twice without any error at all, and how to stop the error coming back.
published: 2026-09-29
updated: 2026-09-29
order: 2
keywords: EADDRINUSE, address already in use, listen EADDRINUSE address already in use :::3000, errno 48 address already in use, OSError Errno 48 mac, Errno::EADDRINUSE, bind address already in use, nodemon EADDRINUSE
---

A server claims its port in two steps: it binds a socket to an address and port, then starts listening on it. If another socket on the Mac already holds that exact address and port, the kernel refuses the bind with error 48, `EADDRINUSE` (Linux numbers the same error 98). That number is why Python prints `[Errno 48]` and why Node’s error object carries `errno: -48`. The port simply has an owner.

## How each runtime reports it

These are the messages we got on macOS when the port was already taken:

```text
Node.js   Error: listen EADDRINUSE: address already in use :::3000
Python    OSError: [Errno 48] Address already in use
uvicorn   ERROR:    [Errno 48] error while attempting to bind on address ('127.0.0.1', 8000): [errno 48] address already in use
Ruby      Address already in use - bind(2) for "127.0.0.1" port 3000 (Errno::EADDRINUSE)
Go        listen tcp :8080: bind: address already in use
Deno      error: Uncaught (in promise) AddrInUse: Address already in use (os error 48)
Bun       error: Failed to start server. Is port 3000 in use?
```

In every case the next move is to find the owner with `lsof -nP -iTCP:3000 -sTCP:LISTEN` (swap in your port) and decide whether it should keep the port. [Port 3000 already in use](/guides/port-3000-already-in-use-mac) walks through that step by step.

## Read the address, not just the port

The text after “in use” names the address your server asked for:

- `:::3000` is the IPv6 wildcard `::` on port 3000. Node uses it when you call `listen(3000)` without a host, and on macOS that socket accepts IPv4 connections too.
- `127.0.0.1:3000` is IPv4 loopback only. You get it when a server binds to `127.0.0.1`, as Flask and uvicorn do by default.
- `[::1]:3000` in `lsof` output is IPv6 loopback. Vite listens there by default, because with a current Node.js on macOS, `localhost` resolves to `::1` first.

## Taken twice, with no error at all

EADDRINUSE only fires when the exact same address and port are already taken. macOS will let a second server bind a more specific address on a port that another process holds as a wildcard, and it treats IPv4 and IPv6 loopback as different addresses. In our tests:

- A Python server on `127.0.0.1:3000` did not stop a Node server from starting on `:::3000`.
- A server on the `*` wildcard did not stop another from binding `127.0.0.1` on the same port.
- Neither Vite nor Next.js warned about a server that held only `127.0.0.1` on their port.

With two listeners on one port, the client’s choice of address decides who answers. `http://127.0.0.1:3000` reached the Python server; `http://localhost:3000` reached Node, because curl and browsers typically try IPv6 first. `lsof` shows both:

```text
COMMAND     PID USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME
python3.1 51022 alex    3u  IPv4 0x7a8d1f3c2b9e4d10      0t0  TCP 127.0.0.1:3000 (LISTEN)
node      51040 alex   12u  IPv6 0x1e44c0b9a7d35f82      0t0  TCP *:3000 (LISTEN)
```

If the terminal says one thing and the browser shows another, look for a second line like this. The best-known case is port 5000, which macOS’s AirPlay Receiver shares with Flask; see [why port 5000 is taken on your Mac](/guides/port-5000-in-use-mac-airplay).

## Diagnose the owner from what ps tells you

With the PID from `lsof` (48213 here), `ps -o pid,ppid,etime,command -p 48213` and `lsof -a -p 48213 -d cwd` usually make the cause obvious:

| What you see | What it usually means | What to do |
| --- | --- | --- |
| Your project’s folder, parent is a shell or `npm`, running for hours | A copy you forgot in another terminal tab, or the same project started twice | Stop it, or use it instead of starting another |
| Your project’s folder, parent PID is 1 | An orphan: its parent was stopped but the server wasn’t | Stop it, ideally with its whole process group |
| Your own server, only seconds old, while a watcher is restarting | The previous copy hadn’t exited when the new one started | Make the server exit on the watcher’s signal (below) |
| `ControlCenter`, `postgres`, `redis-server` or a container runtime | Something that isn’t your dev server at all | Switch off AirPlay Receiver, stop the service or stop the container |

Orphans are easy to create: when we terminated the shell that had launched a Node server, the server kept running with a parent PID of 1 and its port still bound. Signalling the whole process group, which is what Ctrl-C does in a terminal, avoids that. Watcher restarts depend on the signal: Node’s built-in `--watch` mode sends SIGTERM, while nodemon sends SIGUSR2 unless you choose another with `--signal`. Code that catches the signal and never exits leaves the new process facing its predecessor.

## Make your own server fail helpfully

If you write the server, you can make the failure self-explanatory and make shutdown clean. In Node:

```js
const http = require('node:http');

const port = Number(process.env.PORT) || 3000;
const server = http.createServer((req, res) => res.end('ok\n'));

server.on('error', (err) => {
  if (err.code === 'EADDRINUSE') {
    console.error(`Port ${port} is busy. See who has it: lsof -nP -iTCP:${port} -sTCP:LISTEN`);
    process.exit(1);
  }
  throw err;
});

server.listen(port, () => console.log(`Listening on http://localhost:${port}`));

// Let go of the port when a watcher or terminal asks us to stop.
for (const signal of ['SIGINT', 'SIGTERM']) {
  process.once(signal, () => {
    server.close(() => process.exit(0));
    server.closeIdleConnections();
    setTimeout(() => process.exit(0), 2000).unref();
  });
}
```

The error handler turns a stack trace into an instruction, and the signal handlers release the port so a watcher’s restart finds it free (`closeIdleConnections()` stops idle keep-alive connections from delaying `close()`, and the timer is a backstop). In Python:

```python
import errno
from http.server import HTTPServer, SimpleHTTPRequestHandler

PORT = 8000

try:
    server = HTTPServer(("127.0.0.1", PORT), SimpleHTTPRequestHandler)
except OSError as e:
    if e.errno == errno.EADDRINUSE:
        raise SystemExit(f"Port {PORT} is busy. See who has it: lsof -nP -iTCP:{PORT} -sTCP:LISTEN")
    raise

print(f"Serving on http://127.0.0.1:{PORT}")
server.serve_forever()
```

For tests, you can sidestep the problem: `listen(0)` asks macOS for any free port, and `server.address().port` tells you which one you got.

## How Porto helps

Porto shows every dev server in the menu bar with its port, project and git branch, so “what’s on 3000?” already has an answer before you hit the error. When you stop a server from Porto, it signals the server’s whole process tree (SIGTERM, then SIGKILL after 3 seconds), so orphaned children don’t keep ports busy. [Download Porto](/Porto.dmg), and see [why Vite starts on 5174 and Next.js on 3001](/guides/vite-port-5174-nextjs-port-3001) for the frameworks that dodge the error by moving ports.
