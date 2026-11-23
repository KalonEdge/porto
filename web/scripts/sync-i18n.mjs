// The popover demo speaks the Mac app's languages. Its strings come straight
// from the app's Localizable.strings tables, so the site can never drift from
// the product. Writes lib/i18n/strings.json; run after changing the app's copy.
// Without the app checkout (e.g. a web-only deploy) the committed JSON is kept.
import { existsSync, readFileSync, writeFileSync } from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const root = path.dirname(path.dirname(fileURLToPath(import.meta.url)))
const tables = path.join(root, '../app/Sources/Porto/Resources')
const output = path.join(root, 'lib/i18n/strings.json')
const LANGUAGES = ['de', 'fr', 'es', 'zh-Hans', 'he', 'ja', 'uk']

// Every string the demo popover shows. Keep in step with components/demo.
const KEYS = [
  'Servers', 'Clean up', 'CPU (servers)', 'CPU (all)', 'Whole Mac. Click for servers only.',
  'Dev servers, as a share of the whole Mac. Click for all.', 'Other apps', 'Free', '%@ of %@', 'Free · %@',
  '%@ of RAM', '%@ of RAM · CPU %@', 'System and smaller apps', 'Everything else', 'Everything else · %@',
  'Pick servers to stop', 'freed by stopping %d', 'Nothing listening', 'Dev servers on ports %d–%d show up here.',
  'Cancel', 'Stop servers', 'Stop %d %@ · free %@', 'server', 'servers', 'servers (few)', 'Open in browser', 'Stop',
  'Back', 'up %@', 'idle %@', 'Worktree deleted · idle %@', '+%@ in %@', 'Worktree deleted',
  'Idle %@ · no connections', 'Leaking · +%@', '<1m', '%dm', '%dh', '%dh %dm', '%dd', 'Running for %@',
  'Restart with the same command', 'Session', 'Branch', 'Folder', 'Framework', 'Command', 'Started', 'Workspace',
  'Session ID', '%d more', 'Less', 'Memory', '10 min', 'Processes', 'Open localhost:%@', 'Preview',
]

if (!existsSync(tables)) {
  console.log('sync-i18n: ../app not found, keeping lib/i18n/strings.json')
  process.exit(0)
}

const unescape = (text) => text.replace(/\\(["\\])/g, '$1').replace(/\\n/g, '\n')
const parse = (file) => {
  const entries = {}
  for (const line of readFileSync(file, 'utf8').split('\n')) {
    const match = line.match(/^"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)";$/)
    if (match) entries[unescape(match[1])] = unescape(match[2])
  }
  return entries
}

const result = {}
const missing = []
for (const language of LANGUAGES) {
  const table = parse(path.join(tables, `${language}.lproj/Localizable.strings`))
  result[language] = {}
  for (const key of KEYS) {
    if (key in table) result[language][key] = table[key]
    else missing.push(`${language}: ${key}`)
  }
}
if (missing.length) {
  console.error(`sync-i18n: missing from the app's tables:\n  ${missing.join('\n  ')}`)
  process.exit(1)
}
writeFileSync(output, JSON.stringify(result, null, 1) + '\n')
console.log(`sync-i18n: ${KEYS.length} strings × ${LANGUAGES.length} languages → lib/i18n/strings.json`)
