import fs from 'node:fs'
import path from 'node:path'

// The written content lives in content/ as Markdown, so the same source renders
// the HTML pages and the .md copies agents read (/index.md, /guides/<slug>.md,
// /llms.txt, /llms-full.txt).

const CONTENT = path.join(process.cwd(), 'content')

export type Guide = {
  slug: string
  title: string
  description: string
  published: string
  updated: string
  order: number
  keywords: string[]
  markdown: string
}

/** A small frontmatter block of `key: value` lines between --- fences. */
function parse(file: string) {
  const source = fs.readFileSync(file, 'utf8')
  const match = source.match(/^---\n([\s\S]*?)\n---\n+([\s\S]*)$/)
  if (!match) return { data: {} as Record<string, string>, body: source }
  const data: Record<string, string> = {}
  for (const line of match[1].split('\n')) {
    const colon = line.indexOf(':')
    if (colon > 0) data[line.slice(0, colon).trim()] = line.slice(colon + 1).trim()
  }
  return { data, body: match[2] }
}

let guides: Guide[] | undefined

export function getGuides(): Guide[] {
  if (guides) return guides
  const dir = path.join(CONTENT, 'guides')
  guides = fs
    .readdirSync(dir)
    .filter((name) => name.endsWith('.md'))
    .map((name) => {
      const { data, body } = parse(path.join(dir, name))
      return {
        slug: name.replace(/\.md$/, ''),
        title: data.title,
        description: data.description,
        published: data.published,
        updated: data.updated || data.published,
        order: Number(data.order) || 99,
        keywords: (data.keywords || '').split(',').map((keyword) => keyword.trim()).filter(Boolean),
        markdown: body.trim(),
      }
    })
    .sort((a, b) => a.order - b.order || a.title.localeCompare(b.title))
  return guides
}

export const getGuide = (slug: string) => getGuides().find((guide) => guide.slug === slug)

/** The product overview agents get at /index.md and at the top of /llms-full.txt. */
export const getOverview = () => fs.readFileSync(path.join(CONTENT, 'porto.md'), 'utf8').trim()

/** A rough reading time, at 220 words a minute. */
export const readingMinutes = (markdown: string) => Math.max(1, Math.round(markdown.split(/\s+/).length / 220))

/** The Mac app's version, read from its Info.plist by next.config.ts at build time. */
export const appVersion = () => process.env.APP_VERSION || undefined
