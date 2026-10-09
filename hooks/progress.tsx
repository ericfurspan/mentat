// Mentat's band and pane: what needs the maintainer, where this session's pull
// request stands, what the agents are doing and how much session budget is left.
// Claude Code reads this file as a mod (hooks/hooks.json lists it under "modules");
// it approves, denies or changes no other tool call.
//
// Everything a drawing reads lives in $.state (types/index.d.ts); render hooks never
// write it. Every $ call is in a hook or in a top-level function that takes $.

import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register, RenderChildren } from 'claude-code'

import type { AgentRow, AgentStatus, Checks, CodexRead, PrSnapshot, ReadMark, ReviewSnapshot } from '../types'

const PLUGIN = 'mentat'
const PANE = 'mentat'
const TITLE = 'Mentat'
const OPEN_TOOL = `mcp__${PLUGIN}__open_decision`
const CLOSE_TOOL = `mcp__${PLUGIN}__close_decision`
const CODEX_APP = 'chatgpt-codex-connector[bot]'
const SUMMARY_MARK = '<!-- codex-pull-request-review-summary -->'
const STALE_MS = 5 * 60_000
const LIST_LIMIT = 100

const items = atom({ plugin: 'mentat', key: 'decisionsItems' } as const, [])
const nextId = atom({ plugin: 'mentat', key: 'decisionsNextId' } as const, 1)
const answering = atom({ plugin: 'mentat', key: 'decisionsAnswering' } as const, [])
const agents = atom({ plugin: 'mentat', key: 'agents' } as const, [])
const prRef = atom({ plugin: 'mentat', key: 'prRef' } as const, '')
const prAtom = atom({ plugin: 'mentat', key: 'pr' } as const, null)
const prMark = atom({ plugin: 'mentat', key: 'prMark' } as const, { seq: 0, okAt: 0, failedAt: 0 })
const reviewAtom = atom({ plugin: 'mentat', key: 'review' } as const, null)
const reviewMark = atom({ plugin: 'mentat', key: 'reviewMark' } as const, { seq: 0, okAt: 0, failedAt: 0 })
const meAtom = atom({ plugin: 'mentat', key: 'me' } as const, '')
const seqAtom = atom({ plugin: 'mentat', key: 'seq' } as const, 0)

// Neutral tints that read on dark and light; amber for what needs the maintainer.
const TINT = { surface: '#8b949e14', you: '#d2992224' }
const COLOR = { track: '#8b949e33', now: '#4c8bf5', warn: '#d29922' }

// ---- plain helpers (no $) -----------------------------------------------------------

const cleanTitle = (t: string): string => t.replace(/^[a-z]+(\([^)]*\))?!?:\s*/, '').replace(/^\w/, c => c.toUpperCase())
const plural = (n: number, one: string, many: string): string => `${n} ${n === 1 ? one : many}`
const shortModel = (model: string): string =>
  model.replace(/^claude-/, '').replace(/-\d{8}$/, '').replace(/-(\d+)-(\d+)$/, ' $1.$2').replace(/^\w/, c => c.toUpperCase())
const duration = (ms: number): string => {
  const s = Math.max(0, Math.round(ms / 1000))
  return s < 60 ? `${s}s` : `${Math.floor(s / 60)}m ${String(s % 60).padStart(2, '0')}s`
}
const kTokens = (n: number): string => (n < 1000 ? `${n}` : `${(n / 1000).toFixed(n < 10000 ? 1 : 0)}k`)
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

