'use client'

import { SITE_NAME } from '@/lib/site'
import { PortoMark } from '../icons'
import styles from './landing.module.css'

/** The mark and name. Dark over the one room whose wall is light. */
export function Brand({ dark = false }: { dark?: boolean }) {
  return (
    <a className={styles.brand} data-dark={dark} href="#" onClick={() => window.scrollTo({ top: 0 })}>
      <PortoMark size={30} state="currentColor" />
      {SITE_NAME}
    </a>
  )
}
