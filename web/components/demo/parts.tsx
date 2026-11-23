'use client'

import { useCallback, useEffect, useRef, useState } from 'react'
import { BackIcon } from '../icons'
import styles from './popover.module.css'

/** Title row shared by every page: an optional back button and a centred title. */
export function Header({ title, onBack, backLabel }: { title: string; onBack?: () => void; backLabel?: string }) {
  return (
    <div className={styles.titleRow}>
      <span className={styles.title}>{title}</span>
      {onBack && (
        <button type="button" className={styles.back} onClick={onBack} aria-label={backLabel}>
          <BackIcon />
        </button>
      )}
    </div>
  )
}

/** Brief confirmation on buttons that would open something outside the demo. */
export function useFlash() {
  const [flash, setFlash] = useState<string | null>(null)
  const timer = useRef<ReturnType<typeof setTimeout>>(undefined)
  useEffect(() => () => clearTimeout(timer.current), [])
  const trigger = useCallback((id: string) => {
    setFlash(id)
    clearTimeout(timer.current)
    timer.current = setTimeout(() => setFlash(null), 1400)
  }, [])
  return [flash, trigger] as const
}