const meter = (width: number, percent: number): string => {
  const p = Math.max(0, Math.min(100, percent))
  const fill = p >= 80 ? COLOR.warn : COLOR.now
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="6" viewBox="0 0 ${width} 6"><rect x="0" y="0" width="${width}" height="6" rx="3" fill="${COLOR.track}"/><rect x="0" y="0" width="${Math.max(3, (width * p) / 100).toFixed(1)}" height="6" rx="3" fill="${fill}"/></svg>`
}
const textMeter = (cells: number, percent: number): string => {
  const filled = Math.round((Math.max(0, Math.min(100, percent)) / 100) * cells)
  return '█'.repeat(filled) + '░'.repeat(cells - filled)
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
  const isFinalChecked = mine.some(c => {
    const m = /^Final check on ([0-9a-f]{7,40})\b/.exec(str(c.body))
    return m !== null && head.startsWith(m[1]!)
  })
  return { codex, local, isFinalChecked }
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
// the elapsed time, an agent the mod never saw is added without a model or start,
// and one the engine no longer lists is ended (unknown), never finished.
const reconcile = (rows: AgentRow[], infos: AgentInfoLike[], now: number): AgentRow[] => {
  const next = rows.map(row => {
    const info = infos.find(i => i.id === row.id)
    if (info === undefined) return isEnded(row.status) ? row : { ...row, status: 'unknown' as const, endedAt: now }
    if (isEnded(info.status)) return { ...row, status: info.status, endedAt: row.endedAt ?? now }
    const { endedAt: _endedAt, ...rest } = row
    return { ...rest, status: info.status }
  })
  for (const info of infos) {
    if (rows.some(r => r.id === info.id)) continue
    next.push({ id: info.id, type: info.type, description: info.description, status: info.status, ...(isEnded(info.status) ? { endedAt: now } : {}) })
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

// Runs a command; the stdout, or undefined when it failed (nonzero exit or rejection).
async function run($: EngineInterface, argv: string[], cwd?: string): Promise<string | undefined> {
  try {
    const out = await $.process.run(argv, cwd === undefined ? { timeoutMs: 20_000 } : { timeoutMs: 20_000, cwd })
    return out.exitCode === 0 ? out.stdout : undefined
  } catch {
    return undefined
  }
}

async function syncAgents($: EngineInterface): Promise<void> {
  try {
    const infos = (await $.agent.list()) as AgentInfoLike[]
    const now = await $.clock.now()
    await inTurn(() => update($, agents, rows => reconcile(rows, infos, now)))
  } catch {
    // the next check tries again
  }
}

async function agentTick($: EngineInterface): Promise<void> {
  const rows = await read($, agents)
  if (!rows.some(r => !isEnded(r.status))) return
  await syncAgents($)
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

export const register: Register = (on, _options) => {
  // The effort an Agent call asked for, until the agent it spawns is recorded.
  const effortByCall = new Map<string, string>()
  let agentTimer: { cancel: () => void } | undefined
  let refreshTimer: { cancel: () => void } | undefined

  on('session.start', async ($, e, next) => {
    await $.command.register({
      name: 'mentat',
      description: 'Show what needs you, the pull request, the agents and the session budget in a pane',
      argumentHint: '[pr <number>]',
      immediate: true,
    })
    await $.tool.register({
      name: 'open_decision',
      description:
        'Record a question or decision you have just put to the user in chat, so it shows in their Mentat pane until answered. ' +
        'Call it once per real question that waits on the user (not rhetorical ones, not routine status). ' +
        'Returns an id; call close_decision with that id when the user answers or the question no longer applies.',
      inputSchema: {
        type: 'object',
        properties: {
          question: { type: 'string', description: 'The question, in one short plain sentence' },
          recommendation: { type: 'string', description: 'Your recommendation, in a few words, if you gave one' },
          accept: {
            type: 'string',
            description:
              'If your recommendation can be taken with one press, the label of that answer (for example Yes); the pane shows it as a button',
          },
        },
        required: ['question'],
      },
      isDeferred: false,
    })
    await $.tool.register({
      name: 'close_decision',
      description: 'Close a question opened with open_decision once the user has answered it or it no longer applies.',
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

    // A (re)load: reconcile the agents with the engine's list and start the timers
    // over; reads that a former load left running are told apart by their sequence number.
    // The former decisions pane kept settled entries (with closedAt) in this state;
    // nothing shows them now, so they must not come back as open questions.
    await inTurn(() => update($, items, withoutSettled))
    reader = { isBusy: false, isAgain: false }
    agentTimer?.cancel()
    refreshTimer?.cancel()
    await syncAgents($)
    agentTimer = $.clock.every(1000, () => void agentTick($))
    refreshTimer = $.clock.every(60_000, () => void refresh($))
    void refresh($)

    return next(e)
  })

  // A different conversation starts (/clear, /resume, /branch): the pull request of
  // the old one is not this session's. A mod reload (session.start), a startup and a
  // compaction are the same conversation and keep it.
  on('classic.SessionStart', async ($, e, next) => {
    if (e.source === 'clear' || e.source === 'resume' || e.source === 'fork') {
      await follow($, '')
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
    const input = e as unknown as { question?: unknown; recommendation?: unknown; accept?: unknown }
    const question = typeof input.question === 'string' ? input.question.trim() : ''
    if (question === '') {
      return { deny: 'open_decision needs a question.' }
    }
    const optional = (v: unknown) => (typeof v === 'string' && v.trim() !== '' ? v.trim() : undefined)
    const recommendation = optional(input.recommendation)
    const accept = optional(input.accept)
    const id = await inTurn(async () => {
      const n = await read($, nextId)
      await update($, nextId, () => n + 1)
      const openedAt = await $.clock.now()
      await update($, items, list =>
        [...list, { id: `d${n}`, question, recommendation, accept, openedAt }],
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
      return true
    })
    if (!isClosed) {
      return { deny: `No open decision with id ${id}.` }
    }
    await invalidate($)

    return { result: `Closed decision ${id}.` }
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
    const effort = effortByCall.get(e.tool_use_id)
    if (effort !== undefined) row.effort = effort
    effortByCall.delete(e.tool_use_id)
    await inTurn(() => update($, agents, list => [...list.filter(a => a.id !== id), row].slice(-30)))
    await invalidate($)

    return out
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
      await syncAgents($)
      await invalidate($)
    }

    return next(e)
  })

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    if (e.props.hasSurvey) {
      return next(e)
    }
    const open = await read($, items)
    const pr = await read($, prAtom)
    const review = await read($, reviewAtom)
    const now = await $.clock.now()
    const pm = await read($, prMark)
    const rm = await read($, reviewMark)
    // Only an action the maintainer owns raises the band: an open question, or a
    // pull request whose current head has Claude Code's final check. The stored facts
    // may be of an old head, so the latest read of the PR and of its review must have
    // succeeded and be fresh; otherwise the pane still shows them, with their lines.
    const isCurrent = (m: ReadMark) => m.okAt > m.failedAt && now - m.okAt <= STALE_MS
    const isChecked =
      pr !== null && pr.state === 'OPEN' && review !== null && review.head === pr.head && review.isFinalChecked &&
      isCurrent(pm) && isCurrent(rm)
    if (open.length === 0 && !isChecked) {
      return next(e)
    }
    const { Box, Button, Text } = $.ui.resolve(e)
    // The band is shared: what the plugins beneath draw stays, under this row.
    const beneath = await next(e)

    return (
      <Box flexDirection="column">
        <Box flexDirection="row" alignItems="center" justifyContent="space-between" gap={2}>
          <Box flexDirection="row" alignItems="center" gap={1} flexShrink={1}>
            {isChecked && <Text bold>{`#${pr.number}`}</Text>}
            {isChecked && <Text wrap="truncate-end">{cleanTitle(pr.title)}</Text>}
            {isChecked && <Text color="warning">· Final check posted</Text>}
          </Box>
          <Box flexDirection="row" alignItems="center" gap={1}>
            {open.length > 0 && (
              <Box flexDirection="row" backgroundColor={TINT.you} paddingX={1}>
                <Text color="warning">{plural(open.length, 'question', 'questions')}</Text>
              </Box>
            )}
            <Button key="open" label="Details" onPress={() => $.ui.open({ id: PANE, title: TITLE })} />
          </Box>
        </Box>
        {beneath}
      </Box>
    )
  })

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const { Box, Button, Input, Text } = $.ui.resolve(e)
    const Svg = e.surface === 'desktop' ? $.ui.resolve(e as typeof e & { surface: 'desktop' }).Svg : undefined
    const now = await $.clock.now()
    const cols = e.props.bodyColumns ?? 50
    const isNarrow = cols < 48
    const open = (await read($, items))
    const openAnswers = await read($, answering)
    const ref = await read($, prRef)
    const pr = await read($, prAtom)
    const review = await read($, reviewAtom)
    const pm = await read($, prMark)
    const rm = await read($, reviewMark)
    const rows = [...(await read($, agents))].sort((a, b) => {
      if (isActive(a.status) !== isActive(b.status)) return isActive(a.status) ? -1 : 1
      return (b.startedAt ?? 0) - (a.startedAt ?? 0)
    })
    let usage: Awaited<ReturnType<typeof $.session.usage>> | undefined
    try {
      usage = await $.session.usage()
    } catch {
      usage = undefined
    }

    const Card = ({ tint, children }: { tint?: string; children?: RenderChildren }) => (
      <Box flexDirection="column" backgroundColor={tint ?? TINT.surface} paddingX={2} paddingY={1.5} marginTop={1}>
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

    const send = (d: { id: string; question: string }, text: string) =>
      $.prompt.submit({ text: `Answer to decision ${d.id} ("${d.question}"): ${text}` })
    const setAnswering = (id: string, isOn: boolean) =>
      inTurn(() => update($, answering, ids => (isOn ? [...ids.filter(x => x !== id), id] : ids.filter(x => x !== id))))

    // A freshness line only when a read failed or is more than five minutes old.
    const freshness = (what: string, mark: ReadMark): string | undefined => {
      if (mark.failedAt > 0) {
        return `${mark.cause === 'user' ? 'GitHub user' : what} read failed${mark.okAt > 0 ? ` (last ok ${ago(now - mark.okAt)})` : ''}`
      }
      if (mark.okAt > 0 && now - mark.okAt > STALE_MS) return `${what} read ${Math.floor((now - mark.okAt) / 60_000)}m old`
      return undefined
    }
    const prFresh = freshness('PR', pm)
    const reviewFresh = freshness('Review', rm)
    const isReviewed = pr !== null && review !== null && review.head === pr.head
    const ci = pr === null ? undefined : ciLine(pr.checks)
    const others = pr?.others
    const meterPx = isNarrow ? 56 : 120
    const cells = isNarrow ? 6 : 10
    const limits = (usage?.rateLimits ?? []).map(r => ({
      label: r.kind === 'five_hour' ? '5-hour' : r.kind === 'seven_day' ? 'Week' : r.kind,
      percent: Math.round(r.percentUsed),
      reset: resetIn(r.resetsAt, now),
    }))
    const meters = [
      ...(usage?.context.percent === undefined ? [] : [{ label: 'Context', percent: Math.round(usage.context.percent), reset: '' }]),
      ...limits,
    ]

    return (
      <Box flexDirection="column" paddingX={1}>
        {open.map(d => (
          <Card key={d.id} tint={TINT.you}>
            <Heading label="Question for you" color="warning" />
            <Text bold>{d.question}</Text>
            {d.recommendation !== undefined && <Text dimColor>{`→ ${d.recommendation}`}</Text>}
            <Box flexDirection="row" gap={1} marginTop={1}>
              {d.accept !== undefined && (
                <Button key={`accept-${d.id}`} label={d.accept} variant="primary" onPress={() => send(d, d.accept!)} />
              )}
              <Button key={`answer-open-${d.id}`} label="Answer…" onPress={() => setAnswering(d.id, !openAnswers.includes(d.id))} />
              <Button
                key={`dismiss-${d.id}`}
                label="Dismiss"
                onPress={() =>
                  inTurn(async () => {
                    await update($, items, all => all.filter(x => x.id !== d.id))
                    await update($, answering, ids => ids.filter(x => x !== d.id))
                  })
                }
              />
            </Box>
            {openAnswers.includes(d.id) && (
              <Box marginTop={1}>
                <Input
                  key={`answer-${d.id}`}
                  placeholder="Your answer"
                  submitLabel="Send"
                  onSubmit={async (answer: string) => {
                    const text = answer.trim()
                    if (text === '') return
                    await send(d, text)
                    await setAnswering(d.id, false)
                  }}
                />
              </Box>
            )}
          </Card>
        ))}

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
                  {others.isLimit ? '100+ more open PRs' : `+${others.count} more open PR${others.count === 1 ? '' : 's'}`}
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

        {rows.length > 0 && (
          <Card>
            <Heading label={`Agents  ${rows.length}`} />
            {rows.map((a, i) => {
              const ms = a.startedAt === undefined ? undefined : (a.endedAt ?? now) - a.startedAt
              const facts = [
                a.type,
                a.model === undefined ? undefined : shortModel(a.model),
                isNarrow ? undefined : a.effort,
                a.status === 'unknown' ? 'ended' : a.status,
                ms === undefined ? undefined : duration(ms),
                isNarrow || a.tokens === undefined ? undefined : `${kTokens(a.tokens)} reported`,
              ]
                .filter(Boolean)
                .join(' · ')
              const color = isActive(a.status) ? 'suggestion' : a.status === 'failed' || a.status === 'killed' ? 'error' : a.status === 'completed' ? 'success' : 'subtle'
              return (
                <Box key={a.id} flexDirection="column" marginTop={i === 0 ? 0 : 1}>
                  <Box flexDirection="row" gap={1}>
                    <Text color={color}>{isActive(a.status) ? '●' : a.status === 'completed' ? '✓' : a.status === 'failed' || a.status === 'killed' ? '✕' : '○'}</Text>
                    <Text bold={isActive(a.status)} wrap="truncate-end">
                      {a.description}
                    </Text>
                  </Box>
                  <Box paddingLeft={2}>
                    <Text dimColor wrap="truncate-end">
                      {facts}
                    </Text>
                  </Box>
                </Box>
              )
            })}
          </Card>
        )}

        {meters.length > 0 && (
          <Card>
            <Heading label="Session" />
            {meters.map(m => (
              <Box key={m.label} flexDirection="row" gap={1} alignItems="center">
                <Box width={8}>
                  <Text dimColor>{m.label}</Text>
                </Box>
                {Svg !== undefined ? (
                  <Svg source={meter(meterPx, m.percent)} alt={`${m.label} ${m.percent}%`} width={meterPx} height={6} />
                ) : (
                  <Text color={m.percent >= 80 ? 'warning' : 'suggestion'}>{textMeter(cells, m.percent)}</Text>
                )}
                <Box width={5}>
                  <Text>{`${m.percent}%`}</Text>
                </Box>
                {!isNarrow && m.reset !== '' && <Text dimColor>{m.reset}</Text>}
              </Box>
            ))}
          </Card>
        )}
      </Box>
    )
  })
}
