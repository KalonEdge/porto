---
title: Port 3000 already in use on a Mac? Find the process and free the port
description: Find out what is holding port 3000 on macOS with lsof and ps, stop it without hitting the wrong process, and deal with servers that come straight back after you kill them.
published: 2026-09-29
updated: 2026-09-29
order: 1
keywords: port 3000 already in use mac, kill process on port 3000 mac, lsof port 3000, find process using port macos, free up port 3000 mac, listen EADDRINUSE 3000, what is using port 3000
---

Port 3000 is the most fought-over number on a developer’s Mac. Next.js uses it by default, many Node tutorials pick it, and whatever grabbed it first keeps it until that process exits. When your server loses the fight, Node says so plainly:

```text
Error: listen EADDRINUSE: address already in use :::3000
```

Some frameworks don’t complain at all and quietly move to 3001, which is worse: the tab you have open on 3000 keeps showing the old server. Either way, the job is the same. Find the process, make sure it’s the one you think it is, and stop it in a way that actually frees the port.

## Ask macOS who is listening

```bash
lsof -nP -iTCP:3000 -sTCP:LISTEN
```

```text
COMMAND   PID USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME
node    48213 alex   23u  IPv6 0x9c41d7e25a0b13f8      0t0  TCP *:3000 (LISTEN)
```

| Part | What it does |
| --- | --- |
| `-iTCP:3000` | Only TCP sockets on port 3000 |
| `-sTCP:LISTEN` | Only sockets accepting connections, so clients connected to the port are left out |
| `-n` | Skips reverse DNS lookups, which keeps it fast |
| `-P` | Prints port numbers instead of service names |

Three details are worth knowing before you act on the output:

- The COMMAND column is cut to nine characters, so `python3.12` appears as `python3.1`. Put `+c 0` before the other flags to see full names.
- An empty result doesn’t prove the port is free. Without `sudo`, `lsof` only lists your own processes. `netstat -anv -p tcp | grep LISTEN` shows listeners owned by any user, with a `process:pid` column near the end of each line.
- Two lines for one port can be a single server listening on both IPv4 and IPv6, or two different servers on different addresses. The second case is sneakier than it sounds; [EADDRINUSE, explained](/guides/eaddrinuse-address-already-in-use) shows how it happens.

### A note on the popular one-liner

You’ll often see `kill -9 $(lsof -ti :3000)` recommended. Without `-sTCP:LISTEN`, though, `lsof -ti :3000` returns every process with a connection involving port 3000, and that can include your browser if a tab has the app open. If you want a one-liner, this one targets only the listener and lets it shut down cleanly:

```bash
kill $(lsof -tiTCP:3000 -sTCP:LISTEN)
```

## Put a name to the PID

The name `node` tells you very little. Ask for the command line, the parent and the age, then the folder the process runs in:

```bash
ps -o pid,ppid,etime,command -p 48213
lsof -a -p 48213 -d cwd
```

```text
  PID  PPID     ELAPSED COMMAND
48213 48190 02-04:10:33 next-server (v16.2.10)

COMMAND   PID USER   FD   TYPE DEVICE SIZE/OFF     NODE NAME
node    48213 alex  cwd    DIR   1,15      640 91823344 /Users/alex/code/shop
```

Now you know it’s the Next.js server for `~/code/shop`, and ELAPSED says it has been up for two days and four hours. The PPID is its parent, in this case the `next dev` command that launched it. If a server you started yourself shows a PPID of `1`, whatever launched it (a terminal, a script, an agent) has exited and launchd has adopted it.

## Stop it cleanly

```bash
kill 48213
```

Plain `kill` sends SIGTERM, which gives the server a chance to close its socket and exit. Run the `lsof` command again. If the line is still there after a few seconds, escalate:

```bash
kill -9 48213
```

SIGKILL can’t be caught or ignored, so no shutdown code runs at all. Keep it as the fallback.

A dev server is usually a small family of processes, though: `npm` starts the framework’s CLI, and the CLI starts the process that actually serves your app. Kill only the listener and its parent may exit, or start a new one. Kill only a parent and the child can carry on as an orphan with PPID 1, still holding the port.

In a terminal, Ctrl-C avoids both problems because it signals the whole foreground process group. You can do the same from anywhere:

```bash
ps -o pgid= -p 48213
pgrep -lg 48170
kill -- -48170
```

The first command prints the process group ID (48170 here, the `npm` process that started everything). The second lists the group’s members, so you can check it contains only the server before you signal it. The third sends SIGTERM to every process in the group; note the minus sign in front of the number.

## A listener that respawns

If the listener reappears seconds after you stop it, something is restarting it. Look at the parent before you kill again:

- **A Homebrew service.** Anything started with `brew services start` runs as a launchd agent, and many are set to KeepAlive, so launchd relaunches them the moment they exit. `brew services list` shows what’s registered, and `brew services stop postgresql@16` (or whichever formula it is) stops it properly.
- **A supervisor.** Process managers such as pm2 restart a server as soon as it exits, and watchers like nodemon or `node --watch` start a new one on the next file change. Stop the supervisor, or the whole process group as above.
- **A container.** If `lsof` points at your container runtime rather than a language runtime, the port is being forwarded to a container. Stop the container instead.
- **A coding agent.** An agent may simply start the server again on its next turn. [Claude Code left a dev server running?](/guides/claude-code-dev-server-left-running) covers tracing a server back to the session that started it.

## Stop fighting over 3000

- Pick a port per project and write it into the project’s dev script, so nobody has to remember it.
- Make the dev server fail when its port is busy instead of drifting to the next one. [Vite on 5174, Next.js on 3001](/guides/vite-port-5174-nextjs-port-3001) shows the settings for both.
- Stop servers when you’re done with them, especially ones started in background shells or by agents.

## How Porto helps

Porto is a free, open-source menu bar app that keeps the answer to “what’s on 3000?” one click away. It lists every dev server on your Mac with its port, project, git branch, uptime, memory and CPU. Stop sends SIGTERM to the server’s entire process tree and follows up with SIGKILL after 3 seconds if anything is still running, so no orphan is left holding the port. In the terminal, `porto list` prints the same table.

[Download Porto](/Porto.dmg), or read [how to see every dev server running on your Mac](/guides/see-every-dev-server-running-on-mac).
