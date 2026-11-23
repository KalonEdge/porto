'use client'

import { useEffect, useRef, useState } from 'react'
import { GET_IT, SECTIONS, TERMINAL, TRANSLATIONS, photo } from '@/lib/sections'
import { Popover } from '../demo/Popover'
import { useDemo } from '../demo/useDemo'
import { TerminalWindow } from '../terminal/TerminalWindow'
import { Brand } from './Brand'
import { DotMatrix } from './DotMatrix'
import { useHeadlineLanguage } from './LanguageHeadline'
import { SectionCopy } from './SectionCopy'
import styles from './landing.module.css'

function StandalonePopover({ section, zoom }: { section: number; zoom: number }) {
  const demo = useDemo(section)
  const language = useHeadlineLanguage()
  return (
    <div style={{ zoom }}>
      <Popover demo={demo} language={section === TRANSLATIONS ? language : 'en'} />
    </div>
  )
}

/**
 * Below ~900px wide the laptop would be too small to read, so each section stacks
 * its copy above a working demo, set on that section's wallpaper.
 */
export function Stacked({ stars }: { stars: number | null }) {
  const cardRef = useRef<HTMLDivElement>(null)
  const [zoom, setZoom] = useState(1)

  useEffect(() => {
    const card = cardRef.current
    if (!card) return
    const observer = new ResizeObserver(([entry]) => setZoom(Math.min(1, (entry.contentRect.width - 32) / 400)))
    observer.observe(card)
    return () => observer.disconnect()
  }, [])

  return (
    <div className={styles.stacked}>
      <Brand />
      {SECTIONS.map((section, index) => (
        <section key={section.id} className={styles.stackedSection}>
          <SectionCopy index={index} stars={stars} />
          <div
            ref={index === 0 ? cardRef : undefined}
            className={styles.peek}
            style={{
              // The Languages section has no desktop picture of its own, so it shows its room.
              backgroundImage: `linear-gradient(#05080c33, #05080c33), ${index === TRANSLATIONS ? photo('scenes', section.scene) : photo('wallpapers', section.scene)}`,
            }}
          >
            {index === GET_IT ? (
              <DotMatrix size={160} />
            ) : index === TERMINAL ? (
              <div style={{ zoom: Math.min(1, zoom * 0.8) }}>
                <TerminalWindow />
              </div>
            ) : (
              <StandalonePopover section={index} zoom={zoom} />
            )}
          </div>
        </section>
      ))}
    </div>
  )
}
