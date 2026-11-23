import type { Metadata } from 'next'
import { notFound } from 'next/navigation'
import { JsonLd } from '@/components/JsonLd'
import { Markdown } from '@/components/Markdown'
import { getGuide, getGuides, readingMinutes } from '@/lib/content'
import { OG_IMAGE, SITE_NAME } from '@/lib/site'
import { article } from '@/lib/structured-data'
import { DownloadButton } from '../SiteChrome'
import styles from '../guides.module.css'

export const dynamicParams = false

export function generateStaticParams() {
  return getGuides().map((guide) => ({ slug: guide.slug }))
}

export async function generateMetadata({ params }: PageProps<'/guides/[slug]'>): Promise<Metadata> {
  const guide = getGuide((await params).slug)
  if (!guide) return {}
  const url = `/guides/${guide.slug}`
  return {
    title: guide.title,
    description: guide.description,
    keywords: guide.keywords,
    alternates: { canonical: url, types: { 'text/markdown': `${url}.md` } },
    openGraph: {
      title: guide.title,
      description: guide.description,
      url,
      type: 'article',
      publishedTime: guide.published,
      modifiedTime: guide.updated,
      siteName: SITE_NAME,
      images: [OG_IMAGE],
    },
    twitter: { card: 'summary_large_image', title: guide.title, description: guide.description, images: [OG_IMAGE] },
  }
}

const formatDate = (date: string) => new Intl.DateTimeFormat('en-US', { dateStyle: 'medium', timeZone: 'UTC' }).format(new Date(date))

export default async function GuidePage({ params }: PageProps<'/guides/[slug]'>) {
  const guide = getGuide((await params).slug)
  if (!guide) notFound()
  const more = getGuides().filter((other) => other.slug !== guide.slug)

  return (
    <>
      <JsonLd data={article(guide)} />
      <article>
        <header className={styles.articleHeader}>
          <nav className={styles.crumbs} aria-label="Breadcrumb">
            <a href="/guides">Guides</a>
          </nav>
          <h1 className={styles.title}>{guide.title}</h1>
          <p className={styles.lede}>{guide.description}</p>
          <p className={styles.meta}>
            <time dateTime={guide.updated}>{formatDate(guide.updated)}</time> · {readingMinutes(guide.markdown)} min read
          </p>
        </header>
        <Markdown className={styles.prose} source={guide.markdown} />
      </article>

      <aside className={styles.cta}>
        <div>
          <p className={styles.ctaTitle}>Every dev server on your Mac, in the menu bar.</p>
          <p className={styles.ctaMeta}>Free and open source · macOS 14 or later · No account</p>
        </div>
        <DownloadButton />
      </aside>

      <nav className={styles.more} aria-label="More guides">
        <h2 className={styles.moreTitle}>More guides</h2>
        <ul className={styles.index}>
          {more.map((other) => (
            <li key={other.slug}>
              <a className={styles.indexLink} href={`/guides/${other.slug}`}>
                <span className={styles.indexTitle}>{other.title}</span>
              </a>
            </li>
          ))}
        </ul>
      </nav>
    </>
  )
}
