---
title: How to see every dev server running on your Mac
description: List every listening port on macOS, trace each one back to its project folder and branch, and spot the servers nobody is using, with lsof, ps and a short shell function, or straight from the menu bar.
published: 2026-09-29
updated: 2026-09-29
order: 3
keywords: see all dev servers mac, list listening ports mac, what is running on localhost mac, lsof listening ports, which process is using which port macos, find running node servers mac, list localhost servers
---

Dev servers don’t have windows. Once the terminal tab that started one scrolls out of sight, or an agent launches one in a background shell, the server is just a process holding a port: easy to forget and surprisingly hard to find again. macOS knows about every one of them. The trick is asking in a way that answers the question you actually have, which is less “which PIDs are listening?” and more “which of my projects are running, and since when?”

## Every listening socket, in one command

```bash
lsof -nP -iTCP -sTCP:LISTEN
```

```text
COMMAND     PID USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME
rapportd    612 alex   11u  IPv4 0x52d1a0c4e87f3b21      0t0  TCP *:50372 (LISTEN)
ControlCe   655 alex   11u  IPv4 0x1bb09e7d3c21f4a6      0t0  TCP *:5000 (LISTEN)
ControlCe   655 alex   12u  IPv6 0x8f03c2e1a9d74b50      0t0  TCP *:5000 (LISTEN)
postgres    903 alex    7u  IPv4 0x33e8a5d7b1c0f962      0t0  TCP 127.0.0.1:5432 (LISTEN)
postgres    903 alex    8u  IPv6 0x7c2f9e04a6b5d813      0t0  TCP [::1]:5432 (LISTEN)
figma_age  1104 alex    6u  IPv4 0x4e1d0b8f2a7c6395      0t0  TCP 127.0.0.1:44950 (LISTEN)
node      48213 alex   23u  IPv6 0x9c41d7e25a0b13f8      0t0  TCP *:3000 (LISTEN)
node      48655 alex   28u  IPv6 0x0d6e2f4b8c1a9375      0t0  TCP [::1]:5173 (LISTEN)
python3.1 49002 alex    3u  IPv4 0x6a7b3c9d1e2f4058      0t0  TCP 127.0.0.1:8000 (LISTEN)
```

A few things to know when reading it:

- Plenty of listeners aren’t dev servers. `rapportd` and `ControlCenter` are part of macOS, and desktop apps such as Figma run local helpers.
- A server that listens on both IPv4 and IPv6 appears twice.
- COMMAND is cut to nine characters (`python3.1` is Python 3.12, `ControlCe` is ControlCenter). Add `+c 0` before the other flags for full names.
- It only covers processes you own. `netstat -anv -p tcp | grep LISTEN` includes root’s and other users’ listeners, with a `process:pid` column. For your own dev servers, `lsof` is enough.

## From process IDs to project folders

The useful thing to know about a dev server isn’t that it’s `node`, but which project it was started from. Every process has a working directory, and `lsof -d cwd` reveals it. That also gives you a handy filter: apps and system services launched by macOS usually run with `/` as their working directory, while servers you start from a project run inside it.

Add this to `~/.zshrc` (it works in bash too):

```bash
devservers() {
  for pid in $(lsof -tiTCP -sTCP:LISTEN | sort -un); do
    dir=$(lsof -a -p "$pid" -d cwd -Fn | sed -n 's/^n//p')
    [ "$dir" = "/" ] && continue
    ports=$(lsof -nP -a -p "$pid" -iTCP -sTCP:LISTEN -Fn | sed -n 's/^n.*://p' | sort -un | paste -sd, -)
    printf '%-7s %-24s %-11s %s\n' "$pid" "$(basename "$(ps -o comm= -p "$pid")")" "$ports" "$dir"
  done
}
```

Open a new terminal and run `devservers`:

```text
903     postgres                 5432        /opt/homebrew/var/postgresql@16
48213   next-server (v16.2.10)   3000        /Users/alex/code/shop
48655   node                     5173        /Users/alex/code/docs
49002   python3                  8000        /Users/alex/code/api
```

How it works:

- `lsof -tiTCP -sTCP:LISTEN` prints the PID of every listening process, and `sort -un` drops the duplicates from IPv4 and IPv6 lines.
- `lsof -a -p PID -d cwd -Fn` prints the working directory in a machine-readable format, and `sed` keeps just the path.
- The second `lsof` call collects that process’s listening ports and joins them with commas.
- `ps -o comm=` supplies the process name. Next.js renames its server process, which is why it shows as `next-server (v16.2.10)` rather than `node`.

## Add branch, age and memory

For a closer look at one of them:

```bash
git -C /Users/alex/code/shop branch --show-current
ps -o pid,ppid,etime,rss,command -p 48213
```

`etime` is how long the process has been running (`03-02:14:09` means three days and two hours), and `rss` is resident memory in kilobytes. Treat that memory figure as a lower bound: a dev server is often several processes, and the listener is only one of them. [Dev server memory on a Mac](/guides/dev-server-memory-leak-mac) shows how to total a whole process tree.

## Is anyone still using it?

A server can be running without being used. To see whether anything is connected right now:

```bash
lsof -nP -iTCP:3000 -sTCP:ESTABLISHED
```

No output means no open connections at this moment. Combine that with a long uptime and a parent PID of 1, which for a server you started means whatever launched it has since exited, and you have a good candidate for stopping. Servers that look like that were often started by coding agents; [Claude Code left a dev server running?](/guides/claude-code-dev-server-left-running) shows how to trace them back to a session.

## What a snapshot can’t tell you

Everything above is a single moment. It won’t tell you that a server has been idle all afternoon, that its memory doubled in the last ten minutes, or that its git worktree was deleted this morning. You can script your way there, but at that point you’re writing a monitor.

## The same list, always visible

Porto is that monitor, as a native menu bar app. It rescans every 2 seconds and sits in the menu bar as a small dot-grid icon, optionally with the number of running servers beside it; click it or press ⌃⌥⌘P for the list. Each server appears with its port, project name, git branch, uptime, memory and CPU, and keeps the same colour for its port so you learn to recognise it. Under the hood it reads the same `lsof` data, then inspects each server’s whole process tree, its project manifest (package.json, pyproject.toml, Cargo.toml, go.mod or Gemfile) and its branch. A memory bar shows your Mac’s RAM split between dev servers, other apps and free memory.

In the terminal, `porto list` prints the table and `porto list --json` gives scripts and agents the same data. [Download Porto](/Porto.dmg), or see [what to do when port 3000 is already in use](/guides/port-3000-already-in-use-mac).
