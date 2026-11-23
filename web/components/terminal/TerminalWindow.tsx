'use client'

import { type KeyboardEvent, type PointerEvent, type ReactNode, useCallback, useEffect, useRef, useState } from 'react'
import { type AppLanguage, languageLabel } from '@/lib/i18n'
import {
  AMBER,
  OTHER_MEMORY,
  SERVERS,
  SYSTEM_MEMORY,
  type Server,
  cpuBars,
  formatMemory,
  formatTotal,
  memoryChart,
  portColor,
  serverByPort,
} from '@/lib/demo'
import { brailleCanvas, sparkline } from './braille'
import { PROMPT, lastLogin, reply, wrap } from './shell'
import styles from './terminal.module.css'

// `porto` in a draggable terminal window, working on the demo's sample servers.
// Mirrors the app's TerminalApp.swift: the memory bar, two-line rows, details
// with braille charts, the Actions menu, stop confirmation, Clean up and Keys.
// Dragging and resizing reflow it to the window's columns and rows like a real
// terminal. Everything is simulated; nothing touches the visitor's machine.

const RED = '#FF6961'
const SCREEN = { width: 1152, height: 720, menuBar: 30 }
// Window chrome around the character grid: title bar, body padding and line insets.
const CHAR = { width: 6.6, height: 15 }
const CHROME = { width: 40, height: 50 }
// 64×30 by default; no smaller than 44×14.
const DEFAULT_SIZE = { width: 468, height: 505 }
const MIN_SIZE = { width: 331, height: 260 }

const grid = (size: { width: number; height: number }) => ({
  cols: Math.floor((size.width - CHROME.width) / CHAR.width),
  rows: Math.floor((size.height - CHROME.height) / CHAR.height),
})

const cx = (...names: (string | false | undefined)[]) => names.filter(Boolean).join(' ')
const history = (server: Server) => memoryChart(server).points.map((point) => point.memory)
const trim = (gb: number) => (Number.isInteger(gb) ? String(gb) : gb.toFixed(1))

// ─── Lines ───

function Line({ children, className, selected, onClick }: { children?: ReactNode; className?: string; selected?: boolean; onClick?: () => void }) {
  return (
    <div className={cx(styles.line, selected && styles.selected, className)} onClick={onClick}>
      {children}
    </div>
  )
}

const blank = (key: string) => <Line key={key} />
const Cells = ({ text }: { text: string }) => (
  <>
    {Array.from(text, (char, index) => (
      <span key={index} className={styles.cell}>
        {char}
      </span>
    ))}
  </>
)
const divider = (key: string) => <div key={key} className={styles.divider} />
const Spacer = () => <span className={styles.spacer} />
const T2 = ({ children }: { children: ReactNode }) => <span className={styles.text2}>{children}</span>
const T3 = ({ children }: { children: ReactNode }) => <span className={styles.text3}>{children}</span>

function PortLabel({ server }: { server: Server }) {
  return (
    <span className={styles.port} style={{ color: portColor(server.port) }}>
      <span style={{ opacity: server.status === 'idle' ? 0.45 : 1, fontWeight: server.status === 'amber' ? 700 : 400 }}>:</span>
      {server.port}
    </span>
  )
}

type Hint = [key: string, label: string, tone?: 'red' | 'off']

/** Drops hints from the end until they fit, keeping Keys as long as possible and always the last. */
function hints(items: Hint[], key: string, inner: number) {
  const width = (kept: number[]) =>
    kept.reduce((sum, index) => sum + items[index][0].length + 1 + items[index][1].length, 0) + (kept.length - 1) * 3
  let kept = items.map((_, index) => index)
  for (const pass of [0, 1]) {
    for (let index = items.length - 2; index >= 0 && width(kept) > inner; index--) {
      if (pass === 0 && items[index][0] === '?') continue
      kept = kept.filter((k) => k !== index)
    }
  }
  return [
    divider(`${key}-divider`),
    <Line key={key} className={styles.hints}>
      {kept.map((index) => {
        const [k, label, tone] = items[index]
        const color = tone === 'red' ? RED : undefined
        return (
          <span key={k} style={{ color, opacity: tone === 'off' ? 0.4 : 1 }}>
            <strong>{k}</strong> <span className={color ? undefined : styles.text3}>{label}</span>
          </span>
        )
      })}
    </Line>,
  ]
}

type Action = { label: string; key: string; destructive?: boolean; run: () => void }
type Page = { name: 'list' } | { name: 'detail'; port: string } | { name: 'help' }
type ShellLine = { prompt?: boolean; text: string; tone?: 'dim' }
type Edges = { left?: boolean; right?: boolean; top?: boolean; bottom?: boolean }
type WindowFrame = { x: number; y: number; width: number; height: number }

const EDGES: [string, Edges][] = [
  ['n', { top: true }],
  ['s', { bottom: true }],
  ['e', { right: true }],
  ['w', { left: true }],
  ['ne', { top: true, right: true }],
  ['nw', { top: true, left: true }],
  ['se', { bottom: true, right: true }],
  ['sw', { bottom: true, left: true }],
]

