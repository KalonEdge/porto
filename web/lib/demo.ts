import type { Translator } from './i18n'

// Sample servers for the marketing demo. Presentation follows the native
// SwiftUI views; memory uses binary MB like the app's Format helpers.

export type Agent = 'claude' | 'codex'
export type Status = 'on' | 'amber' | 'idle'
export type CleanUpReason = 'deleted' | 'idle' | 'leaking'

export type Server = {
  port: string
  name: string
  branch: string
  status: Status
  memory: number // binary MB
  cpu: number // % of one core
  uptime: string
  context: { agent?: Agent; text: string; tone?: 'amber' }
  /** Localized row and header copy, in the language the demo is showing. */
  lines: (l: Translator) => { context: string; note?: string; running: string }
  session?: { agent: Agent; title: string; id: string }
  chart: 'steady' | 'leaking' | 'flat'
  spark: string
  processes: { command: string; memory: number }[]
  info: [label: string, value: string][]
  cleanUp?: { reason: CleanUpReason; note: string; suggested: boolean }
}

export const SERVERS: Server[] = [
  {
    port: '3000',
    name: 'porto',
    branch: 'menubar-port-monitor',
    status: 'on',
    memory: 1240,
    cpu: 12,
    uptime: 'up 3h 12m',
    context: { agent: 'claude', text: 'porto · up 3h' },
    lines: (l) => ({ context: `porto · ${l.format('up %@', l.duration(180, true))}`, running: l.duration(192) }),
    session: { agent: 'claude', title: 'Porthole menu bar icon', id: '4f2e9b1c' },
    chart: 'steady',
    spark: 'M0 13 L4 12 L8 12.5 L12 10 L16 11 L20 8 L24 9 L28 7 L32 8 L36 6 L40 6.5 L44 5',
    processes: [
      { command: 'node next dev', memory: 796 },
      { command: 'next-server', memory: 418 },
      { command: 'tailwindcss --watch', memory: 26 },
    ],
    info: [
      ['Folder', '~/conductor/workspaces/porto/providence'],
      ['Framework', 'Next.js 14'],
      ['Command', 'npm run dev'],
      ['PID', '48213'],
      ['Started', 'Today 10:12 AM'],
      ['Workspace', 'providence'],
    ],
  },
  {
    port: '3001',
    name: 'field-notes',
    branch: 'main',
    status: 'on',
    memory: 612,
    cpu: 2,
    uptime: 'up 1d 4h',
    context: { text: 'field notes · up 1d' },
    lines: (l) => ({ context: `field notes · ${l.format('up %@', l.duration(1680, true))}`, running: l.duration(1680) }),
    chart: 'steady',
    spark: 'M0 10 L4 10.5 L8 9.5 L12 10 L16 9 L20 10 L24 9.5 L28 10 L32 9 L36 9.5 L40 9 L44 9.5',
    processes: [
      { command: 'astro dev', memory: 571 },
      { command: 'esbuild', memory: 41 },
    ],
    info: [
      ['Folder', '~/Sites/field-notes'],
      ['Framework', 'Astro 4'],
      ['Command', 'npm run dev -- --port 3001'],
      ['PID', '30412'],
      ['Started', 'Yesterday 9:02 AM'],
      ['Git', 'clean'],
    ],
  },
  {
    port: '5173',
    name: 'paper-plugins',
    branch: 'feat/export-svg',
    status: 'on',
    memory: 184,
    cpu: 0,
    uptime: 'idle 5h',
    context: { agent: 'codex', text: 'paper plugins · idle 5h' },
    lines: (l) => ({
      context: `paper plugins · ${l.format('idle %@', l.duration(300, true))}`,
      note: l.format('Idle %@ · no connections', l.duration(300, true)),
      running: l.duration(300),
    }),
    session: { agent: 'codex', title: 'SVG export for frames', id: 'b83d0a57' },
    chart: 'flat',
    spark: 'M0 13 L4 13 L8 12.5 L12 13 L16 13 L20 13 L24 12.5 L28 13 L32 13 L36 13 L40 13 L44 13',
    processes: [
      { command: 'vite', memory: 142 },
      { command: 'esbuild', memory: 42 },
    ],
    info: [
      ['Folder', '~/conductor/workspaces/paper-plugins/lisbon'],
      ['Framework', 'Vite 5'],
      ['Command', 'pnpm dev'],
      ['PID', '51092'],
      ['Started', 'Today 7:58 AM'],
      ['Workspace', 'lisbon'],
    ],
    cleanUp: { reason: 'idle', note: 'Idle 5h · no connections', suggested: true },
  },
  {
    port: '6006',
    name: 'design-system',
    branch: 'tokens-v2',
    status: 'amber',
    memory: 2810,
    cpu: 34,
    uptime: 'up 2h 40m',
    context: { text: '+1.1 GB in 10 min', tone: 'amber' },
    lines: (l) => ({
      context: l.format('+%@ in %@', '1.1 GB', l.text('10 min')),
      note: l.format('Leaking · +%@', '1.1 GB'),
      running: l.duration(160),
    }),
    session: { agent: 'claude', title: 'Tokens v2 migration', id: 'e6a1c92f' },
    chart: 'leaking',
    spark: 'M0 16 L4 15.5 L8 14.5 L12 14 L16 12.5 L20 12 L24 10 L28 9 L32 7 L36 5.5 L40 4 L44 2',
    processes: [
      { command: 'storybook dev -p 6006', memory: 2210 },
      { command: 'webpack', memory: 548 },
      { command: 'node', memory: 52 },
    ],
    info: [
      ['Folder', '~/Code/design-system'],
      ['Framework', 'Storybook 8'],
      ['Command', 'npm run storybook'],
      ['PID', '61540'],
      ['Started', 'Today 10:44 AM'],
      ['Git', '3 changed files'],
    ],
    cleanUp: { reason: 'leaking', note: 'Leaking · +1.1 GB in 10 min', suggested: false },
  },
  {
    port: '8000',
    name: 'api',
    branch: 'fix/auth-timeout',
    status: 'idle',
    memory: 96,
    cpu: 0,
    uptime: 'idle 2d',
    context: { text: 'Worktree deleted · idle 2d' },
    lines: (l) => ({
      context: l.format('Worktree deleted · idle %@', l.duration(2880, true)),
      note: l.text('Worktree deleted'),
      running: l.duration(2880),
    }),
    chart: 'flat',
    spark: 'M0 12 L44 12',
    processes: [{ command: 'uvicorn main:app', memory: 96 }],
    info: [
      ['Folder', '~/Code/api-fix-auth (deleted)'],
      ['Framework', 'FastAPI'],
      ['Command', 'uvicorn main:app --port 8000'],
      ['PID', '22718'],
      ['Started', 'Mon 3:40 PM'],
      ['Worktree', 'deleted'],
    ],
    cleanUp: { reason: 'deleted', note: 'Worktree deleted', suggested: true },
  },
]

