'use client'

import { useEffect, useState, useSyncExternalStore } from 'react'
import { GITHUB_REPO } from '@/lib/site'
import { Desk } from './Desk'
import { Footer } from './Footer'
import { Stacked } from './Stacked'
import styles from './landing.module.css'

const SMALL = '(max-width: 899px), (max-aspect-ratio: 1/1)'

/**
 * Which layout fits the window. The server renders both and CSS shows the right
 * one; once hydrated only that one stays mounted, so the hidden layout's demos,
 * timers and animations never run.
 */
function useLayout() {
  return useSyncExternalStore(
    (onChange) => {
      const query = window.matchMedia(SMALL)
      query.addEventListener('change', onChange)
      return () => query.removeEventListener('change', onChange)
    },
    () => (window.matchMedia(SMALL).matches ? 'small' : 'desk'),
    () => null,
  )
}

const STARS_KEY = `stars:${GITHUB_REPO}`

/** The repository's star count, cached for the session to spare GitHub's rate limit. */
function useGitHubStars() {
  const [stars, setStars] = useState<number | null>(null)
  useEffect(() => {
    try {
      const cached = sessionStorage.getItem(STARS_KEY)
      if (cached !== null) return setStars(Number(cached))
    } catch {}
    const controller = new AbortController()
    fetch(`https://api.github.com/repos/${GITHUB_REPO}`, { signal: controller.signal })
      .then((response) => (response.ok ? response.json() : null))
      .then((data) => {
        if (typeof data?.stargazers_count !== 'number') return
        setStars(data.stargazers_count)
        try {
          sessionStorage.setItem(STARS_KEY, String(data.stargazers_count))
        } catch {}
      })
      .catch(() => {})
    return () => controller.abort()
  }, [])
  return stars
}

export function Landing() {
  const stars = useGitHubStars()
  const layout = useLayout()
  return (
    <main className={styles.landing}>
      {layout !== 'small' && (
        <div className={styles.desk}>
          <Desk stars={stars} />
        </div>
      )}
      {layout !== 'desk' && (
        <div className={styles.small}>
          <Stacked stars={stars} />
        </div>
      )}
      <Footer />
    </main>
  )
}
