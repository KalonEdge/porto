'use client'

import { useEffect, useRef, useState } from 'react'
import { AUTHOR, DOWNLOAD_URL, FOOTER_LINK, GITHUB_URL, SITE_NAME } from '@/lib/site'
import { Popover } from '@/components/demo/Popover'
import { useDemo } from '@/components/demo/useDemo'
import { AppleIcon, PortoMark } from '@/components/icons'
import styles from './guides.module.css'

// Header and footer for the written pages.

export function DownloadButton() {
  return (
    <a className={styles.download} href={DOWNLOAD_URL} download>
      <AppleIcon />
      <span>
        Download<span className={styles.forMac}> for macOS</span>
      </span>
    </a>
  )
}

/** The landing page's working popover, with sample servers. */
function DemoPopover() {
  const demo = useDemo(0)
  return <Popover demo={demo} />
}

/** "Try Porto": the demo popover, dropped down from the header like the real one from the menu bar. */
function TryIt() {
  const [open, setOpen] = useState(false)
  // Mounted on first open, then kept, so the demo remembers what you stopped.
  const [mounted, setMounted] = useState(false)
  const [zoom, setZoom] = useState(1)
  const ref = useRef<HTMLDivElement>(null)

  useEffect(() => {
    if (!open) return
    const fit = () => setZoom(Math.min(1, (window.innerWidth - 32) / 400))
    const onPointer = (event: PointerEvent) => {
      if (!ref.current?.contains(event.target as Node)) setOpen(false)
    }
    const onKey = (event: KeyboardEvent) => event.key === 'Escape' && setOpen(false)
    fit()
    window.addEventListener('resize', fit)
    document.addEventListener('pointerdown', onPointer)
    document.addEventListener('keydown', onKey)
    return () => {
      window.removeEventListener('resize', fit)
      document.removeEventListener('pointerdown', onPointer)
      document.removeEventListener('keydown', onKey)
    }
  }, [open])

  return (
    <div ref={ref} className={styles.tryIt}>
      <button
        type="button"
        className={styles.tryButton}
        onClick={() => {
          setMounted(true)
          setOpen(!open)
        }}
        aria-expanded={open}
        aria-controls="demo-popover"
      >
        Try {SITE_NAME}
      </button>
      <div id="demo-popover" className={styles.demoPanel} data-open={open} role="dialog" aria-label={`${SITE_NAME} demo`}>
        <p className={styles.demoLabel}>
          <span className={styles.demoBadge}>Demo</span>
          Sample servers, not your Mac. Nothing here touches real processes.
        </p>
        <div className={styles.demoApp} style={{ zoom }}>
          {mounted && <DemoPopover />}
        </div>
      </div>
    </div>
  )
}

export function Header() {
  return (
    <header className={styles.headerBar}>
      <div className={styles.header}>
        <a className={styles.brand} href="/">
          <PortoMark size={22} state="currentColor" />
          {SITE_NAME}
        </a>
        <nav className={styles.nav} aria-label="Main">
          <a className={styles.navLink} href="/guides">
            Guides
          </a>
          <a className={styles.navLink} href={GITHUB_URL} target="_blank" rel="noopener noreferrer">
            GitHub
          </a>
          <TryIt />
          <DownloadButton />
        </nav>
      </div>
    </header>
  )
}

export function Footer() {
  return (
    <footer className={styles.footer}>
      <div className={styles.footerInner}>
        <span className={styles.footerBrand}>
          <PortoMark size={18} />
          {SITE_NAME}
        </span>
        <span className={styles.footerMeta}>Free and open source · Made by {AUTHOR.name}</span>
        <nav className={styles.footerLinks} aria-label="Footer">
          <a href="/">Home</a>
          <a href="/guides">Guides</a>
          <a href={DOWNLOAD_URL} download>
            Download
          </a>
          <a href={GITHUB_URL} target="_blank" rel="noopener noreferrer">
            GitHub <span aria-hidden="true">↗</span>
          </a>
          <a href={FOOTER_LINK.href} target="_blank" rel="noopener noreferrer">
            {FOOTER_LINK.label} <span aria-hidden="true">↗</span>
          </a>
        </nav>
      </div>
    </footer>
  )
}
