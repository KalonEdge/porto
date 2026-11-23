'use client'

import { useCallback, useState } from 'react'
import { SERVERS } from '@/lib/demo'
import { GET_IT, TERMINAL } from '@/lib/sections'

// A working copy of the Porto popover. Scrolling picks the view for each
// section; clicking around works like the real app until the next section.

export type View = { name: 'list' } | { name: 'detail'; port: string } | { name: 'cleanUp' }

const SECTION_VIEWS: View[] = [
  { name: 'list' },
  { name: 'detail', port: '3000' },
  { name: 'detail', port: '6006' },
  { name: 'cleanUp' },
  { name: 'list' },
  { name: 'list' },
  { name: 'list' },
]

// The Terminal section shows the CLI instead, and the last section the dot matrix.
const opensPopover = (section: number) => section !== GET_IT && section !== TERMINAL

const ALL_PORTS = SERVERS.map((server) => server.port)

/** Clean up preselects idle servers and ones from deleted worktrees, never leaking ones. */
const suggested = (running: string[]) =>
  SERVERS.filter((server) => server.cleanUp?.suggested && running.includes(server.port)).map((server) => server.port)

export function useDemo(section: number) {
  const [running, setRunning] = useState(ALL_PORTS)
  const [view, setView] = useState<View>(SECTION_VIEWS[section])
  const [direction, setDirection] = useState(1)
  const [open, setOpen] = useState(opensPopover(section))
  const [selected, setSelected] = useState(() => suggested(ALL_PORTS))

  // A new section resets the view during render, so no frame shows the old one.
  // Stopped servers stay stopped.
  const [shownSection, setShownSection] = useState(section)
  if (shownSection !== section) {
    setShownSection(section)
    setDirection(section > shownSection ? 1 : -1)
    setView(SECTION_VIEWS[section])
    setOpen(opensPopover(section))
    setSelected(suggested(running))
  }

  const go = useCallback(
    (next: View, dir: number) => {
      setDirection(dir)
      if (next.name === 'cleanUp') setSelected(suggested(running))
      setView(next)
    },
    [running],
  )

  const stop = useCallback((ports: string[]) => {
    setRunning((current) => current.filter((port) => !ports.includes(port)))
    setSelected((current) => current.filter((port) => !ports.includes(port)))
    setDirection(-1)
    setView((current) => (current.name === 'detail' && ports.includes(current.port) ? { name: 'list' } : current))
  }, [])

  const restartAll = useCallback(() => {
    setRunning(ALL_PORTS)
    setSelected(suggested(ALL_PORTS))
  }, [])

  const toggleSelected = useCallback((port: string) => {
    setSelected((current) => (current.includes(port) ? current.filter((p) => p !== port) : [...current, port]))
  }, [])

  // A detail view for a server that's been stopped falls back to the list.
  const shown: View = view.name === 'detail' && !running.includes(view.port) ? { name: 'list' } : view

  return {
    running: SERVERS.filter((server) => running.includes(server.port)),
    view: shown,
    direction,
    open,
    setOpen,
    selected,
    toggleSelected,
    go,
    stop,
    restartAll,
  }
}

export type Demo = ReturnType<typeof useDemo>
