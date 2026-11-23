# Porto

> Porto is a free, open-source menu bar app for macOS that shows every local dev server running on your Mac, with its port, project, git branch, uptime, memory and CPU. It links servers to the Claude Code or Codex session (or Conductor workspace) that started them, warns you when one starts using too much memory, and helps you stop the ones you’ve forgotten. It’s a native Swift app: no Electron, no Dock icon, no account.

- [Download Porto](/Porto.dmg) (macOS 14 Sonoma or later, Apple Silicon)
- [Guides](/guides)
- GitHub (link coming soon)

## What it does

- **Every dev server in one list.** Porto lives in the menu bar as a small dot-grid “porthole” icon, a ring of dots with a lit centre, and can show the number of running servers beside it. Click the icon or press ⌃⌥⌘P to open the list. Each server shows its port, project name, git branch, uptime, memory and CPU, and keeps a stable colour for its port. A memory bar shows the whole Mac’s RAM split between dev servers, other apps and free memory.
- **Agent sessions.** Servers started by Claude Code are linked to their session, with the session title. Codex sessions are matched by working directory, and servers started in Conductor show their workspace name. Porto can resume a session in your terminal of choice (`claude --resume <id>`, `codex resume <id>`).
- **Memory alerts.** A server that passes 2 GB (adjustable) or grows by more than 500 MB within ten minutes turns amber in the list and in the menu bar, and a single notification offers Details, Stop and Snooze. Porto keeps ten minutes of memory and CPU history per server, summed across its process tree.
- **Clean up.** Porto preselects servers from deleted git worktrees and servers that have been idle for 4 hours (no CPU and no open connections), and suggests servers that have been running for more than 3 days. Tick the ones to go and Porto stops each whole process tree. Postgres, Redis, MongoDB and MySQL are protected by default. Clean up can be Off, Ask (the default) or Automatic, and a leaking server is never stopped automatically.
- **Stop and restart.** Stop sends SIGTERM to the server’s whole process tree, then SIGKILL after 3 seconds (configurable). Restart reruns the original command in the same folder and writes its output to `~/Library/Logs/Porto/port-<port>.log`.
- **Pull requests and previews (optional).** Off by default: Porto can show the branch’s pull request and a Vercel preview button, using the GitHub CLI (`gh`) you’re already signed in to.
- **Right-click menu.** Right-click the menu bar icon for Open in Browser, Settings…, Check for Updates…, Send Feedback and Quit.
- **Eight languages.** English, German, French, Spanish, Simplified Chinese, Hebrew (right to left), Japanese and Ukrainian. See [Change Porto’s language](/guides/change-app-language).

## Install

1. Download [Porto.dmg](/Porto.dmg), open it and move Porto to your Applications folder.
2. Open Porto. It appears in the menu bar, not in the Dock.
3. Onboarding starts with a language choice and offers to install the `porto` command for the terminal.

Requirements: macOS 14 Sonoma or later. The prebuilt download is for Apple Silicon. To build from source you need Swift 5.9 or later. Porto is free and open source under the MIT license, and it needs no account.

## The porto command

`porto` gives you the same server list in the terminal. Install it from onboarding, or later from Settings → General → Terminal; either links `/usr/local/bin/porto` to the app’s executable. To create the link by hand:

```bash
sudo ln -sf /Applications/Porto.app/Contents/MacOS/Porto /usr/local/bin/porto
```

| Command | What it does |
| --- | --- |
| `porto` | Opens the terminal UI: the server list, server details and Clean up |
| `porto list` | Prints a table of running dev servers |
| `porto list --json` | Prints the same list as JSON |
| `porto language` | Shows the Mac app’s language |
| `porto language ja` | Sets the Mac app’s language (`en`, `de`, `fr`, `es`, `zh-Hans`, `he`, `ja`, `uk` or `system`) |
| `porto --version` | Prints the version |

Each server in `porto list --json` has these fields: `port`, `url`, `pid`, `name`, `branch`, `framework`, `folder`, `command`, `startedAt`, `memoryBytes`, `cpuPercent`, `status` (`running`, `attention` or `idle`), `protected`, `processes` and `session` (with `kind`, `id` and `title`). Coding agents can call it to see what’s already running before they start another server.

The terminal UI, the command help and the JSON output stay in English whatever language the app uses, so scripts keep working.

