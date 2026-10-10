// Mentat's band and pane. The band is always there, one line: what waits on the maintainer, else a
// warning that a rate limit runs low, else the newest note, else a quiet line. The pane holds the
// Log, the agents and, on the terminal, where this session's pull request stands.
// Claude Code reads this file as a mod (hooks/hooks.json lists it under "modules");
// it approves, denies or changes no other tool call.
//
// Everything a drawing reads lives in $.state (pane/types.d.ts); render hooks never
// write it. Every $ call is in a hook or in a top-level function that takes $.

import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register, RenderChildren } from 'claude-code'

import type { AgentRow, AgentStatus, Checks, CodexRead, Decision, DecisionKind, LogEntry, LogKind, PrSnapshot, ReadMark, ReviewSnapshot } from './types'

const PLUGIN = 'mentat'
const PANE = 'mentat'
const TITLE = 'Mentat'
const OPEN_TOOL = `mcp__${PLUGIN}__open_decision`
const CLOSE_TOOL = `mcp__${PLUGIN}__close_decision`
const NOTE_TOOL = `mcp__${PLUGIN}__note`
const CODEX_APP = 'chatgpt-codex-connector[bot]'
const SUMMARY_MARK = '<!-- codex-pull-request-review-summary -->'
const STALE_MS = 5 * 60_000
const LIST_LIMIT = 100
// A rate limit this far gone raises the band.
const WARN_PERCENT = 80
// Rows between the desktop pane's sections.
const SECTION_GAP = 2
// The Log card keeps this many entries, shows the newest LOG_SHOWN until `Show all`, and cuts a line at LOG_WIDTH characters.
const LOG_LIMIT = 200
const LOG_SHOWN = 5
const LOG_WIDTH = 80

const items = atom({ plugin: 'mentat', key: 'decisionsItems' } as const, [])
const nextId = atom({ plugin: 'mentat', key: 'decisionsNextId' } as const, 1)
const sentAtom = atom({ plugin: 'mentat', key: 'decisionsSent' } as const, [])
const agents = atom({ plugin: 'mentat', key: 'agents' } as const, [])
const finishedHidden = atom({ plugin: 'mentat', key: 'agentsFinishedHidden' } as const, false)
const prRef = atom({ plugin: 'mentat', key: 'prRef' } as const, '')
const prAtom = atom({ plugin: 'mentat', key: 'pr' } as const, null)
const prMark = atom({ plugin: 'mentat', key: 'prMark' } as const, { seq: 0, okAt: 0, failedAt: 0 })
const reviewAtom = atom({ plugin: 'mentat', key: 'review' } as const, null)
const reviewMark = atom({ plugin: 'mentat', key: 'reviewMark' } as const, { seq: 0, okAt: 0, failedAt: 0 })
const meAtom = atom({ plugin: 'mentat', key: 'me' } as const, '')
const seqAtom = atom({ plugin: 'mentat', key: 'seq' } as const, 0)
const checkResult = atom({ plugin: 'mentat', key: 'checkResult' } as const, null)
const logAtom = atom({ plugin: 'mentat', key: 'log' } as const, [])
const logAll = atom({ plugin: 'mentat', key: 'logAll' } as const, false)

// The id of the item the mod itself pins for a `mentat check`: an alert after a failed run, a
// warning after a passing run with warnings. The next run replaces it, and a clean pass removes it.
const CHECK_ID = 'check'

// The notes Claude Code adds with the `note` tool, in the pane's Log card and as the band's line: each kind has an
// icon and a color. The color is a theme color, so the line reads on the terminal and the desktop; the hue is
// the same color for the desktop band's drawing.
const LOG_STYLE: Record<LogKind, { icon: string; color: string; hue: string }> = {
  decision: { icon: '◆', color: 'suggestion', hue: '#3D7FE6' },
  plan: { icon: '▸', color: 'text', hue: '#8f8f8a' },
  surprise: { icon: '!', color: 'warning', hue: '#C98A0E' },
  waiting: { icon: '◌', color: 'subtle', hue: '#8f8f8a' },
  done: { icon: '✓', color: 'success', hue: '#2F9461' },
}
const NOTE_KINDS: readonly LogKind[] = ['decision', 'plan', 'surprise', 'waiting', 'done']
const isNoteKind = (v: unknown): v is LogKind => NOTE_KINDS.includes(v as LogKind)

// ---- plain helpers (no $) -----------------------------------------------------------

const cleanTitle = (t: string): string => t.replace(/^[a-z]+(\([^)]*\))?!?:\s*/, '').replace(/^\w/, c => c.toUpperCase())
type LogDraft = { kind: LogKind; text: string }
const plural = (n: number, one: string, many: string): string => `${n} ${n === 1 ? one : many}`
const shortModel = (model: string): string =>
  model.replace(/^claude-/, '').replace(/-\d{8}$/, '').replace(/-(\d+)-(\d+)$/, ' $1.$2').replace(/^\w/, c => c.toUpperCase())
const duration = (ms: number): string => {
  const s = Math.max(0, Math.round(ms / 1000))
  return s < 60 ? `${s}s` : `${Math.floor(s / 60)}m ${String(s % 60).padStart(2, '0')}s`
}
const kTokens = (n: number): string => (n < 1000 ? `${n}` : `${(n / 1000).toFixed(n < 10000 ? 1 : 0)}k`)
// An effort level as the row shows it; a number is a budget.
const showEffort = (effort: string | number): string => (typeof effort === 'number' ? `${kTokens(effort)} budget` : effort)
const ago = (ms: number): string => {
  const m = Math.floor(Math.max(0, ms) / 60_000)
  return m < 1 ? 'just now' : m < 60 ? `${m}m ago` : `${Math.floor(m / 60)}h ago`
}
const resetIn = (at: string | undefined, now: number): string => {
  if (at === undefined) return ''
  const ms = Date.parse(at) - now
  if (!(ms > 0)) return ''
  const h = Math.floor(ms / 3_600_000)
  const m = Math.floor((ms % 3_600_000) / 60_000)
  return h >= 24 ? `resets in ${Math.round(h / 24)}d` : h > 0 ? `resets in ${h}h ${m}m` : `resets in ${m}m`
}
// The weekly reset as the desktop app's usage popover words it: `resets Thu 7:00 PM`, the short
// weekday and the 12-hour clock in the local time zone. `zone` is an IANA name, or undefined
// for the zone the process runs in; a name the runtime does not know falls back to that zone.
export const resetAt = (at: string | undefined, now: number, zone?: string): string => {
  if (at === undefined || !(Date.parse(at) - now > 0)) return ''
  const part = zoneParts(new Date(at), { weekday: 'short', hour: 'numeric', minute: '2-digit', hour12: true }, zone)

  return `resets ${part('weekday')} ${part('hour')}:${part('minute')} ${part('dayPeriod')}`
}
// The parts of a time in `zone` (an IANA name, or undefined for the zone the process runs in; a name
// the runtime does not know falls back to that zone).
const zoneParts = (when: Date, options: Intl.DateTimeFormatOptions, zone?: string): ((type: string) => string) => {
  const parts = (timeZone: string | undefined) => new Intl.DateTimeFormat('en-US', { ...options, timeZone }).formatToParts(when)
  let found: Intl.DateTimeFormatPart[]
  try {
    found = parts(zone === '' ? undefined : zone)
  } catch {
    found = parts(undefined)
  }

  return type => found.find(x => x.type === type)?.value ?? ''
}
// The time of a log entry as `h:mm AM` or `h:mm PM` (12-hour, no seconds), in the same zone the weekly reset uses.
const clockAt = (at: number, zone?: string): string => {
  const part = zoneParts(new Date(at), { hour: 'numeric', minute: '2-digit', hour12: true }, zone)

  return `${part('hour')}:${part('minute')} ${part('dayPeriod')}`
}
// One line, at most `max` characters, cut with an ellipsis.
const oneLine = (text: string, max: number = LOG_WIDTH): string => {
  const chars = [...text.replace(/\s+/g, ' ').trim()]

  return chars.length <= max ? chars.join('') : `${chars.slice(0, max - 1).join('').trimEnd()}…`
}

type Meter = { kind: string; label: string; percent: number; reset: string }
type Usage = Awaited<ReturnType<EngineInterface['session']['usage']>>

// The rate limits as the band reads them, each with its percent and the reset: a countdown for the
// 5-hour limit, the weekday and local time for the weekly one.
const limitsOf = (usage: Usage | undefined, now: number, zone?: string): Meter[] =>
  (usage?.rateLimits ?? []).map(r => ({
    kind: r.kind,
    label: r.kind === 'five_hour' ? '5-hour' : r.kind === 'seven_day' ? 'Week' : r.kind,
    percent: Math.round(r.percentUsed),
    reset: r.kind === 'seven_day' ? resetAt(r.resetsAt, now, zone) : resetIn(r.resetsAt, now),
  }))

// The band's budget text, for the most used of the 5-hour and weekly limits when it
// is at WARN_PERCENT or more. The context window never raises the band.
const budgetAlert = (limits: Meter[]): string | undefined => {
  const over = limits
    .filter(m => (m.kind === 'five_hour' || m.kind === 'seven_day') && m.percent >= WARN_PERCENT)
    .sort((a, b) => b.percent - a.percent)[0]
  if (over === undefined) return undefined

  return `${over.label} limit ${over.percent}%${over.reset === '' ? '' : ` · ${over.reset}`}`
}

// `gh api --paginate` prints each page as its own JSON array, one after the other.
const parsePages = (text: string): unknown[] => {
  const out: unknown[] = []
  let i = 0
  while (i < text.length) {
    const c = text[i]!
    if (c === ' ' || c === '\n' || c === '\r' || c === '\t') {
      i += 1
      continue
    }
    if (c !== '[') throw new Error('not a JSON array')
    let depth = 0
    let inString = false
    let j = i
    for (; j < text.length; j++) {
      const d = text[j]!
      if (inString) {
        if (d === '\\') j += 1
        else if (d === '"') inString = false
      } else if (d === '"') inString = true
      else if (d === '[') depth += 1
      else if (d === ']') {
        depth -= 1
        if (depth === 0) break
      }
    }
    if (depth !== 0) throw new Error('truncated JSON array')
    const page = JSON.parse(text.slice(i, j + 1)) as unknown
    if (!Array.isArray(page)) throw new Error('not a JSON array')
    out.push(...page)
    i = j + 1
  }
  return out
}

