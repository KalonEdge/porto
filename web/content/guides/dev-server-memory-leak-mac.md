---
title: Dev server eating your Mac’s memory? How to measure it and spot a leak
description: Why local dev servers grow to gigabytes, how to measure a server’s whole process tree on macOS with ps and footprint, how to tell a leak from normal growth, and what to do before your Mac runs out of memory.
published: 2026-09-29
updated: 2026-09-29
order: 7
keywords: next dev memory leak, dev server high memory usage mac, vite memory usage, node memory leak mac, too many node processes mac, your system has run out of application memory, footprint command mac, javascript heap out of memory
---

A dev server’s memory use is easy to underestimate. Activity Monitor shows it as a few anonymous `node` rows, none of them alarming on its own, and the real total only becomes obvious when macOS starts compressing memory, swapping and asking you to quit apps. This guide shows how to put one honest number on a server, how to tell a leak from a big but stable project, and what to do in each case.

## One server, several processes

The process holding the port is rarely the whole server. Two we measured on macOS:

- **Next.js 16** ran `next dev` as two processes: the `next dev` command itself and a child that renames itself `next-server (v16.2.10)`, which holds the port and does most of the work. For a one-page test app the pair used about 390 MB, 350 MB of it in the child.
- **Vite 7** ran as a Node process plus an `esbuild --service` child.

Type checkers, test watchers and framework workers add more. An honest number has to include the whole tree. This shell function prints a process and all of its descendants:

```bash
tree_pids() { echo "$1"; for c in $(pgrep -P "$1"); do tree_pids "$c"; done; }
```

Start from the top of the server (the `next dev` or `npm run dev` process rather than the listener) and list the tree with resident memory in kilobytes:

```bash
ps -o pid,ppid,rss,command -p "$(tree_pids 48190 | paste -sd, -)"
```

```text
  PID  PPID    RSS COMMAND
48190 48170  62432 node /Users/alex/code/shop/node_modules/.bin/next dev
48213 48190 398912 next-server (v16.2.10)
```

## RSS overstates, footprint doesn’t

RSS counts every page a process has in RAM, including shared libraries that many processes map, so adding RSS up across a tree double-counts. macOS ships a `footprint` tool that reports each process’s physical footprint, the memory it is actually responsible for, and totals it for you:

```bash
footprint --noCategories $(tree_pids 48190) | grep Footprint
```

```text
node [48213]: 64-bit    Footprint: 352 MB (16384 bytes per page)
node [48190]: 64-bit    Footprint: 36 MB (16384 bytes per page)
Summary Footprint: 388 MB
```

## Reading the curve

Size alone says little: large apps compile large module graphs, and a few gigabytes can be normal. The shape over time is what gives a leak away:

- **Normal growth** rises during the first compiles and page loads, then levels off. It may jump after a big change and settle back after garbage collection.
- **A leak** climbs with every edit or request and never comes back down, even while the server sits idle.

To see the shape, sample the main process once a minute while you work:

```bash
footprint --noCategories --sample 60 -p 48213
```

Each sample prints a new `Footprint:` line until you press Ctrl-C. Ten or fifteen minutes of ordinary editing is usually enough to tell which curve you’re on.

## Your options, quickest first

- **Shut down idle servers first.** Often the biggest win of all: three forgotten servers at a gigabyte each cost more than one leaky server. [See every dev server on your Mac](/guides/see-every-dev-server-running-on-mac) helps you find them.
- **Restart the one that’s growing.** A dev server rarely holds state you can’t recreate, and restarting returns its memory immediately. For slow growth, that’s often the pragmatic fix.
- **Cap the heap so it fails fast.** `NODE_OPTIONS=--max-old-space-size=4096 npm run dev` limits the JavaScript heap of each Node process to about 4 GB. A leaking server then crashes with `FATAL ERROR: Reached heap limit Allocation failed - JavaScript heap out of memory` instead of pushing your Mac into swap. It doesn’t cap native memory, and a value that’s too low will crash large, healthy projects.
- **Update the framework.** Dev-server leaks are often fixed in patch releases, so read the changelog before you start digging.
- **Profile your own server.** For a Node server you wrote, start it with `node --inspect server.js`, open `chrome://inspect` in Chrome and use the Memory panel to take two heap snapshots a few minutes apart. Objects whose count only ever goes up between snapshots point at the leak.

## Check the Mac as a whole

```bash
memory_pressure | tail -1
top -l 1 -o mem -n 5 -stats pid,command,mem,cpu
```

The first prints a line like `System-wide memory free percentage: 39%`; the second lists the five processes using the most memory. `top` shows a Next.js server as plain `node`, so match it by PID. Activity Monitor’s Memory tab graphs memory pressure over time, which tells you whether the Mac is actually struggling or just using its RAM. If macOS has already shown its “Your system has run out of application memory” dialog, pressure was high for a while; stopping idle servers is the fastest relief.

## How Porto helps

Porto measures memory and CPU across each server’s whole process tree and keeps ten minutes of that history for every server. Once a server passes 2 GB (the default threshold, which you can change) or grows by more than 500 MB within ten minutes, it turns amber in the list and in the menu bar, and a single notification offers Details, Stop and Snooze. A memory bar shows how your Mac’s RAM splits between dev servers, other apps and free memory, and Clean up gathers the idle servers worth stopping. Porto never stops a leaking server automatically; that decision stays with you.

[Download Porto](/Porto.dmg), and if coding agents launch servers on your behalf, read [Claude Code left a dev server running?](/guides/claude-code-dev-server-left-running)
