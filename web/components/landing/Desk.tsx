'use client'

import { useCallback, useEffect, useRef, useState } from 'react'
import { SECTIONS, photo } from '@/lib/sections'
import { Brand } from './Brand'
import { Screen } from './Screen'
import { usePhotos } from './usePhotos'
import styles from './landing.module.css'

// Scene geometry, in the 2560×1600 space the room photos and laptop were composed in.
const SCENE = { width: 2560, height: 1600 }
const SCREEN = { x: 624.2, y: 210.02, width: 1310.4, height: 819 }
const LID_TOP = 190
const LID_WIDTH = 1346.8
const LID_GUTTER = 32

const clamp = (value: number, min: number, max: number) => Math.min(Math.max(value, min), max)
const easeInOutCubic = (t: number) => (t < 0.5 ? 4 * t * t * t : 1 - (-2 * t + 2) ** 3 / 2)

// Each section holds still for most of its scroll distance, then moves quickly to the next.
const HOLD = 0.3
const transition = (fraction: number) => easeInOutCubic(clamp((fraction - HOLD) / (1 - 2 * HOLD), 0, 1))

/**
 * Zoom from the viewport's height, so narrowing the window crops the room instead
 * of shrinking the laptop; only shrink once the lid would no longer fit across.
 * Then pan to keep the screen centred without exposing the scene's edges.
 */
function camera(vw: number, vh: number) {
  const fitsAcross = (vw - LID_GUTTER * 2) * (SCREEN.width / LID_WIDTH)
  const target = Math.min(vh * 0.72 * (SCREEN.width / SCREEN.height), 1500, fitsAcross)
  const scale = Math.max(target / SCREEN.width, vw / SCENE.width, vh / SCENE.height)
  const x = clamp(vw / 2 - (SCREEN.x + SCREEN.width / 2) * scale, vw - SCENE.width * scale, 0)
  const y = clamp(vh * 0.49 - (SCREEN.y + SCREEN.height / 2) * scale, vh - SCENE.height * scale, 0)
  return { x, y, scale }
}

/** The laptop on a desk, one room per section, with the page's scroll driving what's on screen. */
export function Desk({ stars }: { stars: number | null }) {
  const trackRef = useRef<HTMLDivElement>(null)
  const stageRef = useRef<HTMLDivElement>(null)
  const sceneRef = useRef<HTMLDivElement>(null)
  const roomRefs = useRef<(HTMLDivElement | null)[]>([])
  const [active, setActive] = useState(0)
  const photoReady = usePhotos(active, SECTIONS.length)

  useEffect(() => {
    const track = trackRef.current
    const stage = stageRef.current
    const scene = sceneRef.current
    if (!track || !stage || !scene) return
    const sections = Array.from(track.querySelectorAll<HTMLElement>('[data-section]'))
    let frame = 0

    const update = () => {
      frame = 0
      const vh = window.innerHeight
      // A hidden or zero-height window has no scroll position to read yet.
      const progress = vh > 0 ? clamp(-track.getBoundingClientRect().top / vh, 0, SECTIONS.length - 1) : 0
      const base = Math.floor(progress)
      const moving = transition(progress - base)
      const eased = base + moving

      // Headlines move on the eased curve. Each section gets its signed (--d) and absolute (--a)
      // distance from the middle; the CSS staggers, fades and blurs its parts from those.
      track.style.setProperty('--p', eased.toFixed(4))
      sections.forEach((section, index) => {
        const distance = eased - index
        section.style.setProperty('--d', distance.toFixed(4))
        section.style.setProperty('--a', Math.abs(distance).toFixed(4))
      })

      // Rooms only cross-fade; the scene itself never moves.
      roomRefs.current.forEach((room, index) => {
        if (room) room.style.opacity = (index <= base ? 1 : index === base + 1 ? moving : 0).toFixed(3)
      })

      setActive(Math.round(progress))
    }
    const layout = () => {
      const view = camera(window.innerWidth, window.innerHeight)
      scene.style.transform = `translate3d(${view.x}px, ${view.y}px, 0) scale(${view.scale})`
      stage.style.setProperty('--lid-top', `${view.y + LID_TOP * view.scale}px`)
      scene.dataset.ready = 'true'
      update()
    }
    const onScroll = () => {
      if (!frame) frame = requestAnimationFrame(update)
    }

    layout()
    window.addEventListener('scroll', onScroll, { passive: true })
    window.addEventListener('resize', layout)
    return () => {
      cancelAnimationFrame(frame)
      window.removeEventListener('scroll', onScroll)
      window.removeEventListener('resize', layout)
    }
  }, [])

  const navigate = useCallback((index: number, instant = false) => {
    const track = trackRef.current
    if (!track) return
    const top = track.getBoundingClientRect().top + window.scrollY + index * window.innerHeight
    const reduce = window.matchMedia('(prefers-reduced-motion: reduce)').matches
    window.scrollTo({ top, behavior: reduce || instant ? 'auto' : 'smooth' })
  }, [])

  // Links like /#terminal scroll the page to that section.
  useEffect(() => {
    const follow = (instant: boolean) => {
      const index = SECTIONS.findIndex((section) => `#${section.id}` === window.location.hash)
      if (index >= 0 && trackRef.current?.offsetParent) navigate(index, instant)
    }
    follow(true)
    const onHashChange = () => follow(false)
    window.addEventListener('hashchange', onHashChange)
    return () => window.removeEventListener('hashchange', onHashChange)
  }, [navigate])

  return (
    <div ref={trackRef} className={styles.track} style={{ height: `${SECTIONS.length * 100}vh` }}>
      <div ref={stageRef} className={styles.stage}>
        <div ref={sceneRef} className={styles.scene}>
          {SECTIONS.map((section, index) => (
            <div
              key={section.id}
              ref={(element) => {
                roomRefs.current[index] = element
              }}
              className={styles.room}
              style={{
                backgroundImage: photoReady(index) ? photo('scenes', section.scene) : undefined,
                opacity: index === 0 ? 1 : 0,
              }}
            />
          ))}
          <div className={styles.contactShadow} />
          <div className={styles.laptopBase} style={{ backgroundImage: photo('scenes', 'laptop') }} />
          <div className={styles.lid}>
            <div className={styles.screenMask}>
              <Screen active={active} stars={stars} onNavigate={navigate} />
            </div>
            <div className={styles.camera} />
            <div className={styles.glare} />
          </div>
        </div>
        <div className={styles.brandSlot}>
          <Brand dark={SECTIONS[active]?.logo === 'dark'} />
        </div>
      </div>
    </div>
  )
}
