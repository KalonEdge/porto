'use client'

import { useEffect, useState } from 'react'

/**
 * Which sections' photos to load. The first two and the neighbours of the one on
 * screen load straight away; the rest follow once the page is idle, so scrolling
 * never reveals an empty room but the first paint only waits for what it shows.
 */
export function usePhotos(active: number, count: number) {
  const [ready, setReady] = useState(() => new Set([0, 1]))

  const nearby = [active - 1, active, active + 1].filter((index) => index >= 0 && index < count)
  if (nearby.some((index) => !ready.has(index))) setReady(new Set([...ready, ...nearby]))

  useEffect(() => {
    let cancelled = false
    const loadAll = () => !cancelled && setReady(new Set(Array.from({ length: count }, (_, index) => index)))
    const idle = () =>
      'requestIdleCallback' in window ? window.requestIdleCallback(loadAll, { timeout: 2000 }) : setTimeout(loadAll, 300)
    if (document.readyState === 'complete') idle()
    else window.addEventListener('load', idle, { once: true })
    return () => {
      cancelled = true
      window.removeEventListener('load', idle)
    }
  }, [count])

  return (index: number) => ready.has(index)
}
