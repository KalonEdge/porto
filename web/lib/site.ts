// Everything that names Porto or links somewhere lives here, so the brand,
// domain and links can change in one place. Set these in the environment when
// deploying; the defaults keep local development working. Each variable is read
// literally so Next.js can inline it into client components too.

const value = (setting: string | undefined, fallback: string) => setting?.trim() || fallback

export const SITE_URL = value(process.env.NEXT_PUBLIC_SITE_URL, 'http://localhost:8186').replace(/\/$/, '')
export const SITE_NAME = 'Porto'
export const SITE_TITLE = 'Porto: see every dev server and port on your Mac'
export const SITE_DESCRIPTION =
  'A free, open-source macOS menu bar app that shows what’s running on localhost: every dev server’s port, project, git branch, memory and the Claude Code, Codex or Conductor session that started it. Stop the ones you forgot in one click.'

/** `owner/repo` on GitHub. The star count appears once the repository exists. */
export const GITHUB_REPO = value(process.env.NEXT_PUBLIC_GITHUB_REPO, 'KalonEdge/porto')
export const GITHUB_URL = `https://github.com/${GITHUB_REPO}`

/** The latest release, built into public/ from ../app (see app/scripts/make-dmg.sh). */
export const DOWNLOAD_URL = '/Porto.dmg'

const authorURL = process.env.NEXT_PUBLIC_AUTHOR_URL?.trim()

export const AUTHOR = {
  name: value(process.env.NEXT_PUBLIC_AUTHOR_NAME, 'the Porto team'),
  url: authorURL || GITHUB_URL,
}

/** The footer's last link: the maker's site when one is configured, otherwise feedback. */
export const FOOTER_LINK = authorURL
  ? { label: new URL(authorURL).host.replace(/^www\./, ''), href: authorURL }
  : { label: 'Feedback', href: `${GITHUB_URL}/issues` }

export const OG_IMAGE = {
  url: '/og-image.png',
  width: 1200,
  height: 630,
  alt: 'Porto: every dev server on your Mac, in the menu bar. The Porto server list on a warm dark background.',
}

/** The pretend shell in the terminal demo introduces itself with this host. */
export const DEMO_HOST = 'porto'
