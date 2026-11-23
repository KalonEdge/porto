import type { CSSProperties } from 'react'
import { AMBER, type Agent, type Status } from '@/lib/demo'
import { isLit } from '@/lib/glyphs'

const CENTRES = [1.8, 5.4, 9, 12.6, 16.2]
const tint = (alpha: number) => `rgb(235 235 245 / ${alpha}%)`

export type MarkState = 'rest' | 'alert' | 'currentColor'

/**
 * Porto's porthole mark on its 5×5 grid. At rest the ring and centre are lit;
 * on alert the porthole turns amber. 'currentColor' draws it in the text
 * colour, unlit dots at a quarter strength.
 */
export function PortoMark({ state = 'rest', size = 18 }: { state?: MarkState; size?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 18 18" aria-hidden style={{ flexShrink: 0 }}>
      {CENTRES.map((cy, row) =>
        CENTRES.map((cx, column) => {
          const lit = isLit('porthole', row, column)
          if (state === 'currentColor') {
            return <circle key={`${column}-${row}`} cx={cx} cy={cy} r={1.4} fill="currentColor" fillOpacity={lit ? 1 : 0.25} />
          }
          const fill = lit ? (state === 'alert' ? AMBER : '#FFFFFF') : '#FFFFFF40'
          return <circle key={`${column}-${row}`} cx={cx} cy={cy} r={1.4} fill={fill} />
        }),
      )}
    </svg>
  )
}

/** The two status dots in front of every port: solid, glowing amber, or an idle outline. */
export function Colon({ state = 'on', dot = 4, gap = 3, color }: { state?: Status; dot?: number; gap?: number; color?: string }) {
  const style: CSSProperties = { width: dot, height: dot, borderRadius: dot, flexShrink: 0 }
  if (state === 'on') style.backgroundColor = color ?? '#F5F5F7'
  if (state === 'amber') {
    style.backgroundColor = color ?? AMBER
    style.boxShadow = `${color ?? AMBER} 0 0 5px`
  }
  if (state === 'idle') style.boxShadow = `${color ?? '#EBEBF580'} 0 0 0 1.1px inset`
  return (
    <span style={{ display: 'flex', flexDirection: 'column', gap, width: dot === 4 ? 9 : undefined, flexShrink: 0 }}>
      <span style={style} />
      <span style={style} />
    </span>
  )
}

type Stroke = { color?: string; size?: number; width?: number }

export function ClaudeIcon({ color = tint(75), size = 12, width = 1.4 }: Stroke) {
  return (
    <svg width={size} height={size} viewBox="0 0 12 12" aria-hidden style={{ flexShrink: 0 }}>
      <path d="M6 1v10M1 6h10M2.5 2.5l7 7M9.5 2.5l-7 7" fill="none" stroke={color} strokeWidth={width} strokeLinecap="round" />
    </svg>
  )
}

export function CodexIcon({ color = tint(75), size = 12, width = 1.2 }: Stroke) {
  return (
    <svg width={size} height={size} viewBox="0 0 12 12" aria-hidden style={{ flexShrink: 0 }}>
      <rect x="1" y="1.5" width="10" height="9" rx="2.5" fill="none" stroke={color} strokeWidth={width} />
      <path d="M3.5 5 5 6.2 3.5 7.4M6.2 7.6h2.3" fill="none" stroke={color} strokeWidth={width} strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  )
}

export function AgentIcon({ agent }: { agent?: Agent }) {
  if (agent === 'claude') return <ClaudeIcon />
  if (agent === 'codex') return <CodexIcon />
  return null
}

export function ConductorIcon() {
  return (
    <svg width="14" height="14" viewBox="0 0 12 12" aria-hidden style={{ flexShrink: 0 }}>
      {[1.5, 6.5].flatMap((y) =>
        [1.5, 6.5].map((x) => (
          <rect key={`${x}-${y}`} x={x} y={y} width="4" height="4" rx="1" fill="none" stroke="#F5F5F7" strokeWidth="1.1" />
        )),
      )}
    </svg>
  )
}

