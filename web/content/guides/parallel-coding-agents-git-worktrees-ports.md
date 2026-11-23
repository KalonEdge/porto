---
title: Parallel coding agents in git worktrees, without the port collisions
description: Running several Claude Code, Codex or Conductor agents in separate git worktrees? Give each worktree a stable port of its own, make collisions fail loudly, and clean up servers left behind by deleted worktrees.
published: 2026-09-29
updated: 2026-09-29
order: 5
keywords: git worktree dev server port, parallel claude code agents ports, multiple worktrees port conflict, conductor workspace dev server, codex parallel agents ports, git worktree remove process still running, one port per worktree
---

Give three agents three branches and you’ll usually give them three git worktrees, so their edits never touch. Their dev servers are another matter. Every worktree of a project runs the same `npm run dev`, they all share one network stack, and port 3000 can only belong to one of them at a time. The others drift to 3001 and 3002, you lose track of which tab shows which branch, and servers keep running long after the worktree that started them has been deleted.

## A thirty-second refresher

```bash
git worktree add ../shop-login -b feature/login
git worktree list
git worktree remove ../shop-login
```

```text
/Users/alex/code/shop          7d292ec [main]
/Users/alex/code/shop-billing  a41c0e9 [feature/billing]
/Users/alex/code/shop-login    7d292ec [feature/login]
```

Each worktree is a separate folder, which matters later: a running dev server is tied to the folder it started in, not to the branch.

## Derive the port from the folder

Assigning ports to branches by hand doesn’t survive a busy week. A rule that needs no bookkeeping is to compute the port from the worktree’s path. The same folder always gets the same port, and different folders almost always get different ones:

```bash
export PORT=$(( 3100 + $(printf '%s' "$PWD" | cksum | cut -d' ' -f1) % 800 ))
```

That hashes the current path with `cksum` and maps it into the range 3100 to 3899. Wrap it in a small script so people and agents start servers the same way:

```sh
#!/bin/sh
# One port per worktree: the same folder always gets the same port (3100-3899).
: "${PORT:=$(( 3100 + $(printf '%s' "$PWD" | cksum | cut -d' ' -f1) % 800 ))}"
export PORT
echo "$(git branch --show-current) -> http://localhost:$PORT"
exec npm run dev
```

Save it as `scripts/dev.sh`, make it executable with `chmod +x scripts/dev.sh`, and start the server with `./scripts/dev.sh`. A `PORT` you set yourself still wins, and the first line of output says which branch is on which URL:

```text
feature/search -> http://localhost:3579
```

Two worktrees can still hash to the same port. With a handful of worktrees it’s unlikely, and the next section makes it harmless.

### Write the rule down for agents

Agents read project instructions, `CLAUDE.md` for Claude Code and `AGENTS.md` for Codex and others, and every worktree shares them. A short section is enough:

```markdown
## Running the app
- Start it with ./scripts/dev.sh. The first line of output is this worktree's URL.
- Don't pass --port and don't set PORT yourself.
- If it fails because the port is busy, run
  lsof -nP -iTCP:<port> -sTCP:LISTEN and tell me what is using it.
- Stop the server before you finish.
```

Because the port comes from the folder, one identical instruction gives every worktree a different port, and no agent has to guess which `localhost` tab belongs to it.

## Make the framework respect it

A port only helps if the dev server uses it and refuses to fall back to another one:

- **Next.js** reads `PORT`. When the port is set explicitly, a busy port stops the server instead of moving it to the next number.
- **Vite** doesn’t read `PORT` by itself. Tell it to in `vite.config.js`, and turn on `strictPort`:

```js
import { defineConfig } from 'vite'

export default defineConfig({
  server: {
    port: Number(process.env.PORT) || 5173,
    strictPort: true,
  },
})
```

- **Flask** reads `FLASK_RUN_PORT`, and **uvicorn** takes `--port`. Neither moves to another port on its own; they stop with an error instead.

With this in place, a second Vite server in the same worktree stops with `Error: Port 3579 is already in use` rather than quietly starting somewhere else. [Vite on 5174, Next.js on 3001](/guides/vite-port-5174-nextjs-port-3001) covers both frameworks in more detail.

## Servers outlive their worktrees

`git worktree remove` checks for uncommitted changes, not for running processes. In our test it removed a worktree while a Node server was running inside it. The server carried on listening, and `lsof` still reported the deleted folder as its working directory, with no sign that the folder was gone. This loop finds servers in that state:

```bash
for pid in $(lsof -tiTCP -sTCP:LISTEN | sort -un); do
  dir=$(lsof -a -p "$pid" -d cwd -Fn | sed -n 's/^n//p')
  [ -d "$dir" ] || echo "$pid is still running from a deleted folder: $dir"
done
```

Stop anything it reports before you forget which branch it belonged to. Two smaller leftovers:

- The branch survives `git worktree remove`. Delete it with `git branch -D feature/login` once you’re done with it.
- A worktree folder deleted with `rm -rf` instead of `git worktree remove` shows up as `prunable` in `git worktree list` until you run `git worktree prune`.

## Five worktrees, five servers

Parallel agents multiply memory use as well as ports. A Next.js 16 dev server for a one-page test app used about 390 MB in our measurements; real projects use a lot more, and on a 16 GB Mac a handful of them adds up quickly. [Dev server memory on a Mac](/guides/dev-server-memory-leak-mac) shows how to measure a server’s whole process tree.

## How Porto helps

Porto shows each server’s git branch alongside its port, and the workspace name for servers started by Conductor, so parallel worktrees are easy to tell apart. Servers started by Claude Code or Codex are linked to their sessions. When a worktree is deleted, Clean up preselects the server it left behind; tick it and Porto stops the whole process tree. The memory bar shows how much of your Mac’s RAM all those servers are using compared with everything else. [Download Porto](/Porto.dmg), and see [what to do about servers agents leave running](/guides/claude-code-dev-server-left-running).
