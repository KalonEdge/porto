'use client'

import { Popover } from '@/components/demo/Popover'
import { useDemo } from '@/components/demo/useDemo'
import { BatteryIcon, PortoMark, WifiIcon } from '@/components/icons'
import { SITE_NAME } from '@/lib/site'
import styles from './og.module.css'

// The app icon's ring, clockwise from the top, in its sky → pink sweep.
const RING: [number, number, string][] = [
  [0, 1, '#6ec7ed'], [0, 2, '#72b9ee'], [0, 3, '#7aa4f1'], [1, 4, '#9a9af1'], [2, 4, '#b599f0'], [3, 4, '#c79ef1'],
  [4, 3, '#d9a3f2'], [4, 2, '#e29fe3'], [4, 1, '#eb9cd4'], [3, 0, '#c2b0da'], [2, 0, '#7ddbe0'], [1, 0, '#75d1e7'],
]

function RingMark() {
  return (
    <div className={styles.ring} aria-hidden>
      {Array.from({ length: 25 }, (_, index) => {
        const row = Math.floor(index / 5)
        const column = index % 5
        const lit = RING.find(([r, c]) => r === row && c === column)
        const centre = row === 2 && column === 2
        const color = centre ? '#f5f5f7' : lit?.[2]
        return (
          <span
            key={index}
            style={color ? { background: color, boxShadow: `0 0 8px ${color}99` } : undefined}
          />
        )
      })}
    </div>
  )
}

export function OgCard() {
  const demo = useDemo(0)
  return (
    <main className={styles.card}>
      <div className={styles.copy}>
        <RingMark />
        <h1 className={styles.name}>{SITE_NAME}</h1>
        <p className={styles.tagline}>Every dev server on your Mac, in the menu bar.</p>
      </div>
      <div className={styles.menuBar}>
        <span className={styles.statusItem}>
          <PortoMark state="rest" />
          <span className={styles.count}>{demo.running.length}</span>
        </span>
        <WifiIcon />
        <BatteryIcon />
        <span>9:41 AM</span>
      </div>
      <div className={styles.popover}>
        <Popover demo={demo} />
      </div>
    </main>
  )
}