type Json = Record<string, unknown>
const asObj = (v: unknown): Json => (typeof v === 'object' && v !== null ? (v as Json) : {})
const str = (v: unknown): string => (typeof v === 'string' ? v : '')
const login = (c: Json): string => str(asObj(c.user).login)

// statusCheckRollup holds CheckRun nodes (status, conclusion) and StatusContext
// nodes (state); a conclusion or state that is not a success is a failure.
const checksOf = (rollup: unknown): Checks => {
  const checks: Checks = { failed: 0, running: 0, passed: 0 }
  for (const node of Array.isArray(rollup) ? rollup : []) {
    const n = asObj(node)
    if (typeof n.status === 'string') {
      const conclusion = str(n.conclusion).toUpperCase()
      if (n.status !== 'COMPLETED') checks.running += 1
      else if (conclusion === 'SUCCESS' || conclusion === 'NEUTRAL' || conclusion === 'SKIPPED') checks.passed += 1
      else checks.failed += 1
    } else {
      const state = str(n.state).toUpperCase()
      if (state === 'SUCCESS') checks.passed += 1
      else if (state === 'FAILURE' || state === 'ERROR') checks.failed += 1
      else checks.running += 1
    }
  }
  return checks
}

// The GitHub line: facts in this order, from GitHub's own fields.
const githubLine = (pr: PrSnapshot): string => {
  if (pr.state === 'MERGED') return 'Merged'
  if (pr.state === 'CLOSED') return 'Closed'
  if (pr.isDraft) return 'Draft'
  if (pr.mergeState === 'DIRTY') return 'Conflicts'
  if (pr.reviewDecision === 'CHANGES_REQUESTED') return 'Changes requested'
  if (pr.reviewDecision === 'APPROVED') return 'Approved'
  if (pr.reviewDecision === 'REVIEW_REQUIRED') return 'Approval required'
  if (pr.mergeState === 'CLEAN' || pr.mergeState === 'HAS_HOOKS') return 'Mergeable'
  if (pr.mergeState === 'UNKNOWN' || pr.mergeState === '') return 'Merge state unknown'
  return `Merge blocked · ${pr.mergeState.toLowerCase()}`
}
const ciLine = (c: Checks): { text: string; isBad: boolean } =>
  c.failed > 0
    ? { text: `✕ ${c.failed} failed`, isBad: true }
    : c.running > 0
      ? { text: 'running', isBad: false }
      : c.passed > 0
        ? { text: '✓', isBad: false }
        : { text: 'none', isBad: false }

// The Code Review row of the app's summary comment, read as bin/mentat reads it:
// `| 📝 **Code Review** | ✅ **Completed** <relative-time datetime="…Z">…</relative-time> | `sha` | … |`.
const SUMMARY_ROW = /^\|[^|]*\|[^|]*\*\*([A-Za-z ]+)\*\*[^|]*datetime="[0-9T:-]+(?:\.[0-9]+)?Z"[^|]*\|\s*`([0-9a-f]{7,40})`\s*\|/
const parseSummary = (body: string): { status: string; sha: string } | undefined => {
  const row = body.split('\n').find(line => /^\|[^|]*Code Review[^|]*\|/.test(line))
  const m = row === undefined ? null : SUMMARY_ROW.exec(row)
  return m === null ? undefined : { status: m[1]!.trim(), sha: m[2]! }
}

// What the review reads of GitHub say about the PR's head, for the agent account `me`.
const readReview = (issueComments: unknown[], pullComments: unknown[], reviews: unknown[], head: string, me: string): Omit<ReviewSnapshot, 'ref' | 'seq' | 'head'> => {
  const issue = issueComments.map(asObj)
  const inline = pullComments.map(asObj)
  const summaries = issue.filter(c => login(c) === CODEX_APP && str(c.body).includes(SUMMARY_MARK))
  const latest = summaries[summaries.length - 1]
  let codex: CodexRead = { kind: 'none' }
  if (latest !== undefined) {
    const parsed = parseSummary(str(latest.body))
    const status = parsed?.status.toLowerCase()
    if (parsed === undefined) codex = { kind: 'unknown' }
    else if (!head.startsWith(parsed.sha)) codex = { kind: 'other', sha: parsed.sha }
    else if (status === 'completed') {
      const findings = inline.filter(c => login(c) === CODEX_APP && str(c.commit_id) === head && c.in_reply_to_id == null)
      const ids = new Set(findings.map(c => c.id))
      const replied = new Set(inline.filter(c => login(c) === me && ids.has(c.in_reply_to_id)).map(c => c.in_reply_to_id))
      // A review of the head by the app with no inline comment (a head-level or
      // security review) is findings too, but has no count.
      const hasReview = reviews.map(asObj).some(r => login(r) === CODEX_APP && str(r.commit_id) === head)
      codex = { kind: 'completed', sha: parsed.sha, findings: findings.length, replied: replied.size, hasReview }
    } else if (status === 'failed') codex = { kind: 'failed', sha: parsed.sha }
    else if (status !== undefined && /^(running|in progress|reviewing|queued|pending)$/.test(status)) codex = { kind: 'running', sha: parsed.sha }
    else codex = { kind: 'unknown' }
  }
  const mine = issue.filter(c => login(c) === me)
  const locals = mine.filter(c => str(c.body).startsWith(`## Local Codex review of ${head}`))
  const lastLocal = locals[locals.length - 1]
  let local: ReviewSnapshot['local']
  if (lastLocal !== undefined) {
    const lines = str(lastLocal.body).split('\n').map(l => l.trim()).filter(l => l !== '')
    const result = /^REVIEW RESULT: (NO FINDINGS|FINDINGS)$/.exec(lines[lines.length - 1] ?? '')
    local = result === null ? { sha: head } : { sha: head, result: result[1] as 'NO FINDINGS' | 'FINDINGS' }
  }
  return { codex, local }
}

const sha7 = (sha: string): string => sha.slice(0, 7)
const localText = (local: NonNullable<ReviewSnapshot['local']>): string => {
  const result = local.result === undefined ? [] : [local.result === 'FINDINGS' ? 'Findings' : 'No findings']
  return ['Local review posted', ...result, sha7(local.sha)].join(' · ')
}
const codexText = (r: ReviewSnapshot): string => {
  const c = r.codex
  // A completed app result stands. Otherwise a local review of the same head (the
  // review workflow's fallback) is what happened, so it shows even over a Running
  // or Failed app summary.
  if (c.kind === 'completed') {
    if (c.findings === 0) return c.hasReview ? `Findings in review · ${sha7(c.sha)}` : `No findings · ${sha7(c.sha)}`
    return `${plural(c.findings, 'finding', 'findings')} · ${c.replied} replied · ${sha7(c.sha)}`
  }
  if (r.local !== undefined) return localText(r.local)
  if (c.kind === 'running') return `Running · ${sha7(c.sha)}`
  if (c.kind === 'failed') return `Failed · ${sha7(c.sha)}`
  return c.kind === 'other' ? 'Not on this commit' : c.kind === 'none' ? 'No review yet' : 'unknown'
}

const isEnded = (s: AgentStatus): boolean => s === 'completed' || s === 'failed' || s === 'killed' || s === 'unknown'
const isActive = (s: AgentStatus): boolean => s === 'running' || s === 'waiting' || s === 'pending'

type AgentInfoLike = { id: string; type: string; description: string; status: AgentStatus }
// Fits the rows to what the engine lists: statuses follow the engine, an end freezes
// the elapsed time, an agent the mod never saw is added without a model or start (with the
// effort its requests used, if any were seen),
// and one the engine no longer lists is ended (unknown), never finished.
const reconcile = (rows: AgentRow[], infos: AgentInfoLike[], now: number, efforts: ReadonlyMap<string, string>): AgentRow[] => {
  const next = rows.map(row => {
    const info = infos.find(i => i.id === row.id)
    if (info === undefined) return isEnded(row.status) ? row : { ...row, status: 'unknown' as const, endedAt: now }
    if (isEnded(info.status)) return { ...row, status: info.status, endedAt: row.endedAt ?? now }
    const { endedAt: _endedAt, ...rest } = row
    return { ...rest, status: info.status }
  })
  for (const info of infos) {
    if (rows.some(r => r.id === info.id)) continue
    const effort = efforts.get(info.id)
    next.push({
      id: info.id,
      type: info.type,
      description: info.description,
      status: info.status,
      ...(effort === undefined ? {} : { effort }),
      ...(isEnded(info.status) ? { endedAt: now } : {}),
    })
  }
  return next.slice(-30)
}