## How it works

- **Finding servers.** Porto reads listening TCP sockets with `lsof` and rescans every 2 seconds (configurable).
- **What it watches.** By default, ports 3000 to 65535 and dev-server-like processes: node, bun, deno, python and python3 (including versioned names such as python3.12), uvicorn, gunicorn, ruby, rails, puma, php, java, go, cargo, dotnet, elixir and beam, nginx, postgres, redis-server, mongod, mysql and similar. Both lists are configurable in Settings → Ports & processes.
- **Understanding each server.** For every server Porto inspects the whole process tree through libproc and sysctl: memory footprint, CPU time, working directory, arguments and environment. From the working directory it finds the project manifest (package.json, pyproject.toml, Cargo.toml, go.mod or Gemfile), the framework and the git branch.
- **Linking agent sessions.** Commands run by Claude Code inherit a `CLAUDE_CODE_SESSION_ID` environment variable, which Porto reads from the server’s environment; the session title comes from the transcripts in `~/.claude/projects`. Codex sessions are matched by working directory using `~/.codex/sessions`. Conductor’s workspace name comes from `CONDUCTOR_WORKSPACE_NAME`.
- **Idle and leaking.** A server counts as idle when it uses no CPU and has no open connections; the default idle threshold for Clean up is 4 hours. Memory alerts compare each server’s summed footprint with the threshold and with its own last ten minutes.

## Privacy

Porto has no account and no analytics SDK. Everything it learns about your processes, projects and agent sessions stays on your Mac. It uses the network for three things only:

- checking for updates;
- an optional, anonymous once-a-day count of which features were used (feature names only), which you can turn off in Settings → General → Privacy;
- the optional pull request and Vercel preview lookups through `gh`, which are off by default.

## FAQ

### Is Porto free?

Yes. Porto is free and open source under the MIT license, and it doesn’t ask for an account.

### Which Macs does it run on?

Porto needs macOS 14 Sonoma or later. The prebuilt download is for Apple Silicon Macs. You can also build it from source with Swift 5.9 or later.

### Why doesn’t my server appear?

By default Porto watches ports 3000 to 65535 and a list of common dev-server processes. A server on a lower port, or one running under a process name that isn’t on the list, won’t appear until you add it in Settings → Ports & processes. Porto looks for listening TCP sockets, so a process that isn’t listening yet won’t show up either.

### What happens when I press Stop?

Porto sends SIGTERM to every process in the server’s tree, which gives the server a chance to shut down cleanly. Anything still running 3 seconds later receives SIGKILL. The delay is configurable.

### Will Clean up stop my database?

Not by default. Postgres, Redis, MongoDB and MySQL (the processes `postgres`, `redis-server`, `mongod`, `mysqld` and `mysql`) are protected. Clean up also runs in Ask mode unless you change it, so nothing is stopped until you confirm.

### Can Porto stop idle servers automatically?

Yes, if you set Clean up to Automatic. It can also be Off, or Ask, the default. Servers flagged for leaking memory are never stopped automatically; Porto notifies you instead.

### How does Porto know which agent started a server?

Claude Code puts its session ID in the environment of every command it runs, and servers inherit it. Porto reads that variable, then finds the session’s title in `~/.claude/projects`. For Codex, Porto matches the server’s working directory against the session logs in `~/.codex/sessions`. For Conductor, it reads the `CONDUCTOR_WORKSPACE_NAME` variable. All of this happens locally.

### Does Porto send anything off my Mac?

Only update checks, the optional anonymous daily feature count, and the optional `gh` lookups if you turn them on. No process names, paths, ports or session details leave your Mac.

### Can I use Porto from scripts or coding agents?

Yes. `porto list` prints a table, and `porto list --json` prints structured data with each server’s port, URL, folder, branch, status and session. The output stays in English regardless of the app’s language.

### How do I change the language?

Choose it on the first onboarding screen, in Settings → General → Language, or with `porto language <code>` in the terminal. Changes apply immediately. See [Change Porto’s language](/guides/change-app-language).

### Where can I learn more about managing dev servers?

The [guides](/guides) cover common problems, from [port 3000 already in use](/guides/port-3000-already-in-use-mac) to [servers left running by coding agents](/guides/claude-code-dev-server-left-running) and [dev server memory leaks](/guides/dev-server-memory-leak-mac).
