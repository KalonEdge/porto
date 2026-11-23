import { DEMO_HOST, SITE_NAME } from '@/lib/site'
import { type AppLanguage, LANGUAGES, languageLabel } from '@/lib/i18n'
import { SERVERS, formatMemory } from '@/lib/demo'

// A pretend zsh that only really knows `porto`. Everything else gets a short,
// honest answer: this is a web page, not your Mac.

export const PROMPT = `visitor@${DEMO_HOST} ~ %`
export const VERSION = 'porto 1.0'

export type Output = { text: string; tone?: 'dim' }
export type Reply = { lines: Output[]; action?: 'porto' | 'clear' | 'exit'; language?: AppLanguage }

const FILES = 'README.md  Terminal.tsx  Porto.dmg  landing.module.css  demo.ts'
const JOKE = 'This is a web page dressed as a terminal. Type porto, or download the real thing.'
const CODES = `system, ${LANGUAGES.map((language) => language.code).join(', ')}`

const say = (...lines: (string | Output)[]): Reply => ({
  lines: lines.map((line) => (typeof line === 'string' ? { text: line } : line)),
})
const dim = (text: string): Output => ({ text, tone: 'dim' })

function table(ports: string[]): Output[] {
  const servers = SERVERS.filter((server) => ports.includes(server.port))
  if (!servers.length) return [{ text: 'Nothing listening on ports 3000–65535.' }]
  const header = ['PORT', 'NAME', 'BRANCH', 'MEMORY']
  const rows = servers.map((s) => [`:${s.port}`, s.name, s.branch, formatMemory(s.memory)])
  const widths = header.map((_, column) => Math.max(...[header, ...rows].map((row) => row[column].length)))
  const format = (row: string[]) => row.map((cell, i) => (i === 3 ? cell.padStart(widths[i]) : cell.padEnd(widths[i]))).join('  ')
  return [dim(format(header)), ...rows.map((row) => ({ text: format(row) }))]
}

export function reply(input: string, ports: string[], language: AppLanguage): Reply {
  const command = input.trim()
  const [name, ...args] = command.split(/\s+/)
  const argument = args.join(' ')
  if (!command) return { lines: [] }

  if (name === 'porto') {
    if (args[0] === 'language') {
      const code = args[1] ?? language
      if (args.length > 2 || (code !== 'system' && !LANGUAGES.some((item) => item.code === code))) {
        return say(`porto: language must be one of ${CODES}`)
      }
      const selected = code as AppLanguage
      return { ...say(`App language: ${selected} (${languageLabel(selected)})`), language: selected }
    }
    if (!args.length) return { lines: [], action: 'porto' }
    if (/^(list|ls)$/.test(argument)) return { lines: table(ports) }
    if (/^(list|ls) --json$/.test(argument)) {
      const servers = SERVERS.filter((s) => ports.includes(s.port)).map((s) => ({
        port: Number(s.port),
        name: s.name,
        branch: s.branch,
        memoryBytes: s.memory * 1_048_576,
      }))
      return { lines: JSON.stringify(servers, null, 2).split('\n').map((text) => ({ text })) }
    }
    if (/^(-v|--version|version)$/.test(argument)) return say(VERSION)
    if (/^(-h|--help|help)$/.test(argument)) {
      return say(
        'Every dev server on your Mac, in the terminal.',
        '',
        'Usage:',
        '  porto               Browse, open and stop servers',
        '  porto list          Print servers and exit',
        '  porto list --json   Print servers as JSON',
        '  porto language      Show the macOS app language',
        '  porto language de   Set the app language',
        `  Codes: ${CODES}`,
        'The terminal interface and JSON remain English.',
      )
    }
    return say(`porto: unknown command ‘${args[0]}’`, dim('Try porto --help.'))
  }

  switch (name) {
    case 'clear':
      return { lines: [], action: 'clear' }
    case 'exit':
    case 'logout':
      return { lines: [], action: 'exit' }
    case 'ls':
      return say(FILES, dim('Those are this web page’s files. Yours are safe on your Mac.'))
    case 'pwd':
      return say(`/Users/visitor/${DEMO_HOST}`)
    case 'whoami':
      return say('visitor')
    case 'echo':
      return say(argument)
    case 'date':
      return say(new Date().toString().replace(/ GMT.*$/, ''))
    case 'cd':
      return argument && argument !== '~'
        ? say(`cd: no such file or directory: ${argument}`, dim('There are no folders here, only divs.'))
        : { lines: [] }
    case 'sudo':
      return say('[sudo] password for visitor:', 'Sorry, try again.', dim('No root here. This terminal is made of HTML.'))
    case 'rm':
      return say(
        `rm: ${argument || 'missing operand'}: Operation not permitted`,
        dim('Nothing on this page can be deleted. Not even by you.'),
      )
    case 'npm':
    case 'pnpm':
    case 'yarn':
    case 'bun':
    case 'npx':
    case 'next':
    case 'vite':
    case 'node':
      return say(`${name}: can’t start anything from inside a web page.`, dim(`Start it in a real terminal and ${SITE_NAME} will find it.`))
    case 'git':
      return say('fatal: not a git repository (or any of the parent directories): .git')
    case 'lsof':
    case 'ps':
    case 'kill':
    case 'killall':
    case 'top':
    case 'htop':
      return say(`${name}: a browser tab can’t see your processes.`, dim(`That’s what ${SITE_NAME} is for.`))
    case 'brew':
      return say('Error: Homebrew doesn’t live in web pages.', dim(`Download ${SITE_NAME} from this page instead.`))
    case 'claude':
    case 'codex':
      return say(`${name}: needs a real terminal. This one is a <div>.`)
    case 'vim':
    case 'vi':
    case 'nano':
    case 'emacs':
      return say(`${name}: not here. You’d never find the way out of a web page anyway.`)
    case 'help':
      return say(dim(JOKE))
    default:
      return say(`zsh: command not found: ${name}`, dim(JOKE))
  }
}

/** Word-wraps a line into rows; `first` is the room left on the first row after a prompt. */
export function wrap(text: string, width: number, first = width): string[] {
  const rows: string[] = []
  let row = ''
  let room = first
  for (const word of text.split(' ')) {
    const next = row ? `${row} ${word}` : word
    if (next.length <= room) {
      row = next
      continue
    }
    if (row) rows.push(row)
    room = width
    let rest = word
    // Words longer than a row break wherever the row ends.
    while (rest.length > room) {
      rows.push(rest.slice(0, room))
      rest = rest.slice(room)
    }
    row = rest
  }
  rows.push(row)
  return rows
}

export const lastLogin = (tty: string) => `Last login: ${new Date().toString().slice(0, 24)} on ${tty}`