export function VercelIcon({ fill = '#FFFFFF', width = 12, height = 11 }: { fill?: string; width?: number; height?: number }) {
  return (
    <svg width={width} height={height} viewBox="0 0 12 11" aria-hidden style={{ flexShrink: 0 }}>
      <path d="M6 0.5 11.5 10.5H0.5Z" fill={fill} />
    </svg>
  )
}

export function OpenIcon({ color = '#F5F5F7' }: { color?: string }) {
  return (
    <svg width="12" height="12" viewBox="0 0 12 12" aria-hidden style={{ flexShrink: 0 }}>
      <path d="M4 2.5h5.5V8M9.5 2.5 2.5 9.5" fill="none" stroke={color} strokeWidth="1.4" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  )
}

export function BackIcon() {
  return (
    <svg width="14" height="14" viewBox="0 0 14 14" aria-hidden>
      <path d="M8.5 3 4.5 7l4 4" fill="none" stroke={tint(60)} strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  )
}

export function Chevron({ direction }: { direction: 'down' | 'right' }) {
  return (
    <svg width="12" height="12" viewBox="0 0 12 12" aria-hidden style={{ flexShrink: 0 }}>
      <path
        d={direction === 'down' ? 'M3 4.5 6 7.5l3-3' : 'M4.5 3 7.5 6l-3 3'}
        fill="none"
        stroke={tint(50)}
        strokeWidth="1.4"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  )
}

export function AppleIcon() {
  return (
    <svg width="14" height="16" viewBox="0 0 14 16" aria-hidden style={{ flexShrink: 0 }}>
      <path
        d="M11.6 8.5c0-2 1.6-2.9 1.7-3-.9-1.3-2.3-1.5-2.8-1.5-1.2-.1-2.3.7-2.9.7-.6 0-1.5-.7-2.5-.7C3.8 4 2.6 4.8 2 6c-1.4 2.4-.4 6 1 7.9.6.9 1.4 2 2.4 1.9 1-.1 1.3-.6 2.5-.6s1.5.6 2.5.6c1 0 1.7-.9 2.3-1.9.7-1.1 1-2.1 1-2.2 0 0-2-.8-2.1-3.2ZM9.7 2.6c.5-.7.9-1.6.8-2.6-.8 0-1.8.5-2.4 1.2-.5.6-1 1.6-.8 2.5.9.1 1.8-.4 2.4-1.1Z"
        fill="currentColor"
      />
    </svg>
  )
}

export function GitHubIcon() {
  return (
    <svg width="15" height="15" viewBox="0 0 16 16" aria-hidden style={{ flexShrink: 0 }}>
      <path
        d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.013 8.013 0 0016 8c0-4.42-3.58-8-8-8z"
        fill="currentColor"
      />
    </svg>
  )
}

export function WifiIcon() {
  return (
    <svg width="17" height="12" viewBox="0 0 17 12" aria-hidden style={{ flexShrink: 0 }}>
      <path
        d="M8.5 2.2c2.3 0 4.4.9 6 2.4l1.1-1.1C13.7 1.6 11.2.6 8.5.6S3.3 1.6 1.4 3.5l1.1 1.1c1.6-1.5 3.7-2.4 6-2.4Zm0 3.2c1.4 0 2.7.5 3.7 1.4l1.1-1.1C12 4.5 10.3 3.8 8.5 3.8S5 4.5 3.7 5.7l1.1 1.1c1-.9 2.3-1.4 3.7-1.4Zm0 3.2c.6 0 1.1.2 1.5.5L8.5 10.6 7 9.1c.4-.3.9-.5 1.5-.5Z"
        fill="#FFFFFF"
      />
    </svg>
  )
}

export function BatteryIcon() {
  return (
    <svg width="25" height="12" viewBox="0 0 25 12" aria-hidden style={{ flexShrink: 0 }}>
      <rect x="0.5" y="0.5" width="21" height="11" rx="3.5" fill="none" stroke="#FFFFFF80" />
      <rect x="2" y="2" width="15" height="8" rx="2" fill="#FFFFFF" />
      <path d="M23 4v4c.8-.3 1.3-1.1 1.3-2S23.8 4.3 23 4Z" fill="#FFFFFF80" />
    </svg>
  )
}
