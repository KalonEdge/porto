import { Fragment, type ReactNode } from 'react'
import { Lexer, type Token, type Tokens } from 'marked'

// Renders the guides' Markdown straight to React elements from marked's tokens,
// so no HTML string is ever injected into the page. Raw HTML in the source is
// left out; everything else in GitHub-flavoured Markdown is supported.

const ENTITIES: Record<string, string> = { amp: '&', lt: '<', gt: '>', quot: '"', apos: "'", nbsp: ' ', mdash: '—', ndash: '–', hellip: '…', rsquo: '’', lsquo: '‘', ldquo: '“', rdquo: '”' }

const decode = (text: string) =>
  text.replace(/&(#x[0-9a-f]+|#\d+|[a-z]+);/gi, (match, entity: string) => {
    if (entity[0] === '#') {
      const code = entity[1].toLowerCase() === 'x' ? parseInt(entity.slice(2), 16) : Number(entity.slice(1))
      return Number.isFinite(code) ? String.fromCodePoint(code) : match
    }
    return ENTITIES[entity.toLowerCase()] ?? match
  })

const plain = (tokens: Token[] = []): string =>
  tokens.map((token) => ('tokens' in token && token.tokens ? plain(token.tokens) : 'text' in token ? decode(token.text) : '')).join('')

const slugify = (text: string) =>
  text
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-|-$/g, '')

function inline(tokens: Token[] = []): ReactNode[] {
  return tokens.map((token, index) => {
    switch (token.type) {
      case 'text':
        return 'tokens' in token && token.tokens ? <Fragment key={index}>{inline(token.tokens)}</Fragment> : decode(token.text)
      case 'escape':
        return decode(token.text)
      case 'strong':
        return <strong key={index}>{inline(token.tokens)}</strong>
      case 'em':
        return <em key={index}>{inline(token.tokens)}</em>
      case 'del':
        return <del key={index}>{inline(token.tokens)}</del>
      case 'codespan':
        return <code key={index}>{decode(token.text)}</code>
      case 'br':
        return <br key={index} />
      case 'link': {
        const link = token as Tokens.Link
        return (
          <a key={index} href={link.href} title={link.title ?? undefined}>
            {inline(link.tokens)}
          </a>
        )
      }
      case 'image': {
        const image = token as Tokens.Image
        // eslint-disable-next-line @next/next/no-img-element
        return <img key={index} src={image.href} alt={image.text} title={image.title ?? undefined} />
      }
      default:
        // Inline HTML and anything unknown.
        return null
    }
  })
}

function listItem(item: Tokens.ListItem, index: number) {
  return (
    <li key={index}>
      {item.task && <input type="checkbox" checked={item.checked} disabled readOnly />}
      {item.loose ? block(item.tokens) : item.tokens.map((token, i) => (token.type === 'text' ? <Fragment key={i}>{inline(token.tokens ?? [token])}</Fragment> : blockToken(token, i)))}
    </li>
  )
}

function blockToken(token: Token, index: number): ReactNode {
  switch (token.type) {
    case 'heading': {
      const heading = token as Tokens.Heading
      const Tag = `h${heading.depth}` as 'h1' | 'h2' | 'h3' | 'h4' | 'h5' | 'h6'
      return (
        <Tag key={index} id={slugify(plain(heading.tokens))}>
          {inline(heading.tokens)}
        </Tag>
      )
    }
    case 'paragraph':
      return <p key={index}>{inline((token as Tokens.Paragraph).tokens)}</p>
    case 'text':
      return <p key={index}>{inline('tokens' in token && token.tokens ? token.tokens : [token])}</p>
    case 'code': {
      const code = token as Tokens.Code
      return (
        <pre key={index}>
          <code className={code.lang ? `language-${code.lang}` : undefined}>{code.text}</code>
        </pre>
      )
    }
    case 'blockquote':
      return <blockquote key={index}>{block((token as Tokens.Blockquote).tokens)}</blockquote>
    case 'list': {
      const list = token as Tokens.List
      const items = list.items.map(listItem)
      return list.ordered ? (
        <ol key={index} start={list.start === '' || list.start === 1 ? undefined : Number(list.start)}>
          {items}
        </ol>
      ) : (
        <ul key={index}>{items}</ul>
      )
    }
    case 'table': {
      const table = token as Tokens.Table
      return (
        <table key={index}>
          <thead>
            <tr>
              {table.header.map((cell, i) => (
                <th key={i}>{inline(cell.tokens)}</th>
              ))}
            </tr>
          </thead>
          <tbody>
            {table.rows.map((row, r) => (
              <tr key={r}>
                {row.map((cell, i) => (
                  <td key={i}>{inline(cell.tokens)}</td>
                ))}
              </tr>
            ))}
          </tbody>
        </table>
      )
    }
    case 'hr':
      return <hr key={index} />
    default:
      // Spacing, raw HTML blocks and definitions render nothing.
      return null
  }
}

const block = (tokens: Token[]) => tokens.map(blockToken)

export function Markdown({ source, className }: { source: string; className?: string }) {
  return <div className={className}>{block(new Lexer({ gfm: true }).lex(source))}</div>
}
