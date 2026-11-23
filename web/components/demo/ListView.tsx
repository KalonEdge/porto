'use client'

import { useState } from 'react'
import type { Translator } from '@/lib/i18n'
import {
  AMBER,
  OTHER_APPS,
  OTHER_MEMORY,
  SYSTEM_MEMORY,
  formatMemory,
  formatTotal,
  portColor,
  shareOfRAM,
} from '@/lib/demo'
import { AgentIcon, Colon, OpenIcon, PortoMark } from '../icons'
import { Header, useFlash } from './parts'
import type { Demo } from './useDemo'
import styles from './popover.module.css'

const cx = (...names: (string | false | undefined)[]) => names.filter(Boolean).join(' ')

/** The server list, and Clean up: the same page with checkboxes and a Stop footer. */
export function ListView({ demo, l }: { demo: Demo; l: Translator }) {
  const [flash, trigger] = useFlash()
  const cleaning = demo.view.name === 'cleanUp'
  // `focus` is the memory-bar segment under the pointer; `hoveredRow` lights up a row's segment.
  const [focus, setFocus] = useState<string | null>(null)
  const [hoveredRow, setHoveredRow] = useState<string | null>(null)
  const [cpuAll, setCpuAll] = useState(false)

  const total = demo.running.reduce((sum, s) => sum + s.memory, 0)
  const free = SYSTEM_MEMORY - total - OTHER_MEMORY
  const cpu = Math.round(demo.running.reduce((sum, s) => sum + s.cpu, 0) / 8)
  const cleanUpCount = demo.running.filter((s) => s.cleanUp?.suggested).length
  const chosen = demo.running.filter((s) => demo.selected.includes(s.port))
  const freed = chosen.reduce((sum, s) => sum + s.memory, 0)
  const focusedServer = demo.running.find((s) => s.port === focus)
  const focusedApp = OTHER_APPS.find((app) => app.id === focus)
  const focusedMemory = focusedServer?.memory ?? focusedApp?.memory
  const [value, unit] = (
    focusedServer ? formatMemory(focusedServer.memory) : formatTotal(focusedMemory ?? (cleaning ? freed : total))
  ).split(' ')
  const activePort = focus ?? hoveredRow

  const activate = (port: string) => {
    if (cleaning) return demo.toggleSelected(port)
    setFocus(null)
    demo.go({ name: 'detail', port }, 1)
  }
  const hover = (id: string) => ({
    onMouseEnter: () => setFocus(id),
    onMouseLeave: () => setFocus(null),
    onFocus: () => setFocus(id),
    onBlur: () => setFocus(null),
  })

  const title = focusedServer
    ? `${focusedServer.name} :${focusedServer.port}`
    : focusedApp?.id === 'rest'
      ? l.text('Everything else')
      : (focusedApp?.name ?? l.text(cleaning ? 'Clean up' : 'Servers'))

  return (
    <>
      <div className={styles.head}>
        <Header title={title} />
        <div className={styles.display}>
          <span className={styles.big}>{value}</span>
          <span className={styles.unit}>{unit}</span>
          <span className={styles.summaryDetail}>
            {focusedMemory !== undefined ? (
              <span className={focusedApp?.id === 'rest' ? styles.t2 : styles.mono}>
                {focusedApp?.id === 'rest'
                  ? l.text('System and smaller apps')
                  : focusedServer
                    ? l.format('%@ of RAM · CPU %@', shareOfRAM(focusedMemory), `${focusedServer.cpu}%`)
                    : l.format('%@ of RAM', shareOfRAM(focusedMemory))}
              </span>
            ) : cleaning ? (
              <span className={styles.t2}>
                {chosen.length ? l.format('freed by stopping %d', chosen.length) : l.text('Pick servers to stop')}
              </span>
            ) : (
              <button
                type="button"
                className={styles.cpuToggle}
                onClick={() => setCpuAll((all) => !all)}
                title={l.text(
                  cpuAll ? 'Whole Mac. Click for servers only.' : 'Dev servers, as a share of the whole Mac. Click for all.',
                )}
              >
                <span className={styles.t3}>{l.text(cpuAll ? 'CPU (all)' : 'CPU (servers)')}</span>
                <span className={cx(styles.mono, styles.t2)}>{cpuAll ? cpu + 18 : cpu}%</span>
              </button>
            )}
          </span>
        </div>

        <div className={styles.shareBar} aria-label="Mac memory usage">
          {demo.running.map((s) => (
            <button
              key={s.port}
              type="button"
              className={styles.segment}
              style={{ flexGrow: s.memory, color: portColor(s.port) }}
              data-raised
              data-focused={activePort === s.port}
              data-dim={
                (activePort !== null && activePort !== s.port) ||
                (cleaning && !demo.selected.includes(s.port) && activePort !== s.port)
              }
              aria-label={`${s.name} :${s.port} · ${formatMemory(s.memory)}`}
              aria-pressed={cleaning ? demo.selected.includes(s.port) : undefined}
              {...hover(s.port)}
              onClick={() => activate(s.port)}
            />
          ))}
          {OTHER_APPS.map((app) => (
            <span
              key={app.id}
              className={styles.segment}
              style={{ flexGrow: app.memory }}
              tabIndex={0}
              role="img"
              aria-label={
                app.id === 'rest'
                  ? l.format('Everything else · %@', formatMemory(app.memory))
                  : `${app.name} · ${formatMemory(app.memory)}`
              }
              data-focused={focus === app.id}
              {...hover(app.id)}
            />
          ))}
          <span className={styles.free} style={{ flexGrow: free }} title={l.format('Free · %@', formatMemory(free))} />
        </div>

        <div className={styles.legend}>
          <span>
            <i data-servers />
            {l.text('Servers')} <b>{formatTotal(total)}</b>
          </span>
          <span>
            <i />
            {l.text('Other apps')} <b>{formatTotal(OTHER_MEMORY)}</b>
          </span>
          <span>
            <i data-free />
            {l.text('Free')} <b>{l.format('%@ of %@', formatTotal(free).split(' ')[0], '16 GB')}</b>
          </span>
        </div>
      </div>

      <div className={cx(styles.section, styles.rows)}>
        {!demo.running.length && (
          <div className={styles.empty}>
            <PortoMark size={48} />
            <span className={styles.t2}>{l.text('Nothing listening')}</span>
            <span className={cx(styles.caption, styles.t3)}>
              {l.format('Dev servers on ports %d–%d show up here.', 3000, 65535)}
            </span>
          </div>
        )}
        {demo.running.map((s) => {
          const lines = s.lines(l)
          const color = portColor(s.port)
          return (
            <div
              key={s.port}
              role="button"
              tabIndex={0}
              className={styles.row}
              data-dim={s.status === 'idle' || (focus !== null && focus !== s.port)}
              data-focused={focus === s.port}
              data-cleaning={cleaning}
              aria-pressed={cleaning ? demo.selected.includes(s.port) : undefined}
              aria-label={`${cleaning ? 'Select' : 'View'} ${s.branch} on port ${s.port}`}
              onMouseEnter={() => setHoveredRow(s.port)}
              onMouseLeave={() => setHoveredRow(null)}
              onClick={() => activate(s.port)}
              onKeyDown={(event) => {
                if (event.target === event.currentTarget && (event.key === 'Enter' || event.key === ' ')) {
                  event.preventDefault()
                  activate(s.port)
                }
              }}
            >
              {cleaning && (
                <span className={styles.checkbox} data-checked={demo.selected.includes(s.port)} aria-hidden>
                  <svg width="10" height="10" viewBox="0 0 10 10">
                    <path d="M2 5.2 4.1 7.3 8 2.8" fill="none" stroke="#0B0D12" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" />
                  </svg>
                </span>
              )}
              <span className={styles.portLabel}>
                <Colon state={s.status} color={color} />
                <span className={styles.port} style={{ color }}>
                  {s.port}
                </span>
              </span>
              <span className={styles.rowMain}>
                <span className={styles.rowName} title={s.branch}>
                  {s.branch.replaceAll('-', ' ')}
                </span>
                <span className={styles.rowSub} style={{ color: s.context.tone === 'amber' ? AMBER : '#EBEBF599' }}>
                  {cleaning && s.cleanUp ? REASON_ICONS[s.cleanUp.reason] : <AgentIcon agent={s.context.agent} />}
                  <span className={styles.ellipsis}>
                    {flash === s.port ? `Opened localhost:${s.port}` : cleaning && s.cleanUp ? lines.note : lines.context}
                  </span>
                </span>
              </span>
              <svg className={styles.spark} width="40" height="18" viewBox="0 0 44 18" aria-hidden>
                <path
                  d={s.spark}
                  fill="none"
                  stroke={s.status === 'amber' ? AMBER : `rgb(245 245 247 / ${s.status === 'idle' ? 50 : 70}%)`}
                  strokeWidth={s.status === 'amber' ? 1.5 : 1.25}
                  strokeLinecap="round"
                  strokeLinejoin="round"
                  strokeDasharray={s.status === 'idle' ? '2 3' : undefined}
                />
              </svg>
              {!cleaning && (
                <span className={styles.rowActions}>
                  <button
                    type="button"
                    className={styles.rowAction}
                    aria-label={l.text('Open in browser')}
                    onClick={(event) => {
                      event.stopPropagation()
                      trigger(s.port)
                    }}
                  >
                    <OpenIcon />
                  </button>
                  <button
                    type="button"
                    className={styles.rowAction}
                    aria-label={l.text('Stop')}
                    onClick={(event) => {
                      event.stopPropagation()
                      demo.stop([s.port])
                    }}
                  >
                    <svg width="12" height="12" viewBox="0 0 12 12" aria-hidden>
                      <rect x="2.5" y="2.5" width="7" height="7" rx="1.5" fill="rgb(245 245 247 / 80%)" />
                    </svg>
                  </button>
                </span>
              )}
              <span className={styles.rowMemory} style={{ color: s.status === 'amber' ? AMBER : undefined }}>
                {formatMemory(s.memory)}
              </span>
            </div>
          )
        })}
      </div>

      {!demo.running.length ? (
        <div className={cx(styles.section, styles.actions)}>
          <button type="button" className={styles.primary} onClick={demo.restartAll}>
            Start the demo servers again
          </button>
        </div>
      ) : cleaning ? (
        <div className={cx(styles.section, styles.actions)}>
          <button type="button" className={styles.secondary} onClick={() => demo.go({ name: 'list' }, -1)}>
            {l.text('Cancel')}
          </button>
          <button
            type="button"
            className={cx(styles.primary, styles.destructive)}
            disabled={!chosen.length}
            onClick={() => {
              demo.stop(chosen.map((s) => s.port))
              demo.go({ name: 'list' }, -1)
            }}
          >
            {chosen.length
              ? l.format('Stop %d %@ · free %@', chosen.length, l.counted('server', 'servers', chosen.length), formatMemory(freed))
              : l.text('Stop servers')}
          </button>
        </div>
      ) : (
        <div className={cx(styles.section, styles.footer)}>
          <button type="button" className={styles.chip} onClick={() => demo.go({ name: 'cleanUp' }, 1)}>
            <svg width="14" height="14" viewBox="0 0 14 14" aria-hidden>
              <path d="M8.5 1.5 6 7M3 8.5h7l.8 4H2.2L3 8.5Z" fill="none" stroke="#F5F5F7" strokeWidth="1.3" strokeLinecap="round" strokeLinejoin="round" />
              <path d="M5 10.5v2M7.5 10.5v2" fill="none" stroke="#F5F5F7" strokeWidth="1.1" strokeLinecap="round" />
            </svg>
            <span className={styles.title}>{l.text('Clean up')}</span>
            {cleanUpCount > 0 && <span className={styles.chipCount}>{cleanUpCount}</span>}
          </button>
          <GearIcon />
        </div>
      )}
    </>
  )
}