export const serverByPort = (port: string) => SERVERS.find((server) => server.port === port)!

// Port identities are stable: stopping a server never recolours the rest.
// Same palette as the app (Theme.swift), avoiding the red, amber and green status families.
const PORT_COLORS = ['#6EC7ED', '#B599F0', '#EB9CD4', '#7D9CF2', '#7DDBE0', '#D9A3F2', '#ABC2E0']
export const portColor = (port: string) =>
  PORT_COLORS[Math.max(0, SERVERS.findIndex((server) => server.port === port)) % PORT_COLORS.length]

export const AMBER = '#FFB224'
export const SYSTEM_MEMORY = 16 * 1024
export const OTHER_APPS = [
  { id: 'chrome', name: 'Google Chrome', memory: 1536 },
  { id: 'conductor', name: 'Conductor', memory: 768 },
  { id: 'rest', name: 'Everything else', memory: 4864 },
]
export const OTHER_MEMORY = OTHER_APPS.reduce((sum, app) => sum + app.memory, 0)

/** Compact totals for headers: "4.8 GB", "612 MB". */
export const formatTotal = (mb: number) => (mb >= 1024 ? `${Number((mb / 1024).toFixed(1))} GB` : `${Math.round(mb)} MB`)
/** Per-server readings: "1.21 GB", "184 MB". */
export const formatMemory = (mb: number) => (mb >= 1024 ? `${(mb / 1024).toFixed(2)} GB` : `${Math.round(mb)} MB`)
export const shareOfRAM = (mb: number) => `${((mb / SYSTEM_MEMORY) * 100).toFixed(1)}%`

