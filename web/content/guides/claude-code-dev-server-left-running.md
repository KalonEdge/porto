---
title: Claude Code left a dev server running? Find it and trace it to its session
description: Coding agents start dev servers in background shells and often leave them running. How to find agent-started servers on a Mac, link each one to its Claude Code or Codex session, and stop the duplicates.
published: 2026-09-29
updated: 2026-09-29
order: 4
keywords: claude code dev server still running, claude code background process port, claude code port already in use, codex dev server left running, CLAUDE_CODE_SESSION_ID, agent started dev server mac, orphaned dev server mac
---

Ask an agent to check a change in the browser and it has to get the app running first. Claude Code and Codex often do that in a background shell, so the conversation isn’t blocked while `npm run dev` runs. Nothing in that arrangement guarantees the server stops when the conversation ends. A week of agent sessions can leave half a dozen servers behind, each holding a port and memory, and a new session that doesn’t know about them may start yet another copy of the same app on the next free port.

## Why a server outlives the session

A dev server is an ordinary process, and whether it stops with the session depends on how it was launched and how the session ended. If the shell that started it exits first, macOS doesn’t take the child down with it. The orphan is adopted by launchd (PID 1) and keeps listening. We checked this directly: stopping the shell that had launched a Node server left the server running with a parent PID of 1 and its port still bound.

That gives leftovers a recognisable signature: a parent PID of 1, a working directory inside a project, and an uptime measured in hours or days.

## Find the likely leftovers

```bash
ps -o pid,ppid,etime,command -p "$(lsof -tiTCP -sTCP:LISTEN | sort -un | paste -sd, -)"
```

This prints every listening process with its parent and age. Desktop apps also have a parent PID of 1, so treat it as a hint and confirm with the working directory (`lsof -a -p 48213 -d cwd`, using the PID in question). To see whether anything is still talking to a server:

```bash
lsof -nP -iTCP:3000 -sTCP:ESTABLISHED
```

No output means no client is connected right now. A server with no connections, no CPU use and a two-day uptime is rarely one you still need.

## Trace a server back to its session

### Claude Code

Claude Code sets `CLAUDE_CODE_SESSION_ID` in the environment of the commands it runs, and processes inherit their parent’s environment, so a server started by Claude Code carries the ID of its session. On macOS, `ps -E` prints a process’s environment along with its command line (for processes you own):

```bash
ps -E -o command= -p 48213 | grep -o 'CLAUDE_CODE_SESSION_ID=[^ ]*'
```

```text
CLAUDE_CODE_SESSION_ID=0f3c9a52-7d1e-4b8a-9c6f-2e5d8b1a4c70
```

Claude Code keeps each session’s transcript under `~/.claude/projects`, in a folder named after the project path with slashes turned into dashes, in a file named after the session ID:

```bash
ls ~/.claude/projects/*/0f3c9a52-7d1e-4b8a-9c6f-2e5d8b1a4c70.jsonl
```

To pick the conversation up again, run this from the project’s folder, then ask the agent to shut down what it started:

```bash
claude --resume 0f3c9a52-7d1e-4b8a-9c6f-2e5d8b1a4c70
```

### Codex

Codex writes a log for each session under `~/.codex/sessions/<year>/<month>/<day>/`, and each log records the working directory the session ran in. To find recent sessions for a project folder:

```bash
grep -rl "\"cwd\":\"$HOME/code/shop\"" ~/.codex/sessions | tail -3
```

The file names end with the session ID, which `codex resume <id>` accepts. Matching by folder is approximate when several sessions ran in the same project, so check the dates in the path.

### Conductor

Conductor sets `CONDUCTOR_WORKSPACE_NAME` for the processes it runs in a workspace, so the same `ps -E` trick tells you which workspace a server belongs to:

```bash
ps -E -o command= -p 48213 | grep -o 'CONDUCTOR_WORKSPACE_NAME=[^ ]*'
```

## Shut down the abandoned ones

Once you know a server is abandoned, stop its whole process group so no child lingers on the port; [the port 3000 guide](/guides/port-3000-already-in-use-mac) walks through `kill` and process groups. If the session is still active, it’s cleaner to ask the agent to stop the server itself. Otherwise it may start it again on its next turn.

## Keep agents from starting a second copy

Agents follow project instructions. Claude Code reads `CLAUDE.md`, and Codex and many other agents read `AGENTS.md`. A few lines there prevent most duplicates:

```markdown
## Running the app
- This repo's dev server runs on port 3100: `PORT=3100 npm run dev`.
- Before starting it, check whether it's already running:
  `lsof -nP -iTCP:3100 -sTCP:LISTEN`. If it is, use that one.
- Never start a second copy on another port. If 3100 is taken by
  something else, stop and tell me what it is.
- Stop any server you started before you finish the task.
```

Adjust the command to however your framework takes a port. Then make sure the server refuses to drift, so a duplicate fails loudly instead of landing on 3101; [Vite on 5174, Next.js on 3001](/guides/vite-port-5174-nextjs-port-3001) shows how for both frameworks. If you run several agents at once in git worktrees, each one needs a port of its own: see [parallel coding agents in git worktrees](/guides/parallel-coding-agents-git-worktrees-ports).

## How Porto helps

Porto does this tracing for every server, all the time. Servers started by Claude Code are linked to their session through `CLAUDE_CODE_SESSION_ID`, with the session’s title read from the transcripts in `~/.claude/projects`. Codex sessions are matched by working directory from `~/.codex/sessions`, and servers started in Conductor show their workspace name. Porto can resume a session in your terminal of choice with `claude --resume <id>` or `codex resume <id>`.

Clean up preselects the servers that look abandoned: those from deleted git worktrees and those idle for 4 hours (no CPU and no open connections), and it also suggests any that have run for more than 3 days. Tick the ones to go and Porto stops each whole process tree. Postgres, Redis, MongoDB and MySQL are protected by default. It’s useful to agents as well: `porto list --json` includes each server’s folder, URL, branch and session, so an agent can check what’s already running before it starts anything. [Download Porto](/Porto.dmg).
