---
title: How to manage localhost ports on a Mac, from lsof to menu bar apps
description: A practical comparison of the ways to see and stop local dev servers on macOS, from lsof and Activity Monitor to npm helpers, launcher extensions and menu bar apps, and which fits which way of working.
published: 2026-09-29
updated: 2026-09-29
order: 9
keywords: localhost port manager mac, dev server manager mac, kill port app mac, menu bar app localhost ports, lsof alternative mac, see running servers mac, port monitor macos
---

Every way of managing local servers on a Mac makes the same trade: how much it tells you against how much effort it takes to ask. A one-off `lsof` costs nothing and answers one question. An always-on app costs a little memory and keeps answering all of them. The right balance comes down to two things: the number of servers you juggle, and whether you start them all yourself. One disclosure first: Porto is ours. Where we compare it with other tools, we stick to behaviour you can check on your own Mac.

## The options

- **Built-in commands:** `lsof`, `ps`, `kill` and `netstat`, in any terminal.
- **Activity Monitor:** the graphical process list that ships with macOS.
- **Package helpers:** small npm tools such as kill-port and fkill-cli, plus `brew services` for databases installed with Homebrew.
- **Launcher extensions:** community extensions and workflows for Raycast and Alfred.
- **Container dashboards:** Docker Desktop and OrbStack, for servers that run inside containers.
- **Menu bar apps:** always-visible lists of local servers, Porto among them.

The rest of this guide looks at them through five questions that decide whether a tool actually helps.

## Can it show everything at once?

`lsof -nP -iTCP -sTCP:LISTEN` lists every listening socket in one go, but without `sudo` only for processes you own; `netstat -anv -p tcp | grep LISTEN` adds root’s and other users’ listeners, with a `process:pid` column. Activity Monitor can’t list servers by port: its optional Ports column counts Mach ports, not network ports, so you have to open each process and look at its Open Files and Ports tab. Package helpers are mostly built around stopping a process you name or pick, and many launcher extensions work the same way, which makes them good at answering “what’s on 3000?” and less helpful for “what’s running at all?”. A menu bar app is built for the second question. Porto rescans every 2 seconds and can show the number of running servers right next to its icon.

## Can it tell you which project a server belongs to?

Almost every listener is called `node` or `python3`, so the name alone identifies nothing. The folder does: `lsof -a -p 48213 -d cwd` prints a process’s working directory, and [a short shell function](/guides/see-every-dev-server-running-on-mac) does the same for every server at once. Activity Monitor’s list has no column for it. Porto shows each server’s project name and git branch, working them out from the project’s manifest (package.json, pyproject.toml, Cargo.toml, go.mod or Gemfile) and its repository.

## Does it measure the whole server?

Dev servers are often several processes. In our measurements, `next dev` in Next.js 16 ran as the `next dev` command plus a `next-server` child that held most of the memory, and Vite ran alongside an `esbuild` service process. Activity Monitor and `top` show those as separate rows; `ps` and `footprint` can total them with a little scripting, as the [memory guide](/guides/dev-server-memory-leak-mac) shows. Porto sums memory and CPU across each server’s whole process tree, keeps ten minutes of history, and turns a server amber when it passes 2 GB or grows by more than 500 MB within ten minutes.

## Can it stop a server without collateral damage?

Three things go wrong when stopping servers by hand, and they’re worth checking in any tool:

- **Stopping one process instead of the server.** Kill a parent and its child can keep the port as an orphan. By hand, signal the process group (`kill -- -48170`); Activity Monitor quits one process at a time.
- **Hitting clients.** `lsof -ti :3000` without `-sTCP:LISTEN` also returns processes merely connected to the port, such as a browser. Check what a helper tool matches before wiring it into a script, and whether it signals politely or force-kills.
- **Fighting launchd.** Databases started with `brew services` are launchd agents, often set to restart when they exit. `brew services stop` is the right control for those.

Porto’s Stop sends SIGTERM to the server’s whole process tree and SIGKILL after 3 seconds if anything is left. Its Clean up view protects Postgres, Redis, MongoDB and MySQL by default.

## Does it understand servers started by agents?

More and more servers are started by coding agents in background shells, which is exactly where leftovers come from. By hand, you can read `CLAUDE_CODE_SESSION_ID` from a process’s environment with `ps -E`, or match Codex session logs by folder; [the agent guide](/guides/claude-code-dev-server-left-running) shows both. General-purpose tools don’t attempt this. Porto links servers to their Claude Code or Codex session and shows Conductor workspace names, can resume a session in your terminal of choice, and its Clean up view preselects idle servers and servers from deleted git worktrees.

## Containers are a separate case

Docker Desktop and OrbStack show your containers and their published ports, and they remain the right place to stop containers. They don’t see servers running directly on macOS, which is where the servers in this guide run.

## Side by side

| | lsof, ps, kill | Activity Monitor | Porto |
| --- | --- | --- | --- |
| Lists every listening server | Yes, on demand | No | Yes, always visible |
| Project folder and branch | By hand | No | Yes |
| Memory per server | By hand, per process | Per process | Summed across the process tree |
| Stops the whole server | By hand, via the process group | No | Yes |
| Agent sessions | By hand, via the environment | No | Claude Code and Codex sessions, Conductor workspaces |
| Cost | Built in | Built in | Free, open source (MIT) |

## Picking one

- **The odd port clash in a single project:** the built-in commands are all you need. [Port 3000 already in use](/guides/port-3000-already-in-use-mac) has the recipe.
- **Scripts and automation:** `lsof` is always there; if Porto is installed, `porto list --json` gives you project, branch and session data as structured JSON.
- **Keyboard-driven, on-demand checks:** a launcher extension.
- **Many projects in flight, parallel worktrees or several agents:** an always-visible menu bar app earns its place, because the problem is no longer one port but a dozen servers you didn’t all start yourself.

Porto is a native Swift app with no Dock icon and no account, and it’s free. It needs macOS 14 or later, and the prebuilt download is for Apple Silicon. [Download Porto](/Porto.dmg).
