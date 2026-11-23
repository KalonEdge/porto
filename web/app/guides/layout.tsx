import type { ReactNode } from 'react'
import { Footer, Header } from './SiteChrome'
import styles from './guides.module.css'

export default function GuidesLayout({ children }: { children: ReactNode }) {
  return (
    <div className={styles.page}>
      <Header />
      <main className={styles.main}>{children}</main>
      <Footer />
    </div>
  )
}