const ghPrUrl = /https:\/\/github\.com\/([A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+)\/pull\/(\d+)/g
const REFRESH_COMMAND = /\b(gh pr|git push|mentat review)\b/
// `mentat review [--local] [--repo owner/repo] <N>` at the start of a command.
const REVIEW_COMMAND = /(?:^|[;&|(]\s*)(?:\S*\/)?mentat\s+review\s+([^;&|\n)]*)/m
const cdTarget = (command: string): string | undefined => {
  const m = /^\s*cd\s+("[^"]+"|'[^']+'|[^\s;&|]+)\s*(?:&&|;)/.exec(command)
  const dir = m === null ? undefined : m[1]!.replace(/^["']|["']$/g, '')
  return dir !== undefined && dir.startsWith('/') ? dir : undefined
}
const reviewTarget = (command: string): { repo?: string; number: number } | undefined => {
  const m = REVIEW_COMMAND.exec(command)
  if (m === null) return undefined
  let repo: string | undefined
  let number: number | undefined
  const words = m[1]!.trim().split(/\s+/)
  for (let i = 0; i < words.length; i++) {
    const w = words[i]!
    if (w === '--repo') repo = words[++i]
    else if (w.startsWith('--repo=')) repo = w.slice(7)
    else if (/^\d+$/.test(w) && number === undefined) number = Number(w)
  }
  return number === undefined ? undefined : { repo, number }
}
const parseRef = (ref: string): { repo: string; number: number } => {
  const m = /^(.+)#(\d+)$/.exec(ref)
  return { repo: m![1]!, number: Number(m![2]) }
}

// The kinds of open item, in the order the pane lists them. An item stored without a kind is a question.
const KIND_RANK: Record<DecisionKind, number> = { alert: 0, question: 1, warning: 2, action: 3 }
const kindOf = (d: { kind?: DecisionKind }): DecisionKind => d.kind ?? 'question'
// The kinds the agent may open. A warning is the mod's own, for a passing `mentat check` with warnings.
const isKind = (v: unknown): v is Exclude<DecisionKind, 'warning'> => v === 'question' || v === 'action' || v === 'alert'
// A link is drawn only when it is an https URL.
const httpsLink = (v: unknown): string | undefined => {
  const link = typeof v === 'string' ? v.trim() : ''
  return link.length <= 2048 && /^https:\/\/[^\s/]\S*$/.test(link) ? link : undefined
}
// The words an item's link is drawn with: the address without its scheme.
const linkLabel = (link: string): string => link.replace(/^https:\/\//, '')

// `mentat check` as words anywhere in a command: after a `cd ... &&`, with a path or quotes
// around mentat, before `2>&1` or a pipe.
const CHECK_COMMAND = /(?:^|[\s;&|(/"'])mentat["']?\s+check(?=$|[\s;&|)"'])/
// What a `mentat check` run says: its final line (`Check OK (N warning(s))` or `Check failed:
// N problem(s)`) and its WARN lines (counted). A Bash result has no exit code, so the final line is the
// signal; without one (an interrupted run, a usage error, output cut by a pipe) there is nothing
// to record. A line that came twice (the same output in two parts of the result) counts once.
type CheckRead = { passed: true; warnings: string[] } | { passed: false; failedLine: string }
// Stands for a warning the final line counts but the output did not show (a cut or doubled line).
const UNSHOWN_WARNING = 'A warning whose text was not in the output'
const parseCheck = (output: string): CheckRead | undefined => {
  const lines = [...new Set(output.replace(/\r/g, '').split('\n').map(l => l.trimEnd()))]
  const ok = lines.map(l => /^Check OK \((\d+) warning\(s\)\)$/.exec(l)).find(m => m !== null)
  const failedLine = lines.find(l => /^Check failed: \d+ problem\(s\)$/.test(l))
  if ((ok !== undefined) === (failedLine !== undefined)) return undefined
  if (ok !== undefined && ok !== null) {
    const warns = lines.filter(l => l.startsWith('WARN: ')).map(l => l.slice(6))
    const count = Number(ok[1])
    while (warns.length < count) warns.push(UNSHOWN_WARNING)
    return { passed: true, warnings: warns }
  }
  return { passed: false, failedLine: failedLine! }
}

// The stored list is treated as unknown-shaped JSON: an entry with a closedAt was
// settled by the former decisions pane.
export const withoutSettled = <T,>(list: T[]): T[] => list.filter(d => asObj(d).closedAt === undefined)

// ---- state changes: one at a time -------------------------------------------------------

// $.state reads and writes are separate awaits, so two changes running at once could
// lose one. Every change to state runs here, in turn.
let queue: Promise<unknown> = Promise.resolve()
const inTurn = <T,>(work: () => Promise<T>): Promise<T> => {
  const run = queue.then(work, work)
  queue = run.catch(() => undefined)
  return run
}

// ---- top-level functions that take $ ------------------------------------------------------

async function invalidate($: EngineInterface): Promise<void> {
  try {
    $.ui.invalidate('ui.render')
  } catch {
    // drawing is best effort
  }
}

// The session's usage, or undefined when the engine cannot say.
async function readUsage($: EngineInterface): Promise<Usage | undefined> {
  try {
    return await $.session.usage()
  } catch {
    return undefined
  }
}

// The time zone the reset times are shown in: TZ when it is set, else the process's own (undefined).
async function readZone($: EngineInterface): Promise<string | undefined> {
  try {
    return await $.env.get('TZ')
  } catch {
    return undefined
  }
}

// Runs a command; the stdout, or undefined when it failed (nonzero exit or rejection).
async function run($: EngineInterface, argv: string[], cwd?: string): Promise<string | undefined> {
  try {
    const out = await $.process.run(argv, cwd === undefined ? { timeoutMs: 20_000 } : { timeoutMs: 20_000, cwd })
    return out.exitCode === 0 ? out.stdout : undefined
  } catch {
    return undefined
  }
}

// Adds entries to the log; call it inside inTurn. An entry equal to the newest one (same kind and
// text) is the same event again and is not added. The log keeps the last LOG_LIMIT entries.
async function addLog($: EngineInterface, at: number, drafts: LogDraft[]): Promise<void> {
  if (drafts.length === 0) return
  await update($, logAtom, list => {
    let next: LogEntry[] = list
    for (const d of drafts) {
      const text = oneLine(d.text)
      const last = next[next.length - 1]
      if (last !== undefined && last.kind === d.kind && last.text === text) continue
      next = [...next, { at, kind: d.kind, text }]
    }

    return next.slice(-LOG_LIMIT)
  })
}

async function syncAgents($: EngineInterface, efforts: ReadonlyMap<string, string>): Promise<void> {
  try {
    const infos = (await $.agent.list()) as AgentInfoLike[]
    const now = await $.clock.now()
    await inTurn(async () => {
      const before = await read($, agents)
      await update($, agents, () => reconcile(before, infos, now, efforts))
    })
  } catch {
    // the next check tries again
  }
}

async function agentTick($: EngineInterface, efforts: ReadonlyMap<string, string>): Promise<void> {
  const rows = await read($, agents)
  if (!rows.some(r => !isEnded(r.status))) return
  await syncAgents($, efforts)
  await invalidate($)
}

// Starts following a pull request: a different one clears what was read for the old.
async function follow($: EngineInterface, ref: string): Promise<boolean> {
  const changed = await inTurn(async () => {
    if ((await read($, prRef)) === ref) return false
    await update($, prRef, () => ref)
    await update($, prAtom, () => null)
    await update($, reviewAtom, () => null)
    await update($, prMark, () => ({ seq: 0, okAt: 0, failedAt: 0 }))
    await update($, reviewMark, () => ({ seq: 0, okAt: 0, failedAt: 0 }))
    return true
  })
  if (changed) await invalidate($)
  return changed
}

const failedMark = (mark: ReadMark, seq: number, at: number, cause?: 'user'): ReadMark => ({
  seq,
  okAt: mark.okAt,
  failedAt: at,
  ...(cause === undefined ? {} : { cause }),
})

// Stores a read of the pull request, unless the followed PR changed or a newer read
// is already stored. A new head discards review data read for the old one.
async function commitPr($: EngineInterface, ref: string, seq: number, snapshot: PrSnapshot | undefined, at: number): Promise<boolean> {
  return inTurn(async () => {
    if ((await read($, prRef)) !== ref) return false
    const mark = await read($, prMark)
    if (seq < mark.seq) return false
    if (snapshot === undefined) {
      await update($, prMark, () => failedMark(mark, seq, at))
      return false
    }
    await update($, prAtom, () => snapshot)
    await update($, prMark, () => ({ seq, okAt: at, failedAt: 0 }))
    const review = await read($, reviewAtom)
    if (review !== null && review.head !== snapshot.head) await update($, reviewAtom, () => null)
    return true
  })
}

// Stores a read of the review sources, unless it was read for a head that is not
// the stored PR's head now, or a newer one is stored.
async function commitReview($: EngineInterface, ref: string, seq: number, head: string, snapshot: ReviewSnapshot | undefined, at: number, cause?: 'user'): Promise<void> {
  await inTurn(async () => {
    if ((await read($, prRef)) !== ref) return
    const pr = await read($, prAtom)
    if (pr === null || pr.head !== head) return
    const mark = await read($, reviewMark)
    if (seq < mark.seq) return
    if (snapshot === undefined) {
      await update($, reviewMark, () => failedMark(mark, seq, at, cause))
      return
    }
    await update($, reviewAtom, () => snapshot)
    await update($, reviewMark, () => ({ seq, okAt: at, failedAt: 0 }))
  })
}

const PR_FIELDS = 'number,title,state,isDraft,headRefOid,reviewDecision,statusCheckRollup,mergeStateStatus,updatedAt'

// One read of GitHub for the followed pull request: the pull request and the list of
// open ones, then, for the head just read, the review sources.
async function readOnce($: EngineInterface): Promise<void> {
  const ref = await read($, prRef)
  if (ref === '') return
  const { repo, number } = parseRef(ref)
  const seq = await inTurn(async () => {
    const n = (await read($, seqAtom)) + 1
    await update($, seqAtom, () => n)
    return n
  })
  const knownMe = await read($, meAtom)
  const [viewOut, listOut, meOut] = await Promise.all([
    run($, ['gh', 'pr', 'view', String(number), '--repo', repo, '--json', PR_FIELDS]),
    run($, ['gh', 'pr', 'list', '--repo', repo, '--state', 'open', '--limit', String(LIST_LIMIT), '--json', 'number']),
    knownMe === '' ? run($, ['gh', 'api', 'user', '--jq', '.login']) : Promise.resolve(knownMe),
  ])
  let snapshot: PrSnapshot | undefined
  try {
    const p = asObj(JSON.parse(viewOut ?? ''))
    if (p.number !== number || str(p.headRefOid) === '') throw new Error('not the pull request asked for')
    snapshot = {
      ref,
      seq,
      head: str(p.headRefOid),
      number,
      title: str(p.title),
      state: str(p.state),
      isDraft: p.isDraft === true,
      reviewDecision: str(p.reviewDecision),
      mergeState: str(p.mergeStateStatus),
      checks: checksOf(p.statusCheckRollup),
    }
    try {
      const all = parsePages(listOut ?? '')
      snapshot.others = { count: all.filter(x => asObj(x).number !== number).length, isLimit: all.length >= LIST_LIMIT }
    } catch {
      // the list is optional: the line is left out
    }
  } catch {
    snapshot = undefined
  }
  const at = await $.clock.now()
  const isStored = await commitPr($, ref, seq, snapshot, at)
  if (!isStored || snapshot === undefined) return

  const me = (meOut ?? '').trim()
  if (me !== '' && knownMe === '') await inTurn(() => update($, meAtom, cur => (cur === '' ? me : cur)))
  const head = snapshot.head
  // Without the agent account's login nothing in the comments can be attributed:
  // the read of the account is what failed, so it is named.
  if (me === '') {
    await commitReview($, ref, seq, head, undefined, await $.clock.now(), 'user')
    return
  }
  const [issueOut, pullOut, reviewsOut] = await Promise.all([
    run($, ['gh', 'api', '--paginate', `repos/${repo}/issues/${number}/comments`]),
    run($, ['gh', 'api', '--paginate', `repos/${repo}/pulls/${number}/comments`]),
    run($, ['gh', 'api', '--paginate', `repos/${repo}/pulls/${number}/reviews`]),
  ])
  let review: ReviewSnapshot | undefined
  try {
    if (issueOut === undefined || pullOut === undefined || reviewsOut === undefined) throw new Error('a review source could not be read')
    review = { ref, seq, head, ...readReview(parsePages(issueOut), parsePages(pullOut), parsePages(reviewsOut), head, me) }
  } catch {
    review = undefined
  }
  await commitReview($, ref, seq, head, review, await $.clock.now())
}

// One read at a time: a request that comes while one runs is folded into one more
// read after it, so a push made during a read is still seen.
type Reader = { isBusy: boolean; isAgain: boolean }
let reader: Reader = { isBusy: false, isAgain: false }
async function refresh($: EngineInterface): Promise<void> {
  const r = reader
  if (r.isBusy) {
    r.isAgain = true
    return
  }
  r.isBusy = true
  try {
    do {
      r.isAgain = false
      try {
        await readOnce($)
      } catch {
        // a failed read is shown by its freshness line
      }
      await invalidate($)
    } while (r.isAgain)
  } finally {
    r.isBusy = false
  }
}

// What the main loop's Bash call says about the session's pull request.
async function afterBash($: EngineInterface, command: string, stdout: string): Promise<void> {
  try {
    if (/\bgh\s+pr\s+create\b/.test(command)) {
      const urls = [...stdout.matchAll(ghPrUrl)]
      const last = urls[urls.length - 1]
      if (last !== undefined) await follow($, `${last[1]}#${last[2]}`)
    } else {
      const target = reviewTarget(command)
      if (target !== undefined) {
        const repo = target.repo ?? (await repoOf($, cdTarget(command)))
        if (repo !== undefined) await follow($, `${repo}#${target.number}`)
      }
    }
    if (REFRESH_COMMAND.test(command)) await refresh($)
  } catch {
    // the next read tries again
  }
}

// What a `mentat check` run says, recorded: a failed run pins one alert (id CHECK_ID), replacing the
// item a former run left; a passing run with warnings pins one warning item in its place; a clean pass removes it. The result is also kept for the footer label.
// isCurrent is asked inside the turn that writes: a run that is no longer the latest writes nothing.
async function recordCheck($: EngineInterface, outcome: CheckRead, isCurrent: () => boolean): Promise<void> {
  const openedAt = await $.clock.now()
  await inTurn(async () => {
    if (!isCurrent()) return
    await update($, items, list => {
      const rest = list.filter(d => d.id !== CHECK_ID)
      if (!outcome.passed) return [...rest, { id: CHECK_ID, kind: 'alert' as const, question: outcome.failedLine, openedAt }]
      if (outcome.warnings.length === 0) return rest
      return [...rest, { id: CHECK_ID, kind: 'warning' as const, question: `Check passed with ${plural(outcome.warnings.length, 'warning', 'warnings')}`, openedAt }]
    })
    await update($, checkResult, () => (outcome.passed ? { state: outcome.warnings.length > 0 ? ('warn' as const) : ('pass' as const), warnings: outcome.warnings } : { state: 'fail' as const, warnings: [] }))
    await update($, sentAtom, list => list.filter(x => x.id !== CHECK_ID))
  })
  await invalidate($)
}

// Counts the check results being recorded: each run takes the next number when it starts (the
// startup run) or when its result is read (the agent's run), and writes only while its number is the
// latest. So an agent's run that lands while the startup run is in flight wins, and a new
// conversation drops the run of the old one.
let checkEpoch = 0

// The main loop's `mentat check` run. A failing check exits 1, so the Bash result may be an error:
// its text is then in `text` (what the model read) and not in the typed record. All the parts are read.
async function afterCheck($: EngineInterface, command: string, ran: { result?: unknown; text?: unknown; deny?: unknown }): Promise<void> {
  try {
    if (!CHECK_COMMAND.test(command) || ran.deny !== undefined) return
    const record = ran.result
    const typed = typeof record === 'object' && record !== null ? (record as { stdout?: unknown; stderr?: unknown; interrupted?: unknown }) : undefined
    if (typed?.interrupted === true) return
    const output = [typed?.stdout, typed?.stderr, typeof record === 'string' ? record : undefined, ran.text]
      .filter((part): part is string => typeof part === 'string')
      .join('\n')
    const outcome = parseCheck(output)
    if (outcome === undefined) return
    const mine = ++checkEpoch
    await recordCheck($, outcome, () => checkEpoch === mine)
  } catch {
    // the check's own output already told the agent
  }
}

// The pane's own `mentat check`, at the start of a conversation (a startup or a reload, and after
// /clear, /resume and a fork), so the footer label is current before any message. Only in a git work
// tree: elsewhere (a folder that is not a repository) the check would fail for a reason that is not
// the project's. A failing check exits 1 and still prints its `Check failed:` line, so the output is
// read whatever the exit code; a `mentat` that cannot run, or output without a final line, records nothing.
async function startCheck($: EngineInterface, cwd?: string): Promise<void> {
  const mine = ++checkEpoch
  try {
    const dir = cwd ?? (await $.session.cwd())
    const inside = await run($, ['git', 'rev-parse', '--is-inside-work-tree'], dir)
    if (inside?.trim() !== 'true') return
    const out = await $.process.run(['mentat', 'check'], { timeoutMs: 30_000, cwd: dir })
    const outcome = parseCheck(`${out.stdout}\n${out.stderr}`)
    if (outcome === undefined) return
    await recordCheck($, outcome, () => checkEpoch === mine)
  } catch {
    // no mentat to run, or the engine is gone: the label stays as it is
  }
}

// A `mentat review` command names its pull request before it runs, so the card is
// there during the long wait for the review.
async function followReview($: EngineInterface, command: string): Promise<void> {
  try {
    const target = reviewTarget(command)
    if (target === undefined) return
    const repo = target.repo ?? (await repoOf($, cdTarget(command)))
    if (repo === undefined) return
    await follow($, `${repo}#${target.number}`)
    await refresh($)
  } catch {
    // afterBash tries again when the command ends
  }
}

async function repoOf($: EngineInterface, cwd?: string): Promise<string | undefined> {
  const out = await run($, ['gh', 'repo', 'view', '--json', 'nameWithOwner', '--jq', '.nameWithOwner'], cwd ?? (await $.session.cwd()))
  const repo = out?.trim()
  return repo !== undefined && /^[^/\s]+\/[^/\s]+$/.test(repo) ? repo : undefined
}

// `/mentat pr <number | #number | owner/repo#number | pull request URL>`
async function resolveTarget($: EngineInterface, arg: string): Promise<string | undefined> {
  const url = /^https:\/\/github\.com\/([^/\s]+\/[^/\s]+)\/pull\/(\d+)/.exec(arg)
  if (url !== null) return `${url[1]}#${url[2]}`
  const full = /^([^/\s#]+\/[^/\s#]+)#(\d+)$/.exec(arg)
  if (full !== null) return `${full[1]}#${full[2]}`
  const bare = /^#?(\d+)$/.exec(arg)
  if (bare === null) return undefined
  const repo = await repoOf($)
  return repo === undefined ? undefined : `${repo}#${bare[1]}`
}

// ---- the module -----------------------------------------------------------------------------

// ---- Drawn desktop design: each card is one themed Svg; buttons stay native. ----
const FONT = "-apple-system,BlinkMacSystemFont,'SF Pro Text','Segoe UI',sans-serif"
const CSS = `<style>
.t{fill:#1d1d1b}.s{fill:#6b6b67}.m{fill:#9b9b96}.k{fill:#e9e8e4}.card{fill:#f6f5f2}.ln{stroke:#e6e5e1}
@media (prefers-color-scheme: dark){.t{fill:#ededeb}.s{fill:#a9a9a4}.m{fill:#7c7c78}.k{fill:#2d2d2b}.card{fill:#1f1f1d}.ln{stroke:#33332f}}
</style>`
const HUE = { amber: '#C98A0E', blue: '#3D7FE6', green: '#2F9461', red: '#D0453F', violet: '#8B5CF6', teal: '#1E9E9A', grey: '#8f8f8a' }

const xml = (s: string): string => s.replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c] ?? c)
const charEm = (ch: string): number => (/[\s.,:;'|!il1()[\]]/.test(ch) ? 0.3 : /[A-Z@%mw#]/.test(ch) ? 0.72 : 0.56)
const textW = (s: string, size: number): number => [...s].reduce((w, ch) => w + charEm(ch) * size, 0)
const fit = (s: string, size: number, maxW: number): string => {
  if (textW(s, size) <= maxW) return s
  let out = ''
  for (const ch of s) {
    if (textW(out + ch + '…', size) > maxW) break
    out += ch
  }
  return out + '…'
}
const svgOf = (W: number, H: number, body: string): string =>
  `<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}" viewBox="0 0 ${W} ${H}">${CSS}${body}</svg>`
const agentMark = (x: number, y: number, status: AgentStatus): string => {
  if (isActive(status)) return `<circle cx="${x}" cy="${y}" r="7" fill="${HUE.blue}" opacity="0.18"/><circle cx="${x}" cy="${y}" r="3.5" fill="${HUE.blue}"/>`
  if (status === 'completed') return `<circle cx="${x}" cy="${y}" r="8" fill="${HUE.green}" opacity="0.14"/><path d="M${x - 3.5} ${y}l2.5 2.5 4.5-5" fill="none" stroke="${HUE.green}" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"/>`
  if (status === 'failed' || status === 'killed') return `<circle cx="${x}" cy="${y}" r="8" fill="${HUE.red}" opacity="0.14"/><path d="M${x - 3} ${y - 3}l6 6M${x + 3} ${y - 3}l-6 6" stroke="${HUE.red}" stroke-width="1.7" stroke-linecap="round"/>`
  return `<circle cx="${x}" cy="${y}" r="7" fill="none" class="m" stroke="${HUE.grey}" stroke-width="1.3"/>`
}

// The role of an agent by its type: the label shown, its color and its glyph.
type Role = 'builder' | 'explore' | 'plan' | 'other'
const ROLE_HUE: Record<Role, string> = { builder: HUE.violet, explore: HUE.blue, plan: HUE.teal, other: HUE.grey }
const roleOf = (type: string): { role: Role; label: string } => {
  const t = type.toLowerCase()
  if (t === 'builder' || t === 'mentat:builder') return { role: 'builder', label: 'builder' }
  if (t === 'explore') return { role: 'explore', label: 'explore' }
  if (t === 'plan') return { role: 'plan', label: 'plan' }
  return { role: 'other', label: type }
}
// The terminal's one-character mark for a role, where the desktop draws its glyph.
const ROLE_MARK: Record<Role, string> = { builder: '◆', explore: '◎', plan: '◇', other: '·' }
// Glyphs on a 24 by 24 grid, drawn in the role color: a wrench, a magnifier, a compass, a dot.
const GLYPH: Record<Role, string> = {
  builder: '<path d="M13 11L5 19"/><path d="M16.7 3.9A4.2 4.2 0 1 0 20.1 7.3"/>',
  explore: '<circle cx="10.5" cy="10.5" r="6"/><path d="M15 15l5 5"/>',
  plan: '<circle cx="12" cy="12" r="8.5"/><path d="M15.8 8.2l-2.1 5.5-5.5 2.1 2.1-5.5z"/>',
  other: '<circle cx="12" cy="12" r="4" stroke="none" fill="HUE"/>',
}
// A tinted tile with the role's glyph, centered on (cx, cy); a finished agent's is dimmed.
const roleIcon = (cx: number, cy: number, role: Role, isDone: boolean): string => {
  const hue = ROLE_HUE[role]

  return `<g opacity="${isDone ? 0.55 : 1}"><rect x="${cx - 12}" y="${cy - 12}" width="24" height="24" rx="7" fill="${hue}" opacity="0.14"/><g data-role="${role}" transform="translate(${cx - 7.2} ${cy - 7.2}) scale(0.6)" fill="none" stroke="${hue}" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round">${GLYPH[role].replace('HUE', hue)}</g></g>`
}

type AgentCardRow = { status: AgentStatus; title: string; type: string; model: string; stats: string }
export const AGENT_ROW_H = 34
export const AGENT_HEAD_H = 30
// One group of agents as its own card: an optional header, then one-line rows. Left to right a row
// has the role icon, the title, the model and effort (dimmer) after it, the stats (tokens and
// elapsed time, right-aligned) and the status mark on the right edge. A long title is cut with an
// ellipsis, and the model after it when there is still not room. The role is in the alt text.
const agentsSvg = (W: number, header: string | undefined, rows: AgentCardRow[]): { svg: string; h: number } => {
  const top = header === undefined ? 4 : AGENT_HEAD_H
  const h = top + rows.length * AGENT_ROW_H + 4
  const tx = 48
  const gap = 10
  const body = rows.map((r, i) => {
    const y = top + i * AGENT_ROW_H
    const cy = y + AGENT_ROW_H / 2
    const done = isEnded(r.status)
    const { role } = roleOf(r.type)
    const statsX = W - 44
    const statsW = r.stats === '' ? 0 : textW(r.stats, 11.5)
    // The room from the title's left edge to the stats (or the mark, when there are no stats).
    const room = statsX - tx - (statsW === 0 ? 0 : statsW + 14)
    const modelW = r.model === '' ? 0 : textW(r.model, 12)
    let title = r.title
    let model = r.model
    if (textW(title, 14) + (modelW === 0 ? 0 : gap + modelW) > room) {
      title = fit(r.title, 14, Math.max(room * 0.6, room - (modelW === 0 ? 0 : gap + modelW)))
      const left = room - textW(title, 14) - gap
      model = left < 40 ? '' : fit(r.model, 12, left)
    }
    // A finished agent is drawn in the muted color, so running work stands out; its mark keeps its own.
    return `${roleIcon(24, cy, role, done)}
<text class="${done ? 'm' : 't'}" x="${tx}" y="${cy + 5}" font-family="${FONT}" font-size="14" font-weight="${isActive(r.status) ? 600 : 500}">${xml(title)}</text>
${model === '' ? '' : `<text class="${done ? 'm' : 's'}" x="${Math.round(tx + textW(title, 14) + gap)}" y="${cy + 4.5}" font-family="${FONT}" font-size="12">${xml(model)}</text>`}
${r.stats === '' ? '' : `<text class="${done ? 'm' : 's'}" x="${statsX}" y="${cy + 4}" text-anchor="end" font-family="${FONT}" font-size="11.5" font-variant-numeric="tabular-nums">${xml(r.stats)}</text>`}
${agentMark(W - 26, cy, r.status)}
${i < rows.length - 1 ? `<line class="ln" x1="${tx}" y1="${y + AGENT_ROW_H}" x2="${W - 16}" y2="${y + AGENT_ROW_H}"/>` : ''}`
  })
  const head = header === undefined ? '' : `<text class="s" x="16" y="21" font-family="${FONT}" font-size="12.5" font-weight="600">${xml(header)}</text>`

  return { svg: svgOf(W, h, `<rect class="card" x="0" y="0" width="${W}" height="${h}" rx="10"/>${head}${body.join('')}`), h }
}
// The alt text of a group: its heading and count, then each agent's role and title (the role is not drawn as text).
const agentsAlt = (heading: string, rows: AgentCardRow[]): string =>
  `${heading}: ${rows.length} (${rows.map(r => `${roleOf(r.type).label}: ${r.title}`).join('; ')})`

// What the band's left side shows, in this order: the item that waits on the maintainer (the most
// urgent: alert, question, check warning, action; the newest within a kind), a budget warning,
// the newest Log note, and last a quiet `Mentat` line.
type BandKind = DecisionKind | 'budget'
type BandLeft = { kind: BandKind; text: string } | { kind: 'note'; text: string; icon: string; hue: string } | { kind: 'quiet'; text: string }
const MARK: Record<BandKind, { char: string; hue: string }> = {
  alert: { char: '!', hue: HUE.red },
  question: { char: '?', hue: HUE.amber },
  warning: { char: '!', hue: HUE.amber },
  action: { char: '→', hue: HUE.blue },
  budget: { char: '!', hue: HUE.amber },
}
// The description of an item in the desktop band's alt text.
const ITEM_ALT: Record<DecisionKind, string> = { question: 'Question', action: 'Waiting on you', alert: 'Alert', warning: 'Check warnings' }
// The item that waits on the maintainer and comes first: alert, then question, check warning, action;
// the newest of its kind. The rest are counted in `+N more`.
const mostUrgent = (list: Decision[]): Decision | undefined =>
  [...list].reverse().sort((a, b) => KIND_RANK[kindOf(a)] - KIND_RANK[kindOf(b)])[0]

// One line, drawn as a single Svg on the desktop: a mark and the text, and at the right the `+N more` pill
// when more than one item waits. The buttons are native, beside it.
const bandSvg = (W: number, left: BandLeft, more: string): string => {
  const pillW = more === '' ? 0 : Math.round(20 + textW(more, 12))
  const room = W - pillW - 16
  const mark = left.kind === 'quiet' ? undefined : left.kind === 'note' ? { char: left.icon, hue: left.hue } : MARK[left.kind]
  const leftSvg =
    mark === undefined
      ? `<text class="m" x="2" y="18.5" font-family="${FONT}" font-size="13" font-weight="500">${xml(left.text)}</text>`
      : `<circle cx="11" cy="14" r="8" fill="${mark.hue}" opacity="0.18"/><text fill="${mark.hue}" x="11" y="18.5" text-anchor="middle" font-family="${FONT}" font-size="12" font-weight="700">${xml(mark.char)}</text>
<text class="t" x="27" y="18.5" font-family="${FONT}" font-size="13" font-weight="500">${xml(fit(left.text, 13, room - 30))}</text>`
  const hue = mark?.hue ?? HUE.grey
  const pill = more === '' ? '' : `<rect x="${W - pillW}" y="4" width="${pillW}" height="20" rx="10" fill="${hue}" opacity="0.18"/><text fill="${hue}" x="${W - pillW / 2}" y="18" text-anchor="middle" font-family="${FONT}" font-size="12" font-weight="600">${xml(more)}</text>`
  return svgOf(W, 28, leftSvg + pill)
}
// The width a native button takes beside the band's Svg, roughly.
const buttonW = (text: string): number => Math.round(textW(text, 13) + 40)

// The short line that takes the place of a question's answer button once the answer is sent; it says
// the answer is queued until the prompt has entered the session.
const sentLine = (entry: { text: string; isDelivered?: boolean }): string => {
  const text = entry.text.length > 20 ? `${entry.text.slice(0, 19)}…` : entry.text

  return `Sent: ${text}${entry.isDelivered === true ? '' : ' · queued'}`
}
// True when the answer was taken (queued or in the conversation). The prompt of a plugin runs once
// Claude Code is idle, so while a turn runs this waits for the turn: the question is marked sent
// first, and a second press for it does nothing. When the prompt did not enter, say so: a press
// that vanishes looks broken.
async function sendAnswer($: EngineInterface, d: { id: string; question: string }, text: string): Promise<boolean> {
  const isFirst = await inTurn(async () => {
    if ((await read($, sentAtom)).some(x => x.id === d.id)) return false
    await update($, sentAtom, list => [...list, { id: d.id, text }])
    return true
  })
  if (!isFirst) return false
  // A submit the engine rejects (for example around a reload) did not enter either.
  let isTaken = false
  try {
    const sent = await $.prompt.submit({ text: `Answer to decision ${d.id} ("${d.question}"): ${text}` })
    isTaken = sent.drop === undefined
  } catch {
    isTaken = false
  }
  if (!isTaken) {
    await inTurn(() => update($, sentAtom, list => list.filter(x => x.id !== d.id || x.isDelivered === true)))
    $.ui.toast('Answer not sent: Claude Code did not take it. Press again.')
    return false
  }
  // The answer entered the session; the line stops saying it waits.
  await inTurn(() => update($, sentAtom, list => list.map(x => (x.id === d.id ? { ...x, isDelivered: true } : x))))
  return true
}
const dismissItem = ($: EngineInterface, id: string) =>
  inTurn(async () => {
    await update($, items, all => all.filter(x => x.id !== id))
    await update($, sentAtom, list => list.filter(x => x.id !== id))
  })

export const register: Register = (on, _options) => {
  // The effort an Agent call asked for, until the agent it spawns is recorded.
  const effortByCall = new Map<string, string>()
  // The effort an agent's latest model request used, by agent id. It also holds a value that
  // arrived before the agent's row did; agent.spawn applies it when the row appears.
  const effortByAgent = new Map<string, string>()
  let agentTimer: { cancel: () => void } | undefined
  let refreshTimer: { cancel: () => void } | undefined

  on('session.start', async ($, e, next) => {
    await $.command.register({
      name: 'mentat',
      description: 'Show the log, the agents and, on the terminal, the pull request in a pane',
      argumentHint: '[pr <number>]',
      immediate: true,
    })
    await $.tool.register({
      name: 'open_decision',
      description:
        'Record something that waits on the user, so it stays in their Mentat pane until settled. ' +
        'kind "question" (the default) is a question or decision you have just put to them in chat: one call per real question that waits on them (not rhetorical ones, not routine status). ' +
        'kind "action" is something only the user can do (a merge, a manual test, a plugin update after a merge, rotating a secret); link is the issue or pull request that holds the steps. ' +
        'kind "alert" is a failure you could not resolve, a blocking disagreement on a review finding, or an exposed secret. ' +
        'Returns an id; call close_decision with that id when the user answers, the action is done or the item no longer applies.',
      inputSchema: {
        type: 'object',
        properties: {
          kind: {
            type: 'string',
            enum: ['question', 'action', 'alert'],
            description: 'question (the default), action (something only the user can do) or alert (a failure you could not resolve)',
          },
          question: { type: 'string', description: 'The question, or for an action or alert what it is, in one short plain sentence' },
          link: { type: 'string', description: 'An https URL: the issue or pull request that holds the steps. Anything else is ignored' },
          recommendation: { type: 'string', description: 'Your recommendation, in a few words, if you gave one' },
          accept: {
            type: 'string',
            description:
              'For a question: if your recommendation can be taken with one press, the label of that answer (for example Yes); the pane shows it as a button. Ignored for an action or alert',
          },
        },
        required: ['question'],
      },
      isDeferred: false,
    })
    await $.tool.register({
      name: 'close_decision',
      description: 'Close a question, action or alert opened with open_decision once it is settled or no longer applies.',
      inputSchema: {
        type: 'object',
        properties: {
          id: { type: 'string', description: 'The id open_decision returned' },
          outcome: { type: 'string', description: 'What was decided, in a few words' },
        },
        required: ['id'],
      },
      isDeferred: false,
    })
    await $.tool.register({
      name: 'note',
      description:
        'Add one plain line to the Log in the user\'s Mentat pane, a short running record of the session. ' +
        'Add a note only at a notable moment: a decision the user made, a change of plan, something surprising you found, what you now wait on, or a piece of work finished. ' +
        'Write one line in plain words. A few notes an hour at most, and never for routine steps such as reading files, running tests or opening a pull request. ' +
        'Returns a short acknowledgement.',
      inputSchema: {
        type: 'object',
        properties: {
          text: { type: 'string', description: 'One plain line, about 80 characters at most; longer text is cut with an ellipsis' },
          kind: {
            type: 'string',
            enum: [...NOTE_KINDS],
            description: 'decision, plan (the default), surprise, waiting or done',
          },
        },
        required: ['text'],
      },
      isDeferred: false,
    })

    // A (re)load: reconcile the agents with the engine's list and start the timers
    // over; reads that a former load left running are told apart by their sequence number.
    // The former decisions pane kept settled entries (with closedAt) in this state;
    // nothing shows them now, so they must not come back as open questions.
    await inTurn(() => update($, items, withoutSettled))
    // A submit that was still waiting for a turn is lost with the old load: its question
    // offers its buttons again. A delivered answer stays marked.
    await inTurn(() => update($, sentAtom, list => list.filter(x => x.isDelivered === true)))
    reader = { isBusy: false, isAgain: false }
    agentTimer?.cancel()
    refreshTimer?.cancel()
    await syncAgents($, effortByAgent)
    agentTimer = $.clock.every(1000, () => void agentTick($, effortByAgent))
    refreshTimer = $.clock.every(60_000, () => void refresh($))
    void refresh($)
    void startCheck($, e.cwd)

    return next(e)
  })

  // A different conversation starts (/clear, /resume, /branch): the pull request of
  // the old one is not this session's, and neither are its open questions. A mod reload (session.start), a startup and a
  // compaction are the same conversation and keep it.
  on('classic.SessionStart', async ($, e, next) => {
    if (e.source === 'clear' || e.source === 'resume' || e.source === 'fork') {
      await follow($, '')
      // A check still running for the old conversation writes nothing.
      checkEpoch += 1
      // Open questions belong to the conversation they were asked in.
      await inTurn(async () => {
        await update($, items, () => [])
        await update($, sentAtom, () => [])
        // The last check was of the old conversation too.
        await update($, checkResult, () => null)
        // So is the log.
        await update($, logAtom, () => [])
      })
      await invalidate($)
      // The new conversation's check.
      void startCheck($)
    }

    return next(e)
  })

  on('command.run', { command: 'mentat' }, async ($, e) => {
    const args = e.args.trim()
    if (args === '') {
      await $.ui.open({ id: PANE, title: TITLE })

      return { text: 'Mentat pane opened.' }
    }
    const m = /^pr\s+(\S+)$/.exec(args)
    const ref = m === null ? undefined : await resolveTarget($, m[1]!)
    if (ref === undefined) {
      return { text: 'Usage: /mentat, or /mentat pr <number | owner/repo#number | pull request URL>' }
    }
    await follow($, ref)
    void refresh($)

    return { text: `Following ${ref}.` }
  })

  on('tool.call', { tool: OPEN_TOOL }, async ($, e) => {
    const input = e as unknown as { kind?: unknown; question?: unknown; recommendation?: unknown; accept?: unknown; link?: unknown }
    const question = typeof input.question === 'string' ? input.question.trim() : ''
    if (question === '') {
      return { deny: 'open_decision needs a question.' }
    }
    if (input.kind !== undefined && !isKind(input.kind)) {
      return { deny: 'open_decision kind must be question, action or alert.' }
    }
    const kind: DecisionKind = input.kind ?? 'question'
    const optional = (v: unknown) => (typeof v === 'string' && v.trim() !== '' ? v.trim() : undefined)
    const recommendation = optional(input.recommendation)
    // Only a question has answer buttons.
    const accept = kind === 'question' ? optional(input.accept) : undefined
    const link = httpsLink(input.link)
    const id = await inTurn(async () => {
      const n = await read($, nextId)
      await update($, nextId, () => n + 1)
      const openedAt = await $.clock.now()
      await update($, items, list =>
        [...list, { id: `d${n}`, ...(kind === 'question' ? {} : { kind }), question, ...(link === undefined ? {} : { link }), recommendation, accept, openedAt }],
      )
      return `d${n}`
    })
    await invalidate($)

    return { result: `Opened decision ${id}.` }
  })

  on('tool.call', { tool: CLOSE_TOOL }, async ($, e) => {
    const input = e as unknown as { id?: unknown }
    const id = typeof input.id === 'string' ? input.id : ''
    const isClosed = await inTurn(async () => {
      const list = await read($, items)
      if (!list.some(d => d.id === id)) {
        return false
      }
      // A closed decision is dropped: nothing shows settled ones.
      await update($, items, all => all.filter(d => d.id !== id))
      await update($, sentAtom, sent => sent.filter(x => x.id !== id))
      return true
    })
    if (!isClosed) {
      return { deny: `No open decision with id ${id}.` }
    }
    await invalidate($)

    return { result: `Closed decision ${id}.` }
  })

  on('tool.call', { tool: NOTE_TOOL }, async ($, e) => {
    const input = e as unknown as { text?: unknown; kind?: unknown }
    const text = typeof input.text === 'string' ? oneLine(input.text, LOG_WIDTH) : ''
    if (text === '') {
      return { deny: 'note needs a line of text.' }
    }
    if (input.kind !== undefined && !isNoteKind(input.kind)) {
      return { deny: `note kind must be ${NOTE_KINDS.join(', ')}.` }
    }
    const kind: LogKind = input.kind ?? 'plan'
    await inTurn(async () => addLog($, await $.clock.now(), [{ kind, text }]))
    await invalidate($)

    return { result: 'Noted.' }
  })

  on('tool.call', async ($, e, next) => {
    if (e.tool === 'Agent') {
      const effort = (e as unknown as { effort?: unknown }).effort
      if (typeof effort === 'string') effortByCall.set(e.tool_use_id, effort)
    }
    const isMainBash = e.tool === 'Bash' && e.agentId === undefined && typeof e.command === 'string'
    if (isMainBash) void followReview($, e.command as string)
    const ran = await next(e)
    if (isMainBash) {
      const stdout = str(asObj((ran as { result?: unknown }).result).stdout)
      void afterBash($, e.command as string, stdout)
      await afterCheck($, e.command as string, ran as { result?: unknown; text?: unknown; deny?: unknown })
    }

    return ran
  })

  on('agent.spawn', async ($, e, next) => {
    const startedAt = await $.clock.now()
    const out = await next(e)
    if (out.deny !== undefined) return out
    const id = out.agentId ?? e.tool_use_id
    const row: AgentRow = {
      id,
      type: e.subagentType,
      description: e.description,
      status: 'running',
      startedAt,
    }
    const model = out.model ?? e.model
    if (model !== undefined && model !== '') row.model = model
    const effort = effortByAgent.get(id) ?? effortByCall.get(e.tool_use_id)
    if (effort !== undefined) row.effort = effort
    effortByCall.delete(e.tool_use_id)
    await inTurn(async () => {
      await update($, agents, list => [...list.filter(a => a.id !== id), row].slice(-30))
    })
    await invalidate($)

    return out
  })

  // The effort each of a subagent's requests uses, which the Agent call's own effort often
  // leaves out. The request passes through as it came, and the write never waits for it.
  on('turn.step', async function* ($, e, next) {
    const id = e.agentId
    if (id !== undefined && e.effort !== undefined) {
      const shown = showEffort(e.effort)
      if (effortByAgent.get(id) !== shown) {
        effortByAgent.set(id, shown)
        void inTurn(async () => {
          const rows = await read($, agents)
          if (!rows.some(r => r.id === id && r.effort !== shown)) return
          await update($, agents, list => list.map(r => (r.id === id ? { ...r, effort: shown } : r)))
          await invalidate($)
        }).catch(() => undefined)
      }
    }

    return yield* next(e)
  })

  on('turn.complete', async ($, e, next) => {
    const id = e.agentId
    if (id !== undefined) {
      const u = e.usage
      const tokens =
        u === undefined ? undefined : (u.input_tokens ?? 0) + (u.cache_creation_input_tokens ?? 0) + (u.output_tokens ?? 0)
      if (tokens !== undefined) {
        await inTurn(() => update($, agents, rows => rows.map(r => (r.id === id ? { ...r, tokens } : r))))
      }
      // A subagent's turn is not its end: only the engine's list says that.
      await syncAgents($, effortByAgent)
      await invalidate($)
    }

    return next(e)
  })

  // The footer label: Mentat's state in the prompt footer, before the engine's own mode labels.
  // Dim until a `mentat check` has run, then green, amber with the warning count, or red.
  on('ui.render', { component: 'SessionMode' }, async ($, e, next) => {
    if (e.surface !== 'terminal' && e.surface !== 'desktop') return next(e)
    const result = await read($, checkResult)
    const { Box, Text } = $.ui.resolve(e)
    const modes = e.props.modes
    const [text, color] =
      result === null
        ? ['● Mentat', undefined]
        : result.state === 'fail'
          ? ['● Mentat check failed', 'error']
          : result.state === 'warn'
            ? [`● Mentat · ${plural(result.warnings.length, 'warning', 'warnings')}`, 'warning']
            : ['● Mentat', 'success']

    return (
      <Box flexDirection="row" gap={1}>
        {color === undefined ? <Text dimColor>{text}</Text> : <Text color={color}>{text}</Text>}
        {modes.length > 0 && <Text dimColor>{modes.join(' & ')}</Text>}
      </Box>
    )
  })

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    if (e.props.hasSurvey) {
      return next(e)
    }
    // The band is always there: what waits on the maintainer, else a budget warning, else the newest
    // Log note, else a quiet line. Nothing in it comes from GitHub.
    const open = await read($, items)
    const now = await $.clock.now()
    const urgent = mostUrgent(open)
    // Budget raises it only when no item waits. Nothing redraws the band for a change of usage alone;
    // it is read when the band is drawn (see the report).
    const budget = urgent === undefined ? budgetAlert(limitsOf(await readUsage($), now, await readZone($))) : undefined
    const logList = urgent === undefined && budget === undefined ? await read($, logAtom) : []
    const note = logList[logList.length - 1]
    const left: BandLeft =
      urgent !== undefined
        ? { kind: kindOf(urgent), text: urgent.question }
        : budget !== undefined
          ? { kind: 'budget', text: budget }
          : note !== undefined
            ? { kind: 'note', text: note.text, icon: LOG_STYLE[note.kind].icon, hue: LOG_STYLE[note.kind].hue }
            : { kind: 'quiet', text: TITLE }
    const more = open.length > 1 ? `+${open.length - 1} more` : ''
    // The urgent item's controls: a question with a recommended answer has a one-press button (a line
    // in its place once sent), every item has Dismiss, and an action or alert may carry a link.
    const sent = urgent === undefined ? undefined : (await read($, sentAtom)).find(x => x.id === urgent.id)
    const answer = urgent !== undefined && kindOf(urgent) === 'question' && sent === undefined ? urgent.accept : undefined
    const link = urgent !== undefined && kindOf(urgent) !== 'question' ? urgent.link : undefined
    const { Box, Button, Link, Text } = $.ui.resolve(e)
    // One row, never wrapped: the answer button (or the sent line), Dismiss, the link, then Details. It
    // is one Box with every child its own, not a fragment: a fragment's children are not laid out as one row.
    const controls = () => (
      <Box flexDirection="row" alignItems="center" gap={1} flexShrink={0}>
        {answer !== undefined && urgent !== undefined && (
          <Button key={`accept-${urgent.id}`} label={answer} variant="primary" onPress={() => sendAnswer($, urgent, answer)} />
        )}
        {sent !== undefined && <Text dimColor>{sentLine(sent)}</Text>}
        {urgent !== undefined && <Button key={`dismiss-${urgent.id}`} label="Dismiss" onPress={() => dismissItem($, urgent.id)} />}
        {link !== undefined && (
          <Text>
            <Link href={link} label={linkLabel(link)} />
          </Text>
        )}
        <Button key="open" label="Details" onPress={() => $.ui.open({ id: PANE, title: TITLE })} />
      </Box>
    )
    // The band is shared: what the plugins beneath draw stays, under this row.
    const beneath = await next(e)
    if (e.surface === 'desktop') {
      const { Svg } = $.ui.resolve(e as typeof e & { surface: 'desktop' })
      // The Svg leaves room for the native buttons beside it.
      const beside =
        (urgent === undefined ? 0 : buttonW('Dismiss') + 8) +
        (answer === undefined ? 0 : buttonW(answer) + 8) +
        (sent === undefined ? 0 : Math.round(textW(sentLine(sent), 12)) + 8) +
        (link === undefined ? 0 : Math.round(textW(linkLabel(link), 13)) + 8)
      const W = Math.max(160, (e.props.bodyColumns ?? 80) * 8 - 96 - beside)
      const alt = `${left.kind === 'budget' || left.kind === 'quiet' ? '' : left.kind === 'note' ? 'Note: ' : `${ITEM_ALT[left.kind]}: `}${left.text}${more === '' ? '' : ` (${more})`}`
      return (
        <Box flexDirection="column">
          <Box flexDirection="row" alignItems="center" justifyContent="space-between" gap={1}>
            <Svg source={bandSvg(W, left, more)} alt={alt} width={W} height={28} />
            {controls()}
          </Box>
          {beneath}
        </Box>
      )
    }

    return (
      <Box flexDirection="column">
        <Box flexDirection="row" alignItems="center" justifyContent="space-between" gap={2}>
          <Box flexDirection="row" alignItems="center" gap={1} flexShrink={1}>
            {left.kind === 'budget' && <Text color="warning" wrap="truncate-end">{left.text}</Text>}
            {left.kind === 'alert' && <Text color="error">!</Text>}
            {left.kind === 'question' && <Text dimColor>?</Text>}
            {left.kind === 'warning' && <Text color="warning">!</Text>}
            {left.kind === 'action' && <Text color="suggestion">→</Text>}
            {left.kind === 'note' && <Text color={LOG_STYLE[note!.kind].color}>{left.icon}</Text>}
            {left.kind === 'quiet' && <Text dimColor>{left.text}</Text>}
            {left.kind !== 'budget' && left.kind !== 'quiet' && <Text wrap="truncate-end">{left.text}</Text>}
            {more !== '' && <Text dimColor>{more}</Text>}
          </Box>
          {controls()}
        </Box>
        {beneath}
      </Box>
    )
  })

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const { Box, Button, Text } = $.ui.resolve(e)
    const Svg = e.surface === 'desktop' ? $.ui.resolve(e as typeof e & { surface: 'desktop' }).Svg : undefined
    const now = await $.clock.now()
    const cols = e.props.bodyColumns ?? 50
    const isNarrow = cols < 48
    // What waits on the maintainer is in the band, not here; the pane only knows whether anything does.
    const open = await read($, items)
    const ref = await read($, prRef)
    const pr = await read($, prAtom)
    const review = await read($, reviewAtom)
    const pm = await read($, prMark)
    const rm = await read($, reviewMark)
    const rows = [...(await read($, agents))].sort((a, b) => {
      if (isActive(a.status) !== isActive(b.status)) return isActive(a.status) ? -1 : 1
      return (b.startedAt ?? 0) - (a.startedAt ?? 0)
    })
    const isHidden = await read($, finishedHidden)
    // Agents that have not ended (running, waiting, idle) first, then the finished ones.
    const liveRows = rows.filter(a => !isEnded(a.status))
    const doneRows = rows.filter(a => isEnded(a.status))
    const toggleFinished = () => inTurn(() => update($, finishedHidden, v => !v))
    // The terminal's card: no background, because a terminal draws an 8-digit hex tint as an opaque grey.
    // The kind is marked by its heading's color.
    const Card = ({ children }: { children?: RenderChildren }) => (
      <Box flexDirection="column" marginTop={1}>
        {children}
      </Box>
    )
    const Heading = ({ label, color }: { label: string; color?: string }) => (
      <Box flexDirection="row" marginBottom={1}>
        <Text bold color={color ?? 'subtle'}>
          {label.toUpperCase()}
        </Text>
      </Box>
    )
    const Fact = ({ label, value, color }: { label: string; value: string; color?: string }) => (
      <Box flexDirection="row" gap={1}>
        <Box width={7} flexShrink={0}>
          <Text dimColor>{label}</Text>
        </Box>
        <Text color={color ?? 'text'} wrap="truncate-end">
          {value}
        </Text>
      </Box>
    )

    // One agent on the terminal, on one line: a mark for its role, the description (cut with an
    // ellipsis when long), the model and effort, the tokens and elapsed time, and the status mark at
    // the end. The status is also said in words when the mark cannot (waiting, idle, failed, killed, ended).
    // No background colors: the terminal draws the desktop's alpha tints as solid grey.
    const termRow = (a: AgentRow, i: number) => {
      const ms = a.startedAt === undefined ? undefined : (a.endedAt ?? now) - a.startedAt
      const model = [a.model === undefined ? undefined : shortModel(a.model), isNarrow ? undefined : a.effort].filter(Boolean).join(' · ')
      const word = a.status === 'running' || a.status === 'completed' ? undefined : a.status === 'unknown' ? 'ended' : a.status
      const stats = [word, ms === undefined ? undefined : duration(ms), isNarrow || a.tokens === undefined ? undefined : `${kTokens(a.tokens)} tokens`]
        .filter(Boolean)
        .join(' · ')
      const color = isActive(a.status) ? 'suggestion' : a.status === 'failed' || a.status === 'killed' ? 'error' : a.status === 'completed' ? 'success' : 'subtle'
      return (
        <Box key={a.id} flexDirection="row" gap={1}>
          <Text dimColor={isEnded(a.status)}>{ROLE_MARK[roleOf(a.type).role]}</Text>
          <Box flexGrow={1} flexShrink={1}>
            <Text bold={isActive(a.status)} dimColor={isEnded(a.status)} wrap="truncate-end">
              {a.description}
            </Text>
          </Box>
          {model !== '' && (
            <Text dimColor wrap="truncate-end">
              {model}
            </Text>
          )}
          {stats !== '' && (
            <Text dimColor wrap="truncate-end">
              {stats}
            </Text>
          )}
          <Text color={color}>{isActive(a.status) ? '●' : a.status === 'completed' ? '✓' : a.status === 'failed' || a.status === 'killed' ? '✕' : '○'}</Text>
        </Box>
      )
    }

    // A freshness line only when a read failed or is more than five minutes old.
    const freshness = (what: string, mark: ReadMark): string | undefined => {
      if (mark.failedAt > 0) {
        return `${mark.cause === 'user' ? 'GitHub user' : what} read failed${mark.okAt > 0 ? ` (last ok ${ago(now - mark.okAt)})` : ''}`
      }
      if (mark.okAt > 0 && now - mark.okAt > STALE_MS) return `${what} read ${Math.floor((now - mark.okAt) / 60_000)}m old`
      return undefined
    }
    // The Log card: the newest entries first, the last LOG_SHOWN of them until `Show all`. Plain text
    // rows on both surfaces, with no background: an 8-digit hex tint renders as solid grey in a terminal.
    const logList = await read($, logAtom)
    const isLogAll = await read($, logAll)
    const zone = await readZone($)
    const toggleLog = () => inTurn(() => update($, logAll, v => !v))
    const logRows = logList.map((entry, n) => ({ entry, n })).reverse()
    const logCard = (marginTop: number) =>
      logList.length === 0 ? undefined : (
        <Box flexDirection="column" marginTop={marginTop}>
          <Heading label="Log" />
          {(isLogAll ? logRows : logRows.slice(0, LOG_SHOWN)).map(({ entry, n }) => (
            <Box key={`log-${n}`} flexDirection="row" gap={1}>
              <Box width={8} flexShrink={0} justifyContent="flex-end">
                <Text dimColor>{clockAt(entry.at, zone)}</Text>
              </Box>
              <Text color={LOG_STYLE[entry.kind].color}>{LOG_STYLE[entry.kind].icon}</Text>
              <Text wrap="truncate-end">{entry.text}</Text>
            </Box>
          ))}
          {logList.length > LOG_SHOWN && (
            <Box flexDirection="row" marginTop={1}>
              <Button key="log-toggle" label={isLogAll ? 'Show fewer' : `Show all ${logList.length}`} onPress={toggleLog} />
            </Box>
          )}
        </Box>
      )
    const prFresh = freshness('PR', pm)
    const reviewFresh = freshness('Review', rm)
    const isReviewed = pr !== null && review !== null && review.head === pr.head
    const ci = pr === null ? undefined : ciLine(pr.checks)
    const others = pr?.others
    if (Svg !== undefined) {
      const W = Math.max(220, Math.min(900, cols * 8 - 24))
      const agentRow = (a: AgentRow): AgentCardRow => {
        const ms = a.startedAt === undefined ? undefined : (a.endedAt ?? now) - a.startedAt
        const elapsed = ms === undefined ? (a.status === 'unknown' ? 'ended' : '') : duration(ms)

        return {
          status: a.status,
          title: a.description,
          type: a.type,
          model: [a.model === undefined ? undefined : shortModel(a.model), a.effort].filter(Boolean).join(' · '),
          stats: [a.tokens === undefined ? undefined : `${kTokens(a.tokens)} tokens`, elapsed === '' ? undefined : elapsed].filter(Boolean).join(' · '),
        }
      }
      const liveRowsSvg = liveRows.map(agentRow)
      const doneRowsSvg = doneRows.map(agentRow)
      const liveCard = liveRows.length === 0 ? undefined : agentsSvg(W, `Running · ${liveRows.length}`, liveRowsSvg)
      const doneCard = doneRows.length === 0 || isHidden ? undefined : agentsSvg(W, undefined, doneRowsSvg)
      return (
        <Box flexDirection="column" paddingX={1}>
          {open.length === 0 && logList.length === 0 && rows.length === 0 && (
            <Box marginTop={SECTION_GAP}>
              <Text dimColor>Nothing waiting on you.</Text>
            </Box>
          )}
          {logCard(SECTION_GAP)}
          {rows.length > 0 && (
            <Box flexDirection="column" marginTop={SECTION_GAP}>
              {liveCard !== undefined && <Svg source={liveCard.svg} alt={agentsAlt('Running agents', liveRowsSvg)} width={W} height={liveCard.h} />}
              {doneRows.length > 0 && (
                <Box flexDirection="row" marginTop={liveCard === undefined ? 0 : 1}>
                  <Button key="finished-toggle" label={`${isHidden ? '▸' : '▾'} Finished · ${doneRows.length}`} onPress={toggleFinished} />
                </Box>
              )}
              {doneCard !== undefined && (
                <Box marginTop={1}>
                  <Svg source={doneCard.svg} alt={agentsAlt('Finished agents', doneRowsSvg)} width={W} height={doneCard.h} />
                </Box>
              )}
            </Box>
          )}
        </Box>
      )
    }

    return (
      <Box flexDirection="column" paddingX={1}>
        {ref === '' && open.length === 0 && logList.length === 0 && rows.length === 0 && <Text dimColor>Nothing waiting on you.</Text>}

        {ref !== '' && (
          <Card>
            <Box flexDirection="row" gap={1}>
              {pr === null ? (
                <Text bold wrap="truncate-end">
                  {ref}
                </Text>
              ) : (
                <Text bold>{`#${pr.number}`}</Text>
              )}
              {pr !== null && (
                <Box flexShrink={1}>
                  <Text wrap="truncate-end">{cleanTitle(pr.title)}</Text>
                </Box>
              )}
            </Box>
            {pr !== null && (
              <Box flexDirection="column" marginTop={1}>
                <Fact label="GitHub" value={githubLine(pr)} />
                <Fact label="CI" value={ci!.text} color={ci!.isBad ? 'error' : 'text'} />
                {(isReviewed || rm.failedAt > 0) && (
                  <Fact label="Codex" value={isReviewed ? codexText(review) : 'unknown'} />
                )}
              </Box>
            )}
            {others !== undefined && others.count > 0 && (
              <Box marginTop={1}>
                <Text dimColor wrap="truncate-end">
                  {others.isLimit ? '100+ other open PRs in this repository' : `${others.count} other open PR${others.count === 1 ? '' : 's'} in this repository`}
                </Text>
              </Box>
            )}
            {prFresh !== undefined && (
              <Box marginTop={1}>
                <Text color="warning">{prFresh}</Text>
              </Box>
            )}
            {reviewFresh !== undefined && (
              <Box marginTop={prFresh === undefined ? 1 : 0}>
                <Text color="warning">{reviewFresh}</Text>
              </Box>
            )}
          </Card>
        )}

        {logCard(1)}

        {rows.length > 0 && (
          <Card>
            {liveRows.length > 0 && (
              <Box flexDirection="column">
                <Box marginBottom={1}>
                  <Text bold color="subtle">{`Running · ${liveRows.length}`}</Text>
                </Box>
                {liveRows.map((a, i) => termRow(a, i))}
              </Box>
            )}
            {doneRows.length > 0 && (
              <Box flexDirection="column" marginTop={liveRows.length > 0 ? 1 : 0}>
                <Box flexDirection="row">
                  <Button key="finished-toggle" label={`${isHidden ? '▸' : '▾'} Finished · ${doneRows.length}`} onPress={toggleFinished} />
                </Box>
                {!isHidden && <Box flexDirection="column" marginTop={1}>{doneRows.map((a, i) => termRow(a, i))}</Box>}
              </Box>
            )}
          </Card>
        )}
      </Box>
    )
  })
}
