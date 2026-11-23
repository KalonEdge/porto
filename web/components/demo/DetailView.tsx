'use client'

import { type MouseEvent, type ReactNode, useEffect, useState } from 'react'
import type { Translator } from '@/lib/i18n'
import { type Server, cpuBars, formatMemory, memoryChart, portColor } from '@/lib/demo'
import { AgentIcon, Chevron, Colon, OpenIcon, VercelIcon } from '../icons'
import { Header, useFlash } from './parts'
import type { Demo } from './useDemo'
import styles from './popover.module.css'

const cx = (...names: (string | false | undefined)[]) => names.filter(Boolean).join(' ')
const pad = (value: number) => String(value).padStart(2, '0')

/** A server's page: port, controls, info, ten minutes of memory and CPU, processes. */
export function DetailView({ demo, server, l }: { demo: Demo; server: Server; l: Translator }) {
  const [moreInfo, setMoreInfo] = useState(false)
  const [processesOpen, setProcessesOpen] = useState(false)
  const [restarting, setRestarting] = useState(false)
  const [restarted, setRestarted] = useState(false)
  const [flash, trigger] = useFlash()
  // Both charts share one pointer position, as a fraction of their width.
  const [hover, setHover] = useState<number | null>(null)

  const memory = memoryChart(server)
  const bars = cpuBars(server)
  const sample = hover === null ? null : memory.points[Math.round(hover * (memory.points.length - 1))]
  const cpuSample = hover === null ? server.cpu : bars[Math.round(hover * (bars.length - 1))]
  const timestamp = hover === null ? null : `13:${pad(14 + Math.floor(hover * 10))}:${pad(Math.floor(hover * 600) % 60)}`
  const lines = server.lines(l)

  const trackPointer = (event: MouseEvent<SVGSVGElement>) => {
    const bounds = event.currentTarget.getBoundingClientRect()
    setHover(Math.max(0, Math.min(1, (event.clientX - bounds.left) / bounds.width)))
  }

  useEffect(() => {
    if (!restarting) return
    const timer = setTimeout(() => {
      setRestarting(false)
      setRestarted(true)
    }, 900)
    return () => clearTimeout(timer)
  }, [restarting])

  // Session and branch first when an agent started it; otherwise branch and folder.
  const shownInfo: [string, ReactNode][] = server.session
    ? [
        [
          'Session',
          <span key="session" className={styles.infoValue}>
            <AgentIcon agent={server.session.agent} />
            <span className={cx(styles.ellipsis, styles.t1)}>{server.session.title}</span>
            <span style={{ flexGrow: 1 }} />
            <OpenIcon color="rgb(235 235 245 / 60%)" />
          </span>,
        ],
        ['Branch', server.branch],
      ]
    : [
        ['Branch', server.branch],
        ['Folder', server.info[0][1]],
      ]
  const hiddenInfo: [string, string][] = server.info
    .filter(([label]) => !(label === 'Folder' && !server.session) && label !== 'PID' && label !== 'Git')
    .map(([label, value]) => [label, label === 'Workspace' ? `Conductor · ${value}` : value])
  if (server.session) hiddenInfo.push(['Session ID', server.session.id])

  const color = portColor(server.port)

  return (
    <>
      <div className={styles.head}>
        <Header title={server.name} onBack={() => demo.go({ name: 'list' }, -1)} backLabel={l.text('Back')} />
        <div className={styles.display} style={{ justifyContent: 'space-between' }}>
          <span className={styles.display} dir="ltr">
            <Colon state={server.status} color={color} dot={6} gap={6} />
            <span className={styles.big} style={{ color }}>
              {server.port}
            </span>
          </span>
          <span className={styles.display} style={{ gap: 10 }}>
            <span className={styles.t3}>
              {restarting
                ? 'restarting…'
                : l.format('Running for %@', restarted ? l.duration(0) : lines.running)}
            </span>
            <span className={styles.display}>
              <button
                type="button"
                className={styles.control}
                aria-label="Restart"
                disabled={server.status === 'idle' || restarting}
                title={server.status === 'idle' ? 'Working directory no longer exists' : l.text('Restart with the same command')}
                data-spinning={restarting}
                onClick={() => setRestarting(true)}
              >
                <svg width="13" height="13" viewBox="0 0 14 14" aria-hidden>
                  <path d="M11.5 7a4.5 4.5 0 1 1-1.3-3.2" fill="none" stroke="#F5F5F7" strokeWidth="1.4" strokeLinecap="round" />
                  <path d="M10.6 1.6v2.6H8" fill="none" stroke="#F5F5F7" strokeWidth="1.4" strokeLinecap="round" strokeLinejoin="round" />
                </svg>
              </button>
              <button type="button" className={cx(styles.control, styles.stop)} aria-label={l.text('Stop')} onClick={() => demo.stop([server.port])}>
                <svg width="11" height="11" viewBox="0 0 12 12" aria-hidden>
                  <rect x="2" y="2" width="8" height="8" rx="1.8" fill="#FF6961" />
                </svg>
              </button>
            </span>
          </span>
        </div>
      </div>

      <div className={cx(styles.section, styles.info)}>
        {shownInfo.map(([label, value]) => (
          <div key={label} className={styles.infoRow}>
            <span className={styles.infoLabel}>{l.text(label)}</span>
            {typeof value === 'string' ? <span className={cx(styles.ellipsis, styles.t1)}>{value}</span> : value}
          </div>
        ))}
        <div className={styles.collapsible} data-open={moreInfo}>
          <div>
            {hiddenInfo.map(([label, value]) => (
              <div key={label} className={styles.infoRow}>
                <span className={styles.infoLabel}>{l.text(label)}</span>
                <span className={cx(styles.ellipsis, (label === 'PID' || label === 'Command') && styles.mono, styles.t1)}>{value}</span>
              </div>
            ))}
          </div>
        </div>
        <div className={styles.infoRow}>
          <span className={styles.infoLabel} />
          <button type="button" className={styles.infoMore} onClick={() => setMoreInfo((open) => !open)} data-open={moreInfo}>
            {moreInfo ? l.text('Less') : l.format('%d more', hiddenInfo.length)} <Chevron direction="down" />
          </button>
        </div>
      </div>

      <div className={cx(styles.section, styles.chart)}>
        <div className={styles.chartHead}>
          <span className={styles.chartTitle}>
            <span className={styles.t2}>{l.text('Memory')}</span>
            <span className={styles.mono} style={{ fontWeight: 500 }}>
              {formatMemory(sample?.memory ?? server.memory)}
            </span>
          </span>
          <span className={cx(styles.mono, styles.caption, styles.t3)}>{timestamp ?? l.text('10 min')}</span>
        </div>
        <div className={styles.plot}>
          <span className={styles.axis} style={{ height: 56, position: 'relative' }}>
            <span style={{ position: 'absolute', top: memory.limit - 7, color: '#FFB224D9' }}>2 GB</span>
            <span style={{ position: 'absolute', bottom: -6 }}>0</span>
          </span>
          <svg
            width="328"
            height="56"
            viewBox="0 0 328 56"
            role="img"
            aria-label="Memory over the last ten minutes"
            style={{ flexShrink: 0 }}
            onMouseMove={trackPointer}
            onMouseLeave={() => setHover(null)}
          >
            <path d="M0.5 0 V56 M0 55.5 H328" fill="none" stroke="rgb(255 255 255 / 14%)" />
            <path d={`M0 ${memory.limit} H328`} fill="none" stroke="rgb(255 178 36 / 55%)" strokeDasharray="3 3" />
            <path
              className={styles.chartLine}
              d={memory.line}
              fill="none"
              stroke="rgb(245 245 247 / 90%)"
              strokeWidth="1.5"
              strokeLinecap="round"
              strokeLinejoin="round"
              pathLength={1}
            />
            {sample && <path d={`M${sample.x} 0 V56`} stroke="#F5F5F740" />}
            <circle cx={sample?.x ?? 327} cy={sample?.y ?? memory.end} r="3" fill="#F5F5F7" />
          </svg>
        </div>
      </div>

      <div className={styles.chart} style={{ paddingTop: 0 }}>
        <div className={styles.chartHead}>
          <span className={styles.chartTitle}>
            <span className={styles.t2}>CPU</span>
            <span className={styles.mono} style={{ fontWeight: 500 }}>
              {Math.round(cpuSample)}%
            </span>
          </span>
          {timestamp && <span className={cx(styles.mono, styles.caption, styles.t3)}>{timestamp}</span>}
        </div>
        <div className={styles.plot}>
          <span className={styles.axis} style={{ height: 56 }}>
            <span style={{ marginTop: -6 }}>100%</span>
            <span style={{ marginBottom: -6 }}>0</span>
          </span>
          <svg
            width="328"
            height="56"
            viewBox="0 0 328 56"
            role="img"
            aria-label="CPU over the last ten minutes"
            style={{ flexShrink: 0 }}
            onMouseMove={trackPointer}
            onMouseLeave={() => setHover(null)}
          >
            <path d="M0.5 0 V56 M0 55.5 H328" fill="none" stroke="rgb(255 255 255 / 14%)" />
            {bars.map((value, i) => {
              const height = Math.max(0.6, value * 0.56)
              const highlighted = i === Math.round((hover ?? 1) * (bars.length - 1))
              return (
                <rect
                  key={i}
                  className={styles.cpuBar}
                  style={{ animationDelay: `${i * 6}ms` }}
                  x={0.5 + i * 5.4627}
                  y={56 - height}
                  width="3"
                  height={height}
                  rx="1"
                  fill={highlighted ? '#F5F5F7D9' : '#F5F5F752'}
                />
              )
            })}
            {hover !== null && <path d={`M${hover * 328} 0 V56`} stroke="#F5F5F740" />}
          </svg>
        </div>
      </div>

      <div className={styles.section}>
        <button
          type="button"
          className={styles.processes}
          onClick={() => setProcessesOpen((open) => !open)}
          aria-expanded={processesOpen}
          data-open={processesOpen}
        >
          <span className={styles.display} style={{ gap: 4 }}>
            <span className={styles.t2}>{l.text('Processes')}</span>
            <span className={styles.processesChevron}>
              <Chevron direction="right" />
            </span>
          </span>
          <span className={styles.display} style={{ gap: 8 }}>
            <span className={cx(styles.mono, styles.t3)}>{server.processes.length} ·</span>
            <span className={cx(styles.mono, styles.t2)}>{formatMemory(server.memory)}</span>
          </span>
        </button>
        <div className={styles.collapsible} data-open={processesOpen}>
          <div>
            <div className={styles.processList}>
              {server.processes.map((process, index) => (
                <div key={process.command} className={styles.processRow}>
                  <span className={cx(styles.mono, styles.ellipsis, styles.t1)}>
                    {index ? '└ ' : ''}
                    {process.command}
                  </span>
                  <span className={styles.processBar}>
                    <i style={{ width: `${(process.memory / Math.max(...server.processes.map((p) => p.memory))) * 100}%` }} />
                  </span>
                  <span className={cx(styles.mono, styles.t2)}>{formatMemory(process.memory)}</span>
                </div>
              ))}
            </div>
          </div>
        </div>
      </div>

      <div className={cx(styles.section, styles.actions)}>
        <button type="button" className={styles.primary} onClick={() => trigger('open')}>
          {flash === 'open' ? 'Opened in your browser' : l.format('Open localhost:%@', server.port)}
        </button>
        <button type="button" className={styles.secondary} onClick={() => trigger('preview')}>
          <VercelIcon fill="rgb(235 235 245 / 75%)" width={11} height={10} />
          {flash === 'preview' ? 'Opened' : l.text('Preview')}
        </button>
        <button type="button" className={styles.more} aria-label="More">
          <span />
          <span />
          <span />
        </button>
      </div>
    </>
  )
}