function GearIcon() {
  const stroke = 'rgb(235 235 245 / 70%)'
  return (
    <svg width="16" height="16" viewBox="0 0 24 24" aria-hidden>
      <path
        d="M12.22 2h-.44a2 2 0 0 0-2 2v.18a2 2 0 0 1-1 1.73l-.43.25a2 2 0 0 1-2 0l-.15-.08a2 2 0 0 0-2.73.73l-.22.38a2 2 0 0 0 .73 2.73l.15.1a2 2 0 0 1 1 1.72v.51a2 2 0 0 1-1 1.74l-.15.09a2 2 0 0 0-.73 2.73l.22.38a2 2 0 0 0 2.73.73l.15-.08a2 2 0 0 1 2 0l.43.25a2 2 0 0 1 1 1.73V20a2 2 0 0 0 2 2h.44a2 2 0 0 0 2-2v-.18a2 2 0 0 1 1-1.73l.43-.25a2 2 0 0 1 2 0l.15.08a2 2 0 0 0 2.73-.73l.22-.39a2 2 0 0 0-.73-2.73l-.15-.08a2 2 0 0 1-1-1.74v-.5a2 2 0 0 1 1-1.74l.15-.09a2 2 0 0 0 .73-2.73l-.22-.38a2 2 0 0 0-2.73-.73l-.15.08a2 2 0 0 1-2 0l-.43-.25a2 2 0 0 1-1-1.73V4a2 2 0 0 0-2-2z"
        fill="none"
        stroke={stroke}
        strokeWidth="1.9"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
      <circle cx="12" cy="12" r="3" fill="none" stroke={stroke} strokeWidth="1.9" />
    </svg>
  )
}