// Deterministic ten-minute histories shared by both detail charts and the terminal.
const WOBBLE = [
  40, 39.2, 38.2, 39.3, 39.6, 40.2, 40.1, 38.6, 38, 37.2, 38.1, 38.8, 38.8, 38, 37.7, 36.5, 35.7, 35.8, 37, 37.6, 36.5,
  36.5, 34.5, 34.8, 35.5, 36.3, 36.4, 35.4, 35, 33.6, 34.3, 37.3, 37.9, 36.5, 35, 33.7, 32.2, 32.1, 32.8, 33.2, 33.7,
  33.4, 31.8, 30.9, 31.1, 31.2, 32, 32, 31.6, 31, 29.3, 30, 30.1, 30.5, 31.5, 30.6, 30, 28.3, 28, 29.1,
]
const LEAK = [
  33.4, 33, 33.8, 32.6, 32.2, 32.6, 30.8, 31.2, 29.4, 29.8, 27.9, 26.7, 27.1, 24.8, 23.7, 24, 21.4, 20, 19.2, 17, 15.2,
  13.8, 11.9, 10.4, 9.3, 8.1, 7, 6.2, 5.5, 4.8,
]

export type MemoryChart = {
  points: { x: number; y: number; memory: number }[]
  line: string
  end: number
  limit: number
}

const chartCache = new Map<string, MemoryChart>()

/** Memory over ten minutes on a 328×56 plot, ending at the current reading, with the 2 GB limit. */
export function memoryChart(server: Server): MemoryChart {
  const cached = chartCache.get(server.port)
  if (cached) return cached
  const raw = server.chart === 'leaking' ? LEAK : WOBBLE
  const last = raw[raw.length - 1]
  const perStep = server.chart === 'leaking' ? 1126 / (raw[0] - last) : server.chart === 'flat' ? 0.1 : 8
  const values = raw.map((y) => server.memory - (y - last) * perStep)
  const top = Math.max(2048, ...values.map((mb) => mb * 1.1))
  const points = values.map((mb, i) => ({ x: (i * 328) / (values.length - 1), y: 56 * (1 - mb / top), memory: mb }))
  const chart = {
    points,
    line: `M${points.map((p) => `${p.x.toFixed(1)} ${p.y.toFixed(1)}`).join(' L')}`,
    end: points[points.length - 1].y,
    limit: 56 * (1 - 2048 / top),
  }
  chartCache.set(server.port, chart)
  return chart
}

// CPU history, scaled so the final sample matches the current reading.
const CPU = [
  4.3, 2.1, 3.6, 3.2, 3.1, 2.6, 4.1, 4.5, 2.7, 3.4, 1.1, 3.6, 16, 17.3, 4.1, 2, 2.4, 3.5, 0.9, 2.6, 1.5, 1.3, 1.1, 3.9,
  1.3, 1.8, 2.4, 4.3, 1.2, 2.6, 3, 4.3, 4.1, 4.2, 1.9, 2.5, 2.2, 4.3, 4.6, 1.4, 1.5, 14.3, 14.4, 15.3, 3.1, 1.9, 0.9,
  2.5, 2.3, 3.1, 4.6, 3.5, 2.9, 3.3, 3.5, 1.1, 4.4, 3.9, 4.3, 4,
]

export const cpuBars = (server: Server) => CPU.map((h) => Math.min(100, (h / CPU[CPU.length - 1]) * server.cpu))
