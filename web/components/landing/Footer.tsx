'use client'

import { useEffect, useState } from 'react'
import { AUTHOR, DOWNLOAD_URL, FOOTER_LINK, GITHUB_URL, SITE_NAME } from '@/lib/site'
import { PortoMark } from '../icons'
import styles from './landing.module.css'

/** Slides up over the page once you reach the bottom, without adding any height. */
export function Footer() {
  const [visible, setVisible] = useState(false)

  useEffect(() => {
    const update = () => setVisible(window.scrollY + window.innerHeight >= document.documentElement.scrollHeight - 4)
    update()
    window.addEventListener('scroll', update, { passive: true })
    window.addEventListener('resize', update)
    // The page's height changes without a scroll when the layout switches between desk and phone.
    const observer = new ResizeObserver(update)
    observer.observe(document.body)
    return () => {
      window.removeEventListener('scroll', update)
      window.removeEventListener('resize', update)
      observer.disconnect()
    }
  }, [])

  return (
    <footer className={styles.footer} data-visible={visible}>
      <div className={styles.footerInner}>
        <span className={styles.footerBrand}>
          <PortoMark size={22} />
          {SITE_NAME}
        </span>
        <span className={styles.footerMeta}>Free and open source · Made by {AUTHOR.name}</span>
        <nav className={styles.footerLinks} aria-label="Footer">
          <a href={DOWNLOAD_URL} download>
            Download <span aria-hidden="true">↗</span>
          </a>
          <a href="/guides">Guides</a>
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