// Why Clean up suggests a server: a deleted worktree, idle time, or a leak (never preselected).
const reasonStroke = 'rgb(235 235 245 / 60%)'
const REASON_ICONS = {
  deleted: (
    <svg width="11" height="11" viewBox="0 0 12 12" aria-hidden>
      <path
        d="M1.5 3.5c0-.6.4-1 1-1h2.3l1 1.2h3.7c.6 0 1 .4 1 1V9c0 .6-.4 1-1 1h-7c-.6 0-1-.4-1-1V3.5Z"
        fill="none"
        stroke={reasonStroke}
        strokeWidth="1.1"
      />
      <path d="M4.5 6.2h3" fill="none" stroke={reasonStroke} strokeWidth="1.1" strokeLinecap="round" />
    </svg>
  ),
  idle: (
    <svg width="11" height="11" viewBox="0 0 12 12" aria-hidden>
      <circle cx="6" cy="6" r="4.5" fill="none" stroke={reasonStroke} strokeWidth="1.1" />
      <path d="M6 3.6V6l1.6 1" fill="none" stroke={reasonStroke} strokeWidth="1.1" strokeLinecap="round" />
    </svg>
  ),
  leaking: (
    <svg width="11" height="11" viewBox="0 0 12 12" aria-hidden>
      <path d="M1.5 9 4.5 6l2 2 4-4.5M7.5 3.5h3v3" fill="none" stroke={AMBER} strokeWidth="1.2" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  ),
}
