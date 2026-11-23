'use client'

import { useEffect, useRef, useSyncExternalStore } from 'react'
import type { LanguageCode } from '@/lib/i18n'
import styles from './landing.module.css'

const HEADLINES: { language: LanguageCode; text: string }[] = [
  { language: 'en', text: 'Your language.' },
  { language: 'ja', text: 'あなたの言語。' },
  { language: 'de', text: 'Deine Sprache.' },
  { language: 'uk', text: 'Ваша мова.' },
  { language: 'fr', text: 'Votre langue.' },
  { language: 'zh-Hans', text: '你的语言。' },
  { language: 'he', text: 'השפה שלך.' },
  { language: 'es', text: 'Tu idioma.' },
]

// One headline language for the whole page, so the Languages section's popover
// switches language together with the headline above it.
let current = 0
const listeners = new Set<() => void>()
const subscribe = (listener: () => void) => {
  listeners.add(listener)
  return () => listeners.delete(listener)
}
const advance = () => {
  current = (current + 1) % HEADLINES.length
  listeners.forEach((listener) => listener())
}
const useHeadlineIndex = () => useSyncExternalStore(subscribe, () => current, () => 0)

export const useHeadlineLanguage = () => HEADLINES[useHeadlineIndex()].language

/** "Your language." cycling through the app's languages while it's on screen. */
export function LanguageHeadline() {
  const ref = useRef<HTMLHeadingElement>(null)
  const headline = HEADLINES[useHeadlineIndex()]

  useEffect(() => {
    const element = ref.current
    if (!element) return
    const motion = window.matchMedia('(prefers-reduced-motion: reduce)')
    let visible = false
    let timer: ReturnType<typeof setInterval> | undefined
    const update = () => {
      clearInterval(timer)
      if (visible && !document.hidden && !motion.matches) timer = setInterval(advance, 2800)
    }
    const observer = new IntersectionObserver(
      ([entry]) => {
        visible = entry.isIntersecting
        update()
      },
      { threshold: 0.5 },
    )
    observer.observe(element)
    document.addEventListener('visibilitychange', update)
    motion.addEventListener('change', update)
    return () => {
      clearInterval(timer)
      observer.disconnect()
      document.removeEventListener('visibilitychange', update)
      motion.removeEventListener('change', update)
    }
  }, [])

  return (
    <h2 ref={ref} className={`${styles.headline} ${styles.languageHeadline}`} aria-label="Your language.">
      <span key={headline.language} lang={headline.language} dir="auto" aria-hidden="true">
        {headline.text}
      </span>
    </h2>
  )
}
