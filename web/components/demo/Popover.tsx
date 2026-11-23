'use client'

import { type CSSProperties, type ReactNode, useLayoutEffect, useRef, useState } from 'react'
import { type AppLanguage, translator } from '@/lib/i18n'
import { serverByPort } from '@/lib/demo'
import { DetailView } from './DetailView'
import { ListView } from './ListView'
import type { Demo } from './useDemo'
import styles from './popover.module.css'

/** Keeps the popover's height animating between views, the way a macOS popover resizes. */
function Frame({ children, viewKey }: { children: ReactNode; viewKey: string }) {
  const innerRef = useRef<HTMLDivElement>(null)
  const [height, setHeight] = useState<number>()

  useLayoutEffect(() => {
    const inner = innerRef.current
    if (!inner) return
    const measure = () => setHeight(inner.offsetHeight)
    measure()
    const observer = new ResizeObserver(measure)
    observer.observe(inner)
    return () => observer.disconnect()
  }, [viewKey])

  return (
    <div className={styles.popover} style={{ height }}>
      <div ref={innerRef}>{children}</div>
    </div>
  )
}

export function Popover({ demo, language = 'en' }: { demo: Demo; language?: AppLanguage }) {
  const { view, direction } = demo
  const l = translator(language)
  const key = view.name === 'detail' ? `detail-${view.port}` : demo.running.length ? 'list' : 'empty'

  return (
    <Frame viewKey={key}>
      <div
        key={key}
        className={styles.view}
        style={{ '--dir': direction } as CSSProperties}
        lang={language}
        dir={l.rtl ? 'rtl' : 'ltr'}
      >
        {view.name === 'detail' ? <DetailView demo={demo} server={serverByPort(view.port)} l={l} /> : <ListView demo={demo} l={l} />}
      </div>
    </Frame>
  )
}