export function TerminalWindow({ visible = true, desktop = false }: { visible?: boolean; desktop?: boolean }) {
  const windowRef = useRef<HTMLDivElement>(null)
  // `edges` is null while moving the window by its title bar, otherwise the edges being resized.
  const gesture = useRef<{ edges: Edges | null; x: number; y: number; frame: WindowFrame; scale: number } | null>(null)
  const [frame, setFrame] = useState<WindowFrame>({ x: SCREEN.width - DEFAULT_SIZE.width - 20, y: 60, ...DEFAULT_SIZE })
  const { cols, rows } = grid(desktop ? frame : DEFAULT_SIZE)
  // The UI keeps a two-column inset each side; the shell wraps just inside the edge.
  const inner = cols - 4
  const shellCols = cols - 2
  const [focused, setFocused] = useState(false)
  const [closed, setClosed] = useState(false)

  // The shell
  const [appLanguage, setAppLanguage] = useState<AppLanguage>('system')
  const [mode, setMode] = useState<'shell' | 'tui' | 'ended'>('shell')
  const [lines, setLines] = useState<ShellLine[]>([])
  const [input, setInput] = useState('')
  const [typing, setTyping] = useState(true)
  const [past, setPast] = useState<string[]>([])
  const [recall, setRecall] = useState<number | null>(null)

  // porto
  const [running, setRunning] = useState(() => SERVERS.map((s) => s.port))
  const [selected, setSelected] = useState(SERVERS[0].port)
  const [page, setPage] = useState<Page>({ name: 'list' })
  const [helpFrom, setHelpFrom] = useState<Page>({ name: 'list' })
  const [menu, setMenu] = useState<{ port: string; index: number } | null>(null)
  const [confirm, setConfirm] = useState<string | null>(null)
  const [toast, setToast] = useState<{ text: string; error?: boolean } | null>(null)
  const [cleaning, setCleaning] = useState(false)
  const [checked, setChecked] = useState<string[]>([])
  const [infoExpanded, setInfoExpanded] = useState(false)
  const [processesExpanded, setProcessesExpanded] = useState(false)
  const [cpuAll, setCpuAll] = useState(false)
  const [offset, setOffset] = useState(0)
  const toastTimer = useRef<ReturnType<typeof setTimeout>>(undefined)

  const servers = SERVERS.filter((s) => running.includes(s.port))

  const show = useCallback((text: string, error = false) => {
    setToast({ text, error })
    clearTimeout(toastTimer.current)
    toastTimer.current = setTimeout(() => setToast(null), 2500)
  }, [])

  const launch = useCallback(() => {
    setMode('tui')
    setPage({ name: 'list' })
    setMenu(null)
    setConfirm(null)
    setCleaning(false)
    setOffset(0)
  }, [])

  // Each time the window appears: a fresh login, `porto` typed out, then the UI loads.
  useEffect(() => {
    if (!visible) {
      windowRef.current?.blur()
      return
    }
    setClosed(false)
    setMode('shell')
    setRunning(SERVERS.map((s) => s.port))
    setSelected(SERVERS[0].port)
    setLines([{ text: lastLogin('ttys002') }])
    setInput('')
    setTyping(true)
    const reduce = window.matchMedia('(prefers-reduced-motion: reduce)').matches
    const timers: ReturnType<typeof setTimeout>[] = []
    const at = (ms: number, run: () => void) => timers.push(setTimeout(run, reduce ? 0 : ms))
    // Give the window a moment to settle before typing.
    ;['p', 'po', 'por', 'port', 'porto'].forEach((text, index) => at(1500 + index * 150, () => setInput(text)))
    at(2600, () => {
      setLines((current) => [...current, { prompt: true, text: 'porto' }])
      setInput('')
      setTyping(false)
      launch()
      if (desktop) windowRef.current?.focus({ preventScroll: true })
    })
    return () => timers.forEach(clearTimeout)
  }, [visible, desktop, launch])

  useEffect(() => () => clearTimeout(toastTimer.current), [])

  // ─── Actions ───

  const stop = (ports: string[]) => {
    setRunning((current) => current.filter((port) => !ports.includes(port)))
    setChecked((current) => current.filter((port) => !ports.includes(port)))
    if (page.name === 'detail' && ports.includes(page.port)) setPage({ name: 'list' })
  }

  const actionsFor = (server: Server): Action[] => {
    const agent = server.session ? (server.session.agent === 'claude' ? 'Claude Code' : 'Codex') : null
    const count = server.processes.length
    const items: Action[] = [{ label: `Open localhost:${server.port}`, key: 'o', run: () => show(`Opened localhost:${server.port}`) }]
    if (agent) items.push({ label: `Resume ${agent} in Terminal`, key: 'a', run: () => show('Resuming in Terminal') })
    items.push({ label: agent ? `Restart · runs outside ${agent}` : 'Restart', key: 'r', run: () => show(`Restarting :${server.port}`) })
    items.push({
      label: `Stop ${count} ${count === 1 ? 'process' : 'processes'}`,
      key: 's',
      destructive: true,
      run: () => setConfirm(server.port),
    })
    if (server.status !== 'idle') {
      items.push({ label: 'Open in editor', key: 'e', run: () => show('Opened in Cursor') })
      items.push({ label: 'Reveal in Finder', key: 'f', run: () => show('Revealed in Finder') })
    }
    items.push({ label: 'Copy URL', key: 'y', run: () => show('Copied URL') })
    items.push({ label: 'Copy command', key: 'Y', run: () => show('Copied command') })
    return items
  }

  const shortcut = (key: string, server?: Server) => {
    const item = server && actionsFor(server).find((action) => action.key === key)
    if (!item) return false
    setMenu(null)
    item.run()
    return true
  }

  const move = (delta: number) => {
    if (!servers.length) return
    const index = Math.max(servers.findIndex((s) => s.port === selected), 0)
    setSelected(servers[Math.min(Math.max(index + delta, 0), servers.length - 1)].port)
  }

  const openDetail = (port: string) => {
    setSelected(port)
    setOffset(0)
    setPage({ name: 'detail', port })
  }

  const quit = () => {
    setMode('shell')
    setMenu(null)
    setConfirm(null)
    setCleaning(false)
  }

  // ─── Keys ───

  /** Returns true when the key was used, so the page doesn't also scroll. */
  const handleTui = (key: string, ctrl: boolean): boolean => {
    const current = servers.find((s) => s.port === selected) ?? servers[0]
    if (ctrl && key === 'c') {
      quit()
      return true
    }
    if (ctrl) return false

    if (confirm) {
      const server = serverByPort(confirm)
      setConfirm(null)
      if (['y', 'Y', 's', 'Enter'].includes(key)) {
        stop([server.port])
        show(`Stopping ${server.name} :${server.port}`)
      }
      return true
    }

    if (menu) {
      const server = serverByPort(menu.port)
      const items = actionsFor(server)
      if (key === 'ArrowUp' || key === 'k') setMenu({ ...menu, index: (menu.index + items.length - 1) % items.length })
      else if (key === 'ArrowDown' || key === 'j' || key === 'Tab') setMenu({ ...menu, index: (menu.index + 1) % items.length })
      else if (key === 'Enter') {
        setMenu(null)
        items[menu.index]?.run()
      } else if (!shortcut(key, server)) setMenu(null)
      return true
    }

    if (page.name === 'help') {
      if (key === 'ArrowUp' || key === 'k') setOffset((o) => o - 1)
      else if (key === 'ArrowDown' || key === 'j') setOffset((o) => o + 1)
      else {
        setOffset(0)
        setPage(helpFrom)
      }
      return true
    }

    if (key === '?') {
      setHelpFrom(page)
      setOffset(0)
      setPage({ name: 'help' })
      return true
    }

    if (page.name === 'detail') {
      const server = serverByPort(page.port)
      switch (key) {
        case 'Escape':
        case 'ArrowLeft':
        case 'Backspace':
        case 'h':
        case 'q':
          setPage({ name: 'list' })
          return true
        case 'ArrowUp':
        case 'k':
          setOffset((o) => o - 1)
          return true
        case 'ArrowDown':
        case 'j':
          setOffset((o) => o + 1)
          return true
        case 'Enter':
          show(`Opened localhost:${server.port}`)
          return true
        case ' ':
        case '.':
          setMenu({ port: server.port, index: 0 })
          return true
        case 'i':
          setInfoExpanded((expanded) => !expanded)
          return true
        case 'p':
          setProcessesExpanded((expanded) => !expanded)
          return true
        case 'Tab': {
          const index = servers.findIndex((s) => s.port === server.port)
          openDetail(servers[(index + 1) % servers.length].port)
          return true
        }
        default:
          return shortcut(key, server)
      }
    }

    // The list
    switch (key) {
      case 'ArrowUp':
      case 'k':
        move(-1)
        return true
      case 'ArrowDown':
      case 'j':
        move(1)
        return true
      case 'g':
      case 'Home':
        move(-99)
        return true
      case 'G':
      case 'End':
        move(99)
        return true
      case 'q':
      case 'Escape':
        if (cleaning) setCleaning(false)
        else quit()
        return true
    }
    if (cleaning) {
      switch (key) {
        case ' ':
        case 'x':
          if (current) setChecked((c) => (c.includes(current.port) ? c.filter((p) => p !== current.port) : [...c, current.port]))
          return true
        case 'a':
          setChecked((c) => (c.length === servers.length ? [] : servers.map((s) => s.port)))
          return true
        case 'Enter': {
          const chosen = servers.filter((s) => checked.includes(s.port))
          if (!chosen.length) return true
          stop(chosen.map((s) => s.port))
          setCleaning(false)
          const freed = formatMemory(chosen.reduce((sum, s) => sum + s.memory, 0))
          show(`Stopping ${chosen.length} ${chosen.length === 1 ? 'server' : 'servers'} · freeing ${freed}`)
          return true
        }
        case 'c':
          setCleaning(false)
          return true
      }
      return false
    }
    switch (key) {
      case 'Enter':
      case 'ArrowRight':
      case 'l':
        if (current) openDetail(current.port)
        return true
      case ' ':
      case '.':
        if (current) setMenu({ port: current.port, index: 0 })
        return true
      case 'c':
        if (servers.length) {
          setChecked(servers.filter((s) => s.cleanUp?.suggested).map((s) => s.port))
          setCleaning(true)
        }
        return true
      case 't':
        setCpuAll((all) => !all)
        return true
    }
    return shortcut(key, current)
  }

  const run = (command: string) => {
    const result = reply(command, running, appLanguage)
    if (result.language) setAppLanguage(result.language)
    if (command.trim()) setPast((current) => [...current, command])
    setRecall(null)
    setInput('')
    if (result.action === 'clear') {
      setLines([])
      return
    }
    if (result.action === 'exit') {
      setLines((current) => [
        ...current,
        { prompt: true, text: command },
        { text: '' },
        { text: 'Saving session...completed.' },
        { text: '' },
        { text: '[Process completed]' },
      ])
      setMode('ended')
      return
    }
    setLines((current) => [...current, { prompt: true, text: command }, ...result.lines])
    if (result.action === 'porto') launch()
  }

  const handleShell = (event: KeyboardEvent): boolean => {
    const { key, ctrlKey } = event
    if (ctrlKey && key === 'c') {
      setLines((current) => [...current, { prompt: true, text: `${input}^C` }])
      setInput('')
      return true
    }
    if (ctrlKey && key === 'l') {
      setLines([])
      return true
    }
    if (ctrlKey || event.altKey) return false
    if (key === 'Enter') {
      run(input)
      return true
    }
    if (key === 'Backspace') {
      setInput((value) => value.slice(0, -1))
      return true
    }
    if (key === 'Tab') {
      if (input && 'porto'.startsWith(input)) setInput('porto')
      return true
    }
    if (key === 'ArrowUp' || key === 'ArrowDown') {
      if (!past.length) return true
      const next = recall === null ? (key === 'ArrowUp' ? past.length - 1 : null) : recall + (key === 'ArrowUp' ? -1 : 1)
      const index = next === null || next >= past.length ? null : Math.max(next, 0)
      setRecall(index)
      setInput(index === null ? '' : past[index])
      return true
    }
    if (key === 'Escape') return true
    if (key.length === 1) {
      setInput((value) => (value.length < 48 ? value + key : value))
      return true
    }
    return false
  }

  const onKeyDown = (event: KeyboardEvent<HTMLDivElement>) => {
    if (typing || event.metaKey) return
    let used: boolean
    if (mode === 'ended') {
      // Any key starts a new session.
      setLines([{ text: lastLogin('ttys003') }])
      setMode('shell')
      used = true
    } else if (mode === 'tui') {
      used = handleTui(event.key, event.ctrlKey)
    } else {
      used = handleShell(event)
    }
    if (used) event.preventDefault()
  }

  // ─── Moving and resizing ───

  const startGesture = (edges: Edges | null) => (event: PointerEvent<HTMLElement>) => {
    const screen = (windowRef.current?.parentElement?.offsetParent ?? null) as HTMLElement | null
    if (!desktop || !screen || (event.target as HTMLElement).closest('button')) return
    event.preventDefault()
    event.stopPropagation()
    windowRef.current?.focus({ preventScroll: true })
    event.currentTarget.setPointerCapture(event.pointerId)
    gesture.current = { edges, x: event.clientX, y: event.clientY, frame, scale: screen.getBoundingClientRect().width / SCREEN.width }
  }

  const onPointerMove = (event: PointerEvent<HTMLElement>) => {
    const start = gesture.current
    if (!start) return
    const dx = (event.clientX - start.x) / start.scale
    const dy = (event.clientY - start.y) / start.scale
    const { x, y, width, height } = start.frame
    const clamp = (value: number, min: number, max: number) => Math.min(Math.max(value, min), max)
    if (!start.edges) {
      // Keep the title bar on the screen and below the menu bar, like macOS.
      setFrame({ ...start.frame, x: clamp(x + dx, 80 - width, SCREEN.width - 80), y: clamp(y + dy, SCREEN.menuBar, SCREEN.height - 28) })
      return
    }
    const next = { ...start.frame }
    if (start.edges.right) next.width = clamp(width + dx, MIN_SIZE.width, SCREEN.width - x)
    if (start.edges.bottom) next.height = clamp(height + dy, MIN_SIZE.height, SCREEN.height - y)
    if (start.edges.left) {
      next.x = clamp(x + dx, 0, x + width - MIN_SIZE.width)
      next.width = width + x - next.x
    }
    if (start.edges.top) {
      next.y = clamp(y + dy, SCREEN.menuBar, y + height - MIN_SIZE.height)
      next.height = height + y - next.y
    }
    setFrame(next)
  }

  const endGesture = () => {
    gesture.current = null
  }

  const pointerHandlers = { onPointerMove, onPointerUp: endGesture, onPointerCancel: endGesture }

  // ─── Rendering ───

  function listLines(): [ReactNode[], ReactNode[]] {
    const chosen = servers.filter((s) => checked.includes(s.port))
    const total = servers.reduce((sum, s) => sum + s.memory, 0)
    const [number, unit] = formatTotal(cleaning ? chosen.reduce((sum, s) => sum + s.memory, 0) : total).split(' ')
    const cpu = Math.round(servers.reduce((sum, s) => sum + s.cpu, 0) / 8)
    const free = SYSTEM_MEMORY - total - OTHER_MEMORY
    const share = 100 / SYSTEM_MEMORY

    const top = [
      <Line key="title" className={styles.centered}>
        <strong>{cleaning ? 'Clean up' : 'Servers'}</strong>
      </Line>,
      blank('b1'),
      <Line key="amount">
        <span>
          <strong>{number}</strong> <T3>{unit}</T3>
        </span>
        <Spacer />
        {cleaning ? (
          <T2>{chosen.length ? `freed by stopping ${chosen.length}` : 'Pick servers to stop'}</T2>
        ) : (
          <>
            <T3>{cpuAll ? 'CPU (all)' : 'CPU (servers)'}</T3>
            <T2>&nbsp;&nbsp;{cpuAll ? cpu + 18 : cpu}%</T2>
          </>
        )}
      </Line>,
      <div key="bar" className={styles.bar}>
        {servers.map((s) => {
          const focus = s.port === selected
          return (
            <span
              key={s.port}
              className={styles.segment}
              data-selected={focus}
              data-lit={cleaning ? checked.includes(s.port) || focus : focus}
              style={{ width: `${Math.max(s.memory * share, 1.2)}%`, background: portColor(s.port) }}
              onClick={() => setSelected(s.port)}
            />
          )
        })}
        <span className={styles.baseline} style={{ width: `${OTHER_MEMORY * share}%` }} />
        <span className={styles.track} />
      </div>,
      <Line key="legend">
        <span className={styles.swatch} style={{ height: '0.62em', background: '#F5F5F7' }} />
        <T2>Servers&nbsp;</T2>
        <T3>{formatTotal(total)}</T3>
        <span className={styles.swatch} style={{ height: '0.25em', background: '#F5F5F747' }} />
        <T2>Other apps&nbsp;</T2>
        <T3>{formatTotal(OTHER_MEMORY)}</T3>
        <span className={styles.swatch} style={{ height: '0.25em', background: '#F5F5F71f' }} />
        <T2>Free&nbsp;</T2>
        <T3>
          {formatTotal(free).split(' ')[0]} of {formatTotal(SYSTEM_MEMORY)}
        </T3>
      </Line>,
      divider('d1'),
    ]

    if (!servers.length) {
      return [
        top,
        [
          blank('e0'),
          ...[0, 1, 2, 3, 4].map((row) => (
            <Line key={`dots${row}`} className={cx(styles.centered, styles.faint)}>
              ● ● ● ● ●
            </Line>
          )),
          blank('e1'),
          <Line key="e2" className={styles.centered}>
            <T2>Nothing listening</T2>
          </Line>,
          <Line key="e3" className={styles.centered}>
            <T3>Dev servers on ports 3000–65535 show up here.</T3>
          </Line>,
        ],
      ]
    }

    const rows: ReactNode[] = [blank('r0')]
    servers.forEach((s, index) => {
      const isSelected = s.port === selected
      const amber = s.status === 'amber'
      const reason = cleaning ? s.cleanUp : undefined
      const agent = s.context.agent === 'claude' ? '✳ ' : s.context.agent === 'codex' ? '>_ ' : ''
      const on = checked.includes(s.port)
      const click = () => {
        if (isSelected && cleaning) setChecked((c) => (on ? c.filter((p) => p !== s.port) : [...c, s.port]))
        else if (isSelected) openDetail(s.port)
        else setSelected(s.port)
      }
      const idle = s.status === 'idle' ? styles.idle : undefined
      if (index > 0) rows.push(blank(`gap${s.port}`))
      rows.push(
        <Line key={`${s.port}a`} selected={isSelected} onClick={click} className={idle}>
          {cleaning && <span className={on ? undefined : styles.text3}>{on ? '[✓] ' : '[ ] '}</span>}
          <PortLabel server={s} />
          <span className={styles.name}>{s.branch.replace(/-/g, ' ')}</span>
          <span className={styles.spark} style={{ color: amber ? AMBER : undefined }}>
            <Cells text={sparkline(history(s))} />
          </span>
          <span className={styles.memory} style={{ color: amber ? AMBER : undefined }}>
            {formatMemory(s.memory)}
          </span>
        </Line>,
        <Line key={`${s.port}b`} selected={isSelected} onClick={click} className={idle}>
          <span className={styles.indent} style={{ width: cleaning ? '11ch' : undefined }} />
          {reason ? (
            <span className={reason.reason === 'leaking' ? undefined : styles.text2} style={{ color: reason.reason === 'leaking' ? AMBER : undefined }}>
              {reason.note}
            </span>
          ) : (
            <span className={styles.text2} style={{ color: s.context.tone === 'amber' ? AMBER : undefined }}>
              {agent}
              {s.context.text}
            </span>
          )}
        </Line>,
      )
    })
    rows.push(blank('r-end'))
    return [top, rows]
  }

  function detailLines(server: Server): [ReactNode[], ReactNode[]] {
    const top = [
      <Line key="title">
        <span className={styles.text2} onClick={() => setPage({ name: 'list' })}>
          ‹
        </span>
        <span className={styles.centerFill}>
          <strong>{server.name}</strong>
        </span>
        <span style={{ width: '1ch' }} />
      </Line>,
      blank('b1'),
      <Line key="port">
        <PortLabel server={server} />
        <Spacer />
        <T3>{server.uptime.startsWith('up ') ? `Running for ${server.uptime.slice(3)}` : server.uptime.replace(/^idle/, 'Idle')}</T3>
      </Line>,
      divider('d1'),
    ]

    const row = (label: string, value: ReactNode, key: string) => (
      <Line key={key}>
        <span className={cx(styles.text3, styles.label)}>{label}</span>
        <span className={styles.value}>{value}</span>
      </Line>
    )
    const primary: ReactNode[] = []
    if (server.session) {
      const glyph = server.session.agent === 'claude' ? '✳ ' : '>_ '
      primary.push(
        row(
          'Session',
          <>
            {glyph}
            {server.session.title}
            <T2> ↗</T2>
          </>,
          'session',
        ),
      )
    }
    primary.push(row('Branch', server.branch, 'branch'))
    const folder = server.info.find(([label]) => label === 'Folder')
    const folderIsPrimary = primary.length < 2
    if (folderIsPrimary && folder) primary.push(row('Folder', <T2>{folder[1]}</T2>, 'folder'))
    const secondary = server.info
      .filter(([label]) => !(label === 'Folder' && folderIsPrimary))
      .map(([label, value]) => row(label, <T2>{value}</T2>, `info-${label}`))

    // Memory: a braille line over ten minutes with the 2 GB alert dotted in amber.
    const threshold = 2048
    const values = history(server)
    const topMB = Math.max(threshold, ...values.map((v) => v * 1.1))
    const gutter = 5
    const plotColumns = inner - gutter - 1
    const memory = brailleCanvas(plotColumns, 4)
    const marks = brailleCanvas(plotColumns, 4)
    const y = (mb: number) => Math.round((1 - mb / topMB) * 15)
    memory.plot(values.map((mb, i): [number, number] => [Math.round((i / (values.length - 1)) * (plotColumns * 2 - 1)), y(mb)]))
    for (let x = 0; x < plotColumns * 2; x += 2) marks.set(x, y(threshold))
    const thresholdRow = Math.floor(y(threshold) / 4)
    const axis = (label: string, color?: string) => (
      <>
        <span
          className={color ? undefined : styles.text3}
          style={{ width: `${gutter}ch`, flexShrink: 0, textAlign: 'right', paddingRight: '1ch', color }}
        >
          {label}
        </span>
        <span className={styles.faint}>│</span>
      </>
    )
    const memoryRows = [0, 1, 2, 3].map((r) => (
      <Line key={`mem${r}`}>
        {r === thresholdRow ? axis(`${trim(threshold / 1024)} GB`, `${AMBER}d9`) : axis(r === 3 ? '0' : '')}
        <span>
          {Array.from({ length: plotColumns }, (_, c) =>
            !memory.empty(r, c) ? (
              <span key={c} className={styles.cell}>
                {memory.char(r, c)}
              </span>
            ) : !marks.empty(r, c) ? (
              <span key={c} className={styles.cell} style={{ color: `${AMBER}99` }}>
                {marks.char(r, c)}
              </span>
            ) : (
              <span key={c} className={styles.cell} />
            ),
          )}
        </span>
      </Line>
    ))

    // CPU: block bars, the latest brightest.
    const bars = cpuBars(server)
    const buckets = Array.from({ length: plotColumns }, (_, c) => {
      const from = Math.floor((c / plotColumns) * bars.length)
      const to = Math.max(Math.floor(((c + 1) / plotColumns) * bars.length), from + 1)
      const slice = bars.slice(from, to)
      return slice.reduce((sum, v) => sum + v, 0) / slice.length
    })
    const blocks = ' ▁▂▃▄▅▆▇█'
    const cpuRows = [0, 1, 2, 3].map((r) => (
      <Line key={`cpu${r}`}>
        {axis(r === 0 ? '100%' : r === 3 ? '0' : '')}
        <span>
          {buckets.map((value, c) => {
            let eighths = Math.round((value / 100) * 32)
            if (value >= 1) eighths = Math.max(eighths, 1)
            const level = Math.min(Math.max(eighths - (3 - r) * 8, 0), 8)
            return (
              <span key={c} className={styles.cell} style={{ opacity: c === buckets.length - 1 ? 0.85 : 0.32 }}>
                {blocks[level]}
              </span>
            )
          })}
        </span>
      </Line>
    ))

    const processTotal = server.processes.reduce((sum, p) => sum + p.memory, 0)
    const largest = Math.max(...server.processes.map((p) => p.memory))
    const pid = Number(server.info.find(([label]) => label === 'PID')?.[1] ?? 40000)

    const content: ReactNode[] = [
      blank('i0'),
      ...primary,
      ...(infoExpanded ? secondary : []),
      <Line key="more" onClick={() => setInfoExpanded((expanded) => !expanded)}>
        <span className={styles.label} />
        <T3>{infoExpanded ? 'Less ▴' : `${secondary.length} more ▾`}</T3>
        <strong className={styles.text2}>&nbsp;&nbsp;&nbsp;i</strong>
      </Line>,
      blank('i1'),
      divider('d2'),
      blank('c0'),
      <Line key="mh">
        <T2>Memory</T2>
        <strong>&nbsp;&nbsp;{formatMemory(server.memory)}</strong>
        <Spacer />
        <T3>10 min</T3>
      </Line>,
      ...memoryRows,
      blank('c1'),
      <Line key="ch">
        <T2>CPU</T2>
        <strong>&nbsp;&nbsp;{server.cpu}%</strong>
      </Line>,
      ...cpuRows,
      blank('c2'),
      divider('d3'),
      blank('p0'),
      <Line key="ph" onClick={() => setProcessesExpanded((expanded) => !expanded)}>
        <T2>Processes </T2>
        <T3>{processesExpanded ? '▾' : '▸'}</T3>
        <strong className={styles.text2}>&nbsp;&nbsp;&nbsp;p</strong>
        <Spacer />
        <T2>
          {server.processes.length} · {formatMemory(processTotal)}
        </T2>
      </Line>,
      ...(processesExpanded
        ? server.processes.map((process, index) => {
            const filled = Math.max(Math.round((8 * process.memory) / largest), 1)
            return (
              <Line key={`proc${index}`}>
                <span className={index === 0 ? undefined : styles.text2}>
                  {index > 0 ? '└ ' : ''}
                  {process.command}
                </span>
                <Spacer />
                <T3>{String(pid + index).padEnd(8)}</T3>
                <span>{'━'.repeat(filled)}</span>
                <span className={styles.faint}>{'─'.repeat(8 - filled)}</span>
                <span className={styles.memory} style={{ width: '10ch' }}>
                  {formatMemory(process.memory)}
                </span>
              </Line>
            )
          })
        : []),
      blank('p1'),
    ]
    return [top, content]
  }

  function helpLines(): [ReactNode[], ReactNode[]] {
    const groups: [string, [string, string][]][] = [
      ['Servers', [['↑ ↓  j k', 'Select'], ['⏎', 'Details'], ['space', 'Actions'], ['c', 'Clean up'], ['t', 'CPU for servers or the whole Mac']]],
      [
        'Actions',
        [['o', 'Open in browser'], ['a', 'Resume agent session'], ['r', 'Restart'], ['s', 'Stop'], ['e', 'Open in editor'], ['f', 'Reveal in Finder'], ['y', 'Copy URL'], ['Y', 'Copy command']],
      ],
      ['Clean up', [['space', 'Select or deselect'], ['a', 'Select all'], ['⏎', 'Stop selected'], ['esc', 'Cancel']]],
      ['Details', [['⏎', 'Open in browser'], ['space', 'Actions'], ['i', 'More or less info'], ['p', 'Show or hide processes'], ['tab', 'Next server'], ['esc', 'Back']]],
      ['Anywhere', [['?', 'Keys'], ['esc', 'Back, or quit from the list'], ['q', 'Quit']]],
    ]
    const content: ReactNode[] = [
      blank('language-gap'),
      <Line key="app-language">
        <T2>App language: {languageLabel(appLanguage)}</T2>
      </Line>,
      <Line key="language-help">
        <T3>porto language &lt;code&gt; · terminal text stays English</T3>
      </Line>,
    ]
    groups.forEach(([title, keys]) => {
      content.push(
        blank(`h-${title}`),
        <Line key={`t-${title}`}>
          <T2>{title}</T2>
        </Line>,
      )
      keys.forEach(([key, label]) =>
        content.push(
          <Line key={`${title}-${key}-${label}`}>
            <strong style={{ width: '13ch', flexShrink: 0 }}>{key}</strong>
            <T3>{label}</T3>
          </Line>,
        ),
      )
    })
    content.push(blank('h-end'))
    const top = [
      <Line key="title" className={styles.centered}>
        <strong>Keys</strong>
      </Line>,
      blank('b1'),
      divider('d1'),
    ]
    return [top, content]
  }

  function footerLines(): ReactNode[] {
    if (confirm) {
      const server = serverByPort(confirm)
      const count = server.processes.length
      return [
        divider('f-d'),
        <Line key="confirm">
          <span className={styles.name} style={{ fontWeight: 400 }}>
            Stop {server.name} <span style={{ color: portColor(server.port), fontWeight: 500 }}>:{server.port}</span> and its {count}{' '}
            {count === 1 ? 'process' : 'processes'}?
          </span>
          <span style={{ color: RED }}>
            <strong>y</strong> Stop
          </span>
          <span>
            &nbsp;&nbsp;&nbsp;<strong>n</strong> <T3>Cancel</T3>
          </span>
        </Line>,
      ]
    }
    if (menu) {
      const server = serverByPort(menu.port)
      return [
        divider('f-d'),
        <Line key="menu-title">
          <T2>{server.name} </T2>
          <span style={{ color: portColor(server.port), fontWeight: 500 }}>:{server.port}</span>
        </Line>,
        ...actionsFor(server).map((item, index) => (
          <Line
            key={`menu-${item.key}`}
            selected={index === menu.index}
            onClick={() => {
              setMenu(null)
              item.run()
            }}
          >
            <span style={{ color: item.destructive ? RED : undefined, fontWeight: index === menu.index ? 500 : 400 }}>{item.label}</span>
            <Spacer />
            <span className={index === menu.index ? undefined : styles.text3}>{item.key}</span>
          </Line>
        )),
        <Line key="menu-hints" className={styles.hints}>
          <span>
            <strong>↑ ↓</strong> <T3>Select</T3>
          </span>
          <span>
            <strong>⏎</strong> <T3>Run</T3>
          </span>
          <span>
            <strong>esc</strong> <T3>Close</T3>
          </span>
        </Line>,
      ]
    }
    if (toast) {
      return [
        divider('f-d'),
        <Line key="toast">
          <span className={toast.error ? undefined : styles.text2} style={{ color: toast.error ? RED : undefined }}>
            {toast.text}
          </span>
        </Line>,
      ]
    }
    if (page.name === 'help') return hints([['↑ ↓', 'Scroll'], ['esc', 'Back']], 'f', inner)
    if (page.name === 'detail') {
      return hints(
        [
          ['⏎', `Open localhost:${page.port}`],
          ['space', 'Actions'],
          ['i', infoExpanded ? 'Less info' : 'More info'],
          ['p', processesExpanded ? 'Hide processes' : 'Processes'],
          ['?', 'Keys'],
          ['esc', 'Back'],
        ],
        'f',
        inner,
      )
    }
    if (cleaning) {
      const chosen = servers.filter((s) => checked.includes(s.port))
      const label = chosen.length
        ? `Stop ${chosen.length} ${chosen.length === 1 ? 'server' : 'servers'} · free ${formatMemory(chosen.reduce((sum, s) => sum + s.memory, 0))}`
        : 'Stop servers'
      return hints([['space', 'Select'], ['a', 'All'], ['⏎', label, chosen.length ? 'red' : 'off'], ['esc', 'Cancel']], 'f', inner)
    }
    if (!servers.length) return hints([['?', 'Keys'], ['q', 'Quit']], 'f', inner)
    const suggested = servers.filter((s) => s.cleanUp?.suggested).length
    return hints(
      [
        ['⏎', 'Details'],
        ['space', 'Actions'],
        ['o', 'Open'],
        ['s', 'Stop'],
        ['c', suggested ? `Clean up ${suggested}` : 'Clean up'],
        ['?', 'Keys'],
        ['q', 'Quit'],
      ],
      'f',
      inner,
    )
  }

  /** Content sits at the top; the footer follows it, and long pages scroll like the real thing. */
  function tuiFrame(): ReactNode[] {
    const footer = footerLines()
    let top: ReactNode[] = []
    let content: ReactNode[] = []
    let scroll = offset
    if (page.name === 'detail') {
      ;[top, content] = detailLines(serverByPort(page.port))
    } else if (page.name === 'help') {
      ;[top, content] = helpLines()
    } else {
      ;[top, content] = listLines()
      // Keep the selected row in view: one blank line, then rows of two lines and a gap.
      const index = Math.max(servers.findIndex((s) => s.port === selected), 0)
      const available = rows - top.length - footer.length
      scroll = Math.max(0, 1 + index * 3 + 2 - available + (index === servers.length - 1 ? 1 : 0))
    }
    const available = rows - top.length - footer.length
    scroll = Math.min(Math.max(scroll, 0), Math.max(content.length - available, 0))
    return [...top, ...content.slice(scroll, scroll + available), ...footer]
  }

  let body: ReactNode[]
  if (mode === 'tui') {
    body = tuiFrame()
  } else {
    // Wrap long output at the window's width, as a terminal would, then keep the newest rows.
    const wrapped = lines.flatMap((line) =>
      wrap(line.text, shellCols, line.prompt ? shellCols - PROMPT.length - 1 : shellCols).map((text, index) => ({
        ...line,
        text,
        prompt: line.prompt && index === 0,
      })),
    )
    body = wrapped.slice(-(rows - 1)).map((line, index) => (
      <Line key={`s${index}`} className={line.tone === 'dim' ? styles.text3 : undefined}>
        {line.prompt && <span className={styles.text2}>{PROMPT}&nbsp;</span>}
        {line.text}
      </Line>
    ))
    if (mode === 'shell') {
      body.push(
        <Line key="input">
          <span className={styles.text2}>{PROMPT}&nbsp;</span>
          {input}
          <span className={cx(styles.cursor, focused && !typing && styles.blink)} />
        </Line>,
      )
    }
  }

  if (closed) return null

  return (
    <div className={styles.shell} data-visible={visible} data-desktop={desktop} style={desktop ? { left: frame.x, top: frame.y } : undefined}>
      <div
        ref={windowRef}
        className={styles.window}
        data-focused={focused}
        tabIndex={0}
        role="application"
        aria-label="porto demo terminal. Arrow keys to move, space for actions, q to quit."
        onKeyDown={onKeyDown}
        onFocus={() => setFocused(true)}
        onBlur={() => setFocused(false)}
        onMouseDown={() => windowRef.current?.focus({ preventScroll: true })}
        style={desktop ? { width: frame.width, height: frame.height } : DEFAULT_SIZE}
      >
        <div className={styles.title} data-draggable={desktop} onPointerDown={startGesture(null)} {...pointerHandlers}>
          <span className={styles.lights}>
            <button type="button" aria-label="Close" onClick={() => setClosed(true)} />
            <button type="button" aria-label="Minimize" tabIndex={-1} />
            <button type="button" aria-label="Zoom" tabIndex={-1} />
          </span>
          {mode === 'tui' ? 'porto' : '-zsh'} — {cols}×{rows}
        </div>
        <div className={styles.body}>{body}</div>
        {desktop &&
          EDGES.map(([name, edges]) => (
            <span key={name} className={styles.grip} data-edge={name} onPointerDown={startGesture(edges)} {...pointerHandlers} />
          ))}
      </div>
    </div>
  )
}
