'use client'

import { useEffect, useState } from 'react'
import { GLYPHS, type Glyph } from '@/lib/glyphs'
import styles from './landing.module.css'

// The mark as a tiny display: the porthole at rest, spelling the name, then
// everything else the grid can say in the menu bar.
const SEQUENCE: [glyph: Glyph, hold: number][] = [
  ['porthole', 1600],
  ['P', 700],
  ['O', 700],
  ['R', 700],
  ['T', 700],
  ['O', 700],
  ['porthole', 1200],
  ['line', 900],
  ['bars', 900],
  ['count', 900],
  ['leak', 900],
  ['alert', 1000],
  ['question', 800],
  ['bang', 800],
  ['questionBang', 1000],
]

const COLORS = { '#': '#F5F5F7', a: '#FFB224', '.': '#F5F5F71F' } as const

export function DotMatrix({ size = 216, playing = true }: { size?: number; playing?: boolean }) {
  const [step, setStep] = useState(0)

  // Stopping rewinds, so the next visit starts from the porthole again.
  const [wasPlaying, setWasPlaying] = useState(playing)
  if (wasPlaying !== playing) {
    setWasPlaying(playing)
    if (!playing) setStep(0)
  }

  useEffect(() => {
    if (!playing || window.matchMedia('(prefers-reduced-motion: reduce)').matches) return
    const timer = setTimeout(() => setStep((current) => (current + 1) % SEQUENCE.length), SEQUENCE[step][1])
    return () => clearTimeout(timer)
  }, [step, playing])

  const rows = GLYPHS[SEQUENCE[step][0]]

  return (
    <svg className={styles.dotMatrix} width={size} height={size} viewBox="0 0 216 216" aria-hidden>
      {rows.map((row, y) =>
        [...row].map((cell, x) => (
          <circle
            key={`${x}-${y}`}
            cx={20 + x * 44}
            cy={20 + y * 44}
            r={14}
            data-lit={cell !== '.'}
            style={{ fill: COLORS[cell as keyof typeof COLORS], transitionDelay: `${x * 45}ms` }}
          />
        )),
      )}
    </svg>
  )
}
