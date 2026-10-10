// Mentat's band and pane. On the desktop the band is always there, one line: what waits on the
// maintainer, else a warning that a rate limit runs low, else the newest note, else a quiet line. On the
// terminal there is no band: the footer label counts what waits and opens the pane. The pane, on both, has
// two sections, Waiting on you and the Feed (the agents that have not ended, then the log); the desktop
// draws them as two cards of native rows, the terminal as framed text.
// Claude Code reads this file as a mod (hooks/hooks.json lists it under "modules");
// it approves, denies or changes no other tool call.
//
// Everything a drawing reads lives in $.state (pane/types.d.ts); render hooks never
// write it. Every $ call is in a hook or in a top-level function that takes $.

import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register, RenderElement } from 'claude-code'

import type { AgentRow, AgentStatus, CheckResult, Decision, DecisionKind, EventKind, EventMark, GoneEntry, LogEntry, LogKind, NoteEntry } from './types'

const PLUGIN = 'mentat'
const PANE = 'mentat'
const TITLE = 'Mentat'
const OPEN_TOOL = `mcp__${PLUGIN}__open_decision`
const CLOSE_TOOL = `mcp__${PLUGIN}__close_decision`
const NOTE_TOOL = `mcp__${PLUGIN}__note`
// A rate limit this far gone raises the band.
const WARN_PERCENT = 80
// The terminal pane's width classes, in body columns: sections are framed from FRAME_COLUMNS, headed by a
// rule from RULE_COLUMNS, and below that also drop the times, the recommendation and the WARN lines.
const FRAME_COLUMNS = 60
const RULE_COLUMNS = 40
// The Log keeps this many entries and cuts a line at LOG_WIDTH characters. The Feed shows the newest
// FEED_SHOWN until `Show all`.
const LOG_LIMIT = 200
const FEED_SHOWN = 10
const LOG_WIDTH = 80
// The record of items that left without close_decision keeps this many entries.
const GONE_LIMIT = 50

const items = atom({ plugin: 'mentat', key: 'decisionsItems' } as const, [])
const nextId = atom({ plugin: 'mentat', key: 'decisionsNextId' } as const, 1)
const sentAtom = atom({ plugin: 'mentat', key: 'decisionsSent' } as const, [])
const agents = atom({ plugin: 'mentat', key: 'agents' } as const, [])
const checkResult = atom({ plugin: 'mentat', key: 'checkResult' } as const, null)
const logAtom = atom({ plugin: 'mentat', key: 'log' } as const, [])
// Counts the conversations; see classic.SessionStart and sendAnswer.
const conversationAtom = atom({ plugin: 'mentat', key: 'conversation' } as const, 0)
const logAll = atom({ plugin: 'mentat', key: 'logAll' } as const, false)
const goneAtom = atom({ plugin: 'mentat', key: 'decisionsGone' } as const, [])

// The id of the item the mod itself pins for a `mentat check`: an alert after a failed run, a
// warning after a passing run with warnings. The next run replaces it, and a clean pass removes it.
const CHECK_ID = 'check'

// The notes Claude Code adds with the `note` tool, in the pane's Log and as the desktop band's line: each kind has an
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
// The event lines the pane writes to the Log itself, drawn dim: each has a mark and a theme color. An
// `asked` line takes the mark of the item's kind (the band's marks) and a `check` line that of the result.
const EVENT_STYLE: Record<Exclude<EventKind, 'asked' | 'check'> | EventMark, { icon: string; color: string }> = {
  agentDone: { icon: '✓', color: 'success' },
  agentFailed: { icon: '✕', color: 'error' },
  answered: { icon: '✓', color: 'success' },
  dismissed: { icon: '·', color: 'subtle' },
  prOpened: { icon: '↗', color: 'suggestion' },
  question: { icon: '?', color: 'warning' },
  action: { icon: '→', color: 'suggestion' },
  alert: { icon: '!', color: 'error' },
  pass: { icon: '✓', color: 'success' },
  warn: { icon: '!', color: 'warning' },
  fail: { icon: '✕', color: 'error' },
}
// An entry stored without a source is a note.
export const isNote = (entry: LogEntry): entry is NoteEntry => entry.source !== 'event'
// The icon and color a Log row is drawn with.
const styleOf = (entry: LogEntry): { icon: string; color: string } =>
  isNote(entry) ? LOG_STYLE[entry.kind] : EVENT_STYLE[(entry.mark ?? entry.kind) as keyof typeof EVENT_STYLE] ?? EVENT_STYLE.dismissed

// ---- plain helpers (no $) -----------------------------------------------------------

type LogDraft = { kind: LogKind; text: string } | { kind: EventKind; text: string; source: 'event'; mark?: EventMark }
const eventDraft = (kind: EventKind, text: string, mark?: EventMark): LogDraft => ({ kind, text, source: 'event', ...(mark === undefined ? {} : { mark }) })
// An agent's role as an event line names it: Builder, Explore, Plan, else the type as given.
const roleName = (type: string): string => {
  const role = roleOf(type)

  return role === 'builder' ? 'Builder' : role === 'explore' ? 'Explore' : role === 'plan' ? 'Plan' : type
}
const plural = (n: number, one: string, many: string): string => `${n} ${n === 1 ? one : many}`
const duration = (ms: number): string => {
  const s = Math.max(0, Math.round(ms / 1000))
  return s < 60 ? `${s}s` : `${Math.floor(s / 60)}m ${String(s % 60).padStart(2, '0')}s`
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

type Json = Record<string, unknown>
const asObj = (v: unknown): Json => (typeof v === 'object' && v !== null ? (v as Json) : {})
const str = (v: unknown): string => (typeof v === 'string' ? v : '')

const isEnded = (s: AgentStatus): boolean => s === 'completed' || s === 'failed' || s === 'killed' || s === 'unknown'
const isActive = (s: AgentStatus): boolean => s === 'running' || s === 'waiting' || s === 'pending'

type AgentInfoLike = { id: string; type: string; description: string; status: AgentStatus }
// Fits the rows to what the engine lists: statuses follow the engine, an end freezes
// the elapsed time, an agent the mod never saw is added without a start,
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
    next.push({
      id: info.id,
      type: info.type,
      description: info.description,
      status: info.status,
      ...(isEnded(info.status) ? { endedAt: now } : {}),
    })
  }
  return next.slice(-30)
}

const ghPrUrl = /https:\/\/github\.com\/([A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+)\/pull\/(\d+)/g
// The kinds of open item, most urgent first. An item stored without a kind is a question.
const KIND_RANK: Record<DecisionKind, number> = { alert: 0, question: 1, warning: 2, action: 3 }
const kindOf = (d: { kind?: DecisionKind }): DecisionKind => d.kind ?? 'question'
// The kinds the agent may open. A warning is the mod's own, for a passing `mentat check` with warnings.
const isKind = (v: unknown): v is Exclude<DecisionKind, 'warning'> => v === 'question' || v === 'action' || v === 'alert'
// A link is drawn only when it is an https URL.
const httpsLink = (v: unknown): string | undefined => {
  const link = typeof v === 'string' ? v.trim() : ''
  return link.length <= 2048 && /^https:\/\/[^\s/]\S*$/.test(link) ? link : undefined
}
// The words a link is drawn with, where a row is tight: `#160` for a GitHub issue or pull
// request (always the bare number: knowing whether it is this session's repository would need a read, and the
// pane reads nothing), else the host (`example.com`). The Link still opens the whole address.
const shortLink = (link: string): string => {
  const github = /^https:\/\/github\.com\/[^/\s]+\/[^/\s]+\/(?:issues|pull)\/(\d+)(?:[/?#]\S*)?$/.exec(link)
  if (github !== null) return `#${github[1]}`

  return /^https:\/\/([^/?#\s]+)/.exec(link)?.[1] ?? link.replace(/^https:\/\//, '')
}

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

// Adds entries to the log; call it inside inTurn. A note equal to the newest entry (same kind and
// text) is the same note again and is not added; an event line is always added, for two agents or two
// questions can read alike. The log keeps the last LOG_LIMIT entries.
async function addLog($: EngineInterface, at: number, drafts: LogDraft[]): Promise<void> {
  if (drafts.length === 0) return
  await update($, logAtom, list => {
    let next: LogEntry[] = list
    for (const d of drafts) {
      const text = oneLine(d.text)
      if ('source' in d) {
        next = [...next, { at, kind: d.kind, text, source: 'event', ...(d.mark === undefined ? {} : { mark: d.mark }) }]
        continue
      }
      const last = next[next.length - 1]
      if (last !== undefined && isNote(last) && last.kind === d.kind && last.text === text) continue
      next = [...next, { at, kind: d.kind, text }]
    }

    return next.slice(-LOG_LIMIT)
  })
}

// The event lines for the agents that went from not ended to completed, failed or killed between two
// readings of the rows. An agent that was not in the former rows, or that ended as unknown, writes none.
const agentEvents = (before: AgentRow[], after: AgentRow[]): LogDraft[] => {
  const drafts: LogDraft[] = []
  for (const row of after) {
    const was = before.find(r => r.id === row.id)
    if (was === undefined || isEnded(was.status)) continue
    const who = `${roleName(row.type)} ${row.status === 'completed' ? 'finished' : row.status === 'failed' ? 'failed' : 'stopped'}: ${row.description}`
    if (row.status === 'completed') {
      const ms = row.startedAt === undefined || row.endedAt === undefined ? undefined : row.endedAt - row.startedAt
      drafts.push(eventDraft('agentDone', ms === undefined ? who : `${who} · ${duration(ms)}`))
    } else if (row.status === 'failed' || row.status === 'killed') drafts.push(eventDraft('agentFailed', who))
  }

  return drafts
}

async function syncAgents($: EngineInterface): Promise<void> {
  try {
    const infos = (await $.agent.list()) as AgentInfoLike[]
    const now = await $.clock.now()
    await inTurn(async () => {
      const before = await read($, agents)
      const after = reconcile(before, infos, now)
      await update($, agents, () => after)
      await addLog($, now, agentEvents(before, after))
    })
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

// What the main loop's Bash call says: a pull request it opened.
async function afterBash($: EngineInterface, command: string, stdout: string): Promise<void> {
  try {
    if (/\bgh\s+pr\s+create\b/.test(command)) {
      const urls = [...stdout.matchAll(ghPrUrl)]
      const last = urls[urls.length - 1]
      if (last !== undefined) {
        const at = await $.clock.now()
        await inTurn(() => addLog($, at, [eventDraft('prOpened', `Opened PR #${last[2]}`)]))
        await invalidate($)
      }
    }
  } catch {
    // the next command tries again
  }
}

// The event line for a recorded `mentat check` result.
const checkEvent = (outcome: CheckRead): LogDraft => {
  if (!outcome.passed) {
    const problems = Number(/\d+/.exec(outcome.failedLine)?.[0] ?? 0)

    return eventDraft('check', `mentat check failed: ${plural(problems, 'problem', 'problems')}`, 'fail')
  }
  const n = outcome.warnings.length

  return n === 0 ? eventDraft('check', 'mentat check passed', 'pass') : eventDraft('check', `mentat check passed with ${plural(n, 'warning', 'warnings')}`, 'warn')
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
    // The Feed line is for a result that differs from the one before it (none, after a new conversation).
    const previous = await read($, checkResult)
    const state = outcome.passed ? (outcome.warnings.length > 0 ? 'warn' : 'pass') : 'fail'
    const count = outcome.passed ? outcome.warnings.length : 0
    const isChange = previous === null || previous.state !== state || previous.warnings.length !== count
    await update($, checkResult, () => (outcome.passed ? { state: outcome.warnings.length > 0 ? ('warn' as const) : ('pass' as const), warnings: outcome.warnings } : { state: 'fail' as const, warnings: [] }))
    await update($, sentAtom, list => list.filter(x => x.id !== CHECK_ID))
    if (isChange) await addLog($, openedAt, [checkEvent(outcome)])
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

// ---- the module -----------------------------------------------------------------------------

// ---- Drawn desktop pieces: the small round marks of the band and the pane; text, rows and buttons are native. ----
const FONT = "-apple-system,BlinkMacSystemFont,'SF Pro Text','Segoe UI',sans-serif"
const HUE = { amber: '#C98A0E', blue: '#3D7FE6', red: '#D0453F' }

const xml = (s: string): string => s.replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c] ?? c)
const svgOf = (W: number, H: number, body: string): string =>
  `<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}" viewBox="0 0 ${W} ${H}">${body}</svg>`
// The role of an agent by its type.
type Role = 'builder' | 'explore' | 'plan' | 'other'
const roleOf = (type: string): Role => {
  const t = type.toLowerCase()
  if (t === 'builder' || t === 'mentat:builder') return 'builder'
  if (t === 'explore') return 'explore'
  if (t === 'plan') return 'plan'
  return 'other'
}
// The terminal's one-character mark for a role, where the desktop draws its glyph.
const ROLE_MARK: Record<Role, string> = { builder: '◆', explore: '◎', plan: '◇', other: '·' }
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
// The description of an item in the alt text of its mark.
const ITEM_ALT: Record<DecisionKind, string> = { question: 'Question', action: 'Waiting on you', alert: 'Alert', warning: 'Check warnings' }
// The items that wait on the maintainer, most urgent first: alert, then question, check warning, action; the
// newest of a kind first. The desktop band shows the first and counts the rest in `+N more`; the terminal
// pane lists them all.
const urgentFirst = (list: Decision[]): Decision[] =>
  [...list].reverse().sort((a, b) => KIND_RANK[kindOf(a)] - KIND_RANK[kindOf(b)])
const mostUrgent = (list: Decision[]): Decision | undefined => urgentFirst(list)[0]

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
  // The conversation the press began in: a delivery that lands in a later one writes no line there.
  let began = 0
  const isFirst = await inTurn(async () => {
    if ((await read($, sentAtom)).some(x => x.id === d.id)) return false
    began = await read($, conversationAtom)
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
  await inTurn(async () => {
    await update($, sentAtom, list => list.map(x => (x.id === d.id ? { ...x, isDelivered: true } : x)))
    if ((await read($, conversationAtom)) !== began) return
    await addLog($, await $.clock.now(), [eventDraft('answered', `You answered "${text}": ${d.question}`)])
  })
  await invalidate($)
  return true
}
// Notes that items left the list without close_decision, so close_decision can say so later; call it
// inside inTurn. The record keeps the last GONE_LIMIT entries and is never drawn.
async function recordGone($: EngineInterface, gone: GoneEntry[]): Promise<void> {
  if (gone.length === 0) return
  await update($, goneAtom, list => [...list, ...gone].slice(-GONE_LIMIT))
}
const dismissItem = async ($: EngineInterface, id: string) => {
  const at = await $.clock.now()

  return inTurn(async () => {
    const item = (await read($, items)).find(x => x.id === id)
    await update($, items, all => all.filter(x => x.id !== id))
    await update($, sentAtom, list => list.filter(x => x.id !== id))
    if (item !== undefined) {
      await recordGone($, [{ id, why: 'dismissed', at }])
      await addLog($, at, [eventDraft('dismissed', `You dismissed: ${item.question}`)])
    }
  })
}
// How close_decision names the way a new conversation started.
const SOURCE_WORDS: Record<string, string> = { clear: '/clear', resume: '/resume', fork: '/branch' }

// ---- the terminal pane: Waiting on you, then the Feed ----

type Layout = 'frame' | 'rule' | 'narrow'
const layoutOf = (cols: number): Layout => (cols >= FRAME_COLUMNS ? 'frame' : cols >= RULE_COLUMNS ? 'rule' : 'narrow')
// The pieces of a section's top edge, which together are exactly `cols` characters wide: `╭─ TITLE 3 ───╮`
// in a frame, `── TITLE 3 ───` as a rule. The title is drawn bold and the count dim, so they are apart.
const topEdge = (layout: Layout, title: string, count: number, cols: number): { head: string; title: string; count: string; fill: string } => {
  const head = layout === 'frame' ? '╭─ ' : '── '
  const shown = ` ${count}`
  const room = cols - head.length - title.length - shown.length - 1 - (layout === 'frame' ? 1 : 0)

  return { head, title, count: shown, fill: ` ${'─'.repeat(Math.max(0, room))}${layout === 'frame' ? '╮' : ''}` }
}
const bottomEdge = (cols: number): string => `╰${'─'.repeat(Math.max(0, cols - 2))}╯`
// The mark of each kind of open item and its theme color.
const ITEM_MARK: Record<DecisionKind, { char: string; color: string | undefined }> = {
  question: { char: '?', color: undefined },
  alert: { char: '!', color: 'error' },
  warning: { char: '!', color: 'warning' },
  action: { char: '→', color: 'suggestion' },
}

// What both panes draw, read once: the same sections, entries and order on the terminal and the desktop, so
// the two cannot drift. Each drawer only lays it out.
type PaneData = {
  now: number
  zone: string | undefined
  // Open items, most urgent first.
  open: Decision[]
  sentList: { id: string; text: string; isDelivered?: boolean }[]
  result: CheckResult | null
  // Agents that have not ended: working ones first, then the newest start first.
  live: AgentRow[]
  logList: LogEntry[]
  isLogAll: boolean
  // The Feed's log lines, newest first (`n` is the entry's place in the stored log), cut to FEED_SHOWN unless all.
  entries: { entry: LogEntry; n: number }[]
  // The toggle's label, when the log is longer than FEED_SHOWN.
  toggle: string | undefined
  budget: string | undefined
}
async function paneData($: EngineInterface): Promise<PaneData> {
  const now = await $.clock.now()
  const zone = await readZone($)
  const open = urgentFirst(await read($, items))
  const sentList = await read($, sentAtom)
  const result = await read($, checkResult)
  const live = [...(await read($, agents))]
    .filter(a => !isEnded(a.status))
    .sort((a, b) => {
      if (isActive(a.status) !== isActive(b.status)) return isActive(a.status) ? -1 : 1
      return (b.startedAt ?? 0) - (a.startedAt ?? 0)
    })
  const logList = await read($, logAtom)
  const isLogAll = await read($, logAll)
  const budget = budgetAlert(limitsOf(await readUsage($), now, zone))
  const newest = logList.map((entry, n) => ({ entry, n })).reverse()
  const toggle = logList.length > FEED_SHOWN ? (isLogAll ? 'Show fewer' : `Show all ${logList.length}`) : undefined

  return { now, zone, open, sentList, result, live, logList, isLogAll, entries: isLogAll ? newest : newest.slice(0, FEED_SHOWN), toggle, budget }
}
const toggleLogAll = ($: EngineInterface) => inTurn(() => update($, logAll, v => !v))
// What an open item shows besides its text: the answer button or the sent line, the link, the line under it
// (`Recommended: <text> · <time>`, else the time) and, for the check's warning item, the WARN lines.
const itemView = (d: Decision, data: PaneData) => {
  const kind = kindOf(d)
  const sent = data.sentList.find(x => x.id === d.id)
  const time = clockAt(d.openedAt, data.zone)

  return {
    kind,
    sent,
    answer: kind === 'question' && sent === undefined ? d.accept : undefined,
    link: kind !== 'question' ? d.link : undefined,
    detail: d.recommendation === undefined ? time : `Recommended: ${d.recommendation} · ${time}`,
    warns: d.id === CHECK_ID && kind === 'warning' ? (data.result?.warnings ?? []).map(w => `WARN: ${w}`) : [],
  }
}
// A live agent's state word as the engine reports it, and the time it has run when its start is known.
const agentClock = (a: AgentRow, now: number): string | undefined => (a.startedAt === undefined ? undefined : duration(now - a.startedAt))

// The pane on the terminal. `e` is the Pane's own render argument; `cols` its body width.
async function terminalPane($: EngineInterface, e: Parameters<EngineInterface['ui']['resolve']>[0], cols: number) {
  const { Box, Button, Link, Text } = $.ui.resolve(e)
  const data = await paneData($)
  const { now, zone, open, live, logList, budget } = data
  const layout = layoutOf(cols)
  const isShort = layout === 'narrow'
  const toggleLog = () => toggleLogAll($)

  // One body row: in a frame between the dim side lines, else bare. The middle grows and shrinks, so a row
  // that ends in Buttons needs no width arithmetic and the right edge stays where it is.
  const row = (key: string, children: RenderElement[], gap = 1) => (
    <Box key={key} flexDirection="row">
      {layout === 'frame' && <Text dimColor>│ </Text>}
      <Box flexGrow={1} flexShrink={1} flexDirection="row" gap={gap}>
        {children}
      </Box>
      {layout === 'frame' && <Text dimColor> │</Text>}
    </Box>
  )
  // A dim line under an item's text, indented to it.
  const detail = (key: string, text: string) =>
    row(key, [
      <Box key="text" flexGrow={1} flexShrink={1} paddingLeft={2}>
        <Text dimColor wrap="truncate-end">
          {text}
        </Text>
      </Box>,
    ])
  const section = (key: string, title: string, count: number, rows: RenderElement[], gap: boolean) => {
    const edge = topEdge(layout, title, count, cols)

    return (
      <Box key={key} flexDirection="column" marginTop={gap ? 1 : 0}>
        <Box key={`${key}-top`} flexDirection="row">
          <Text dimColor>{edge.head}</Text>
          <Text bold>{edge.title}</Text>
          <Text dimColor>{edge.count}</Text>
          <Text dimColor>{edge.fill}</Text>
        </Box>
        {rows}
        {layout === 'frame' && (
          <Box key={`${key}-bottom`} flexDirection="row">
            <Text dimColor>{bottomEdge(cols)}</Text>
          </Box>
        )}
      </Box>
    )
  }

  // Waiting on you: every open item, most urgent first. The first line holds the mark, the text and the buttons;
  // under it, dim, the recommendation and the time, and for the check's warning item its WARN lines.
  const waiting = open.flatMap(d => {
    const { kind, sent, answer, link, detail: recommended, warns } = itemView(d, data)
    const mark = ITEM_MARK[kind]
    const lines: RenderElement[] = [
      // The mark never shrinks and keeps its space after it (a margin, which a tight row cannot take away);
      // the text is what is cut. The controls keep their size and their space before them.
      row(`item-${d.id}`, [
        <Box key="mark-box" flexShrink={0} marginRight={1}>
          {mark.color === undefined ? <Text key="mark" dimColor>{mark.char}</Text> : <Text key="mark" color={mark.color}>{mark.char}</Text>}
        </Box>,
        <Box key="text" flexGrow={1} flexShrink={1}>
          <Text wrap="truncate-end">{d.question}</Text>
        </Box>,
        <Box key="controls" flexDirection="row" gap={1} flexShrink={0} paddingLeft={1}>
          {answer !== undefined && (
            <Button key={`accept-${d.id}`} plain label={answer} onPress={() => sendAnswer($, d, answer)}>
              <Text bold color="suggestion">
                {answer}
              </Text>
            </Button>
          )}
          {sent !== undefined && <Text dimColor>{sentLine(sent)}</Text>}
          {link !== undefined && (
            <Text underline color="suggestion">
              <Link href={link} label={shortLink(link)} />
            </Text>
          )}
          <Button key={`dismiss-${d.id}`} plain label="Dismiss" onPress={() => dismissItem($, d.id)}>
            <Text color="suggestion">Dismiss</Text>
          </Button>
        </Box>,
      ], 0),
    ]
    if (!isShort) {
      lines.push(detail(`detail-${d.id}`, recommended))
      warns.forEach((w, i) => lines.push(detail(`warn-${i}`, w)))
    }

    return lines
  })

  // The Feed: the agents that have not ended, pinned, then the log newest first.
  const feedRows: RenderElement[] = live.map(a => {
    const ran = agentClock(a, now)
    const state = ran === undefined ? a.status : `${a.status} · ${ran}`

    return row(`agent-${a.id}`, [
      <Text key="mark">{ROLE_MARK[roleOf(a.type)]}</Text>,
      <Box key="text" flexGrow={1} flexShrink={1}>
        <Text bold wrap="truncate-end">
          {a.description}
        </Text>
      </Box>,
      <Text key="state" dimColor>
        {state}
      </Text>,
    ])
  })
  if (live.length > 0 && logList.length > 0) feedRows.push(row('feed-gap', [<Text key="gap"> </Text>]))
  for (const { entry, n } of data.entries) {
    const { icon, color } = styleOf(entry)
    feedRows.push(
      row(`log-${n}`, [
        ...(isShort
          ? []
          : [
              <Box key="time" width={8} flexShrink={0} justifyContent="flex-end">
                <Text dimColor>{clockAt(entry.at, zone)}</Text>
              </Box>,
            ]),
        <Text key="icon" color={color}>
          {icon}
        </Text>,
        <Box key="text" flexGrow={1} flexShrink={1}>
          <Text wrap="truncate-end" {...(isNote(entry) ? {} : { dimColor: true })}>
            {entry.text}
          </Text>
        </Box>,
      ]),
    )
  }
  if (data.toggle !== undefined) {
    const label = data.toggle
    feedRows.push(
      row('log-toggle-row', [
        <Button key="log-toggle" plain label={label} onPress={toggleLog}>
          <Text color="suggestion">{label}</Text>
        </Button>,
      ]),
    )
  }

  return (
    <Box flexDirection="column">
      {budget !== undefined && (
        <Box key="budget" marginBottom={1}>
          <Text color="warning" wrap="truncate-end">
            {budget}
          </Text>
        </Box>
      )}
      {open.length > 0 && section('waiting', 'WAITING ON YOU', open.length, waiting, false)}
      {feedRows.length > 0 && section('feed', 'FEED', live.length + logList.length, feedRows, open.length > 0)}
      {open.length === 0 && feedRows.length === 0 && <Text dimColor>Nothing waiting on you.</Text>}
    </Box>
  )
}

// ---- the desktop pane: Waiting on you, then the Feed, as two cards of native rows ----

// The card surface: a faint neutral tint (grey at about 8%), light on a light theme and dark on a dark one.
// Whether the desktop app draws a Box background and a rounded border is not verified; change or drop it here.
export const CARD_TINT = '#80808014'
// The mark column of an item row, in cells (the Svg inside is 20px), and the indent of the lines under the text.
const MARK_CELLS = 3
const TEXT_INDENT = MARK_CELLS + 1
// A small round tinted mark with a glyph, a fixed 20px Svg; it is the only picture in the pane, and it does
// not take part in the reflow when the divider moves.
const MARK_SIZE = 20
// The tint behind the band's `+N more` pill: the warning amber at about 18%.
const MORE_TINT = `${HUE.amber}2e`
const markSvg = (char: string, hue: string): string =>
  svgOf(MARK_SIZE, MARK_SIZE, `<circle cx="10" cy="10" r="10" fill="${hue}" opacity="0.18"/><text fill="${hue}" x="10" y="14.5" text-anchor="middle" font-family="${FONT}" font-size="12" font-weight="700">${xml(char)}</text>`)

// The pane on the desktop: the same sections, entries and order as the terminal's, drawn as rows of native
// Box and Text. Nothing here is measured: the text row grows and shrinks (and is cut with an ellipsis), so
// the rows follow the divider without a redraw from the mod.
async function desktopPane($: EngineInterface, e: Parameters<EngineInterface['ui']['resolve']>[0] & { surface: 'desktop' }) {
  const { Box, Button, Link, Svg, Text } = $.ui.resolve(e)
  const data = await paneData($)
  const { now, zone, open, live, logList, budget } = data

  // The desktop lays rows out with CSS flexbox, where a flex item's min-width is `auto` (its content's width),
  // so a Box never shrinks below its text however its flexShrink is set. Every Box between the card and the
  // text that must be cut therefore has minWidth 0, and the text Box also hides its overflow.
  const card = (key: string, title: string, color: string, count: number, body: RenderElement) => (
    <Box key={key} flexDirection="column" gap={1} minWidth={0} borderStyle="round" borderDimColor backgroundColor={CARD_TINT} paddingX={1}>
      <Box key={`${key}-head`} flexDirection="row" gap={1}>
        <Text bold color={color}>
          {title}
        </Text>
        <Text dimColor>{count}</Text>
      </Box>
      {body}
    </Box>
  )
  // The text of a row: the only part that shrinks.
  const cut = (text: string, props: { bold?: boolean; dimColor?: boolean } = {}) => (
    <Box flexGrow={1} flexShrink={1} minWidth={0} overflow="hidden">
      <Text wrap="truncate-end" {...props}>
        {text}
      </Text>
    </Box>
  )

  const waiting = open.map(d => {
    const { kind, sent, answer, link, detail, warns } = itemView(d, data)
    const mark = MARK[kind]

    return (
      <Box key={`item-${d.id}`} flexDirection="column" minWidth={0}>
        <Box flexDirection="row" alignItems="center" gap={1} minWidth={0}>
          <Box width={MARK_CELLS} flexShrink={0}>
            <Svg source={markSvg(mark.char, mark.hue)} alt={ITEM_ALT[kind]} width={MARK_SIZE} height={MARK_SIZE} />
          </Box>
          {cut(d.question)}
          <Box flexDirection="row" alignItems="center" gap={1} flexShrink={0}>
            {link !== undefined && (
              <Text>
                <Link href={link} label={shortLink(link)} />
              </Text>
            )}
            {answer !== undefined && <Button key={`accept-${d.id}`} label={answer} variant="primary" onPress={() => sendAnswer($, d, answer)} />}
            {sent !== undefined && <Text dimColor>{sentLine(sent)}</Text>}
            <Button key={`dismiss-${d.id}`} label="Dismiss" onPress={() => dismissItem($, d.id)} />
          </Box>
        </Box>
        {[detail, ...warns].map((line, i) => (
          <Box key={`detail-${i}`} paddingLeft={TEXT_INDENT} flexDirection="row" minWidth={0}>
            {cut(line, { dimColor: true })}
          </Box>
        ))}
      </Box>
    )
  })

  // The time column is a fixed width and right-aligned: an agent's state word sits in it, a log line's time.
  const timeColumn = (child: RenderElement) => (
    <Box width={8} flexShrink={0} justifyContent="flex-end">
      {child}
    </Box>
  )
  const agentRows = live.map(a => {
    const ran = agentClock(a, now)

    return (
      <Box key={`agent-${a.id}`} flexDirection="row" alignItems="center" gap={1} minWidth={0}>
        {timeColumn(<Text color="suggestion">{a.status}</Text>)}
        <Box flexShrink={0}>
          <Text color="suggestion">●</Text>
        </Box>
        {cut(a.description, { bold: true })}
        {ran !== undefined && (
          <Box flexShrink={0}>
            <Text dimColor>{ran}</Text>
          </Box>
        )}
      </Box>
    )
  })
  const logRows = data.entries.map(({ entry, n }) => {
    const { icon, color } = styleOf(entry)

    return (
      <Box key={`log-${n}`} flexDirection="row" alignItems="center" gap={1} minWidth={0}>
        {timeColumn(<Text dimColor>{clockAt(entry.at, zone)}</Text>)}
        <Box flexShrink={0}>
          <Text color={color}>{icon}</Text>
        </Box>
        {cut(entry.text, isNote(entry) ? {} : { dimColor: true })}
      </Box>
    )
  })
  const feed = (
    <Box flexDirection="column" minWidth={0}>
      {agentRows}
      {logRows.length > 0 && (
        <Box key="log" flexDirection="column" minWidth={0} marginTop={agentRows.length > 0 ? 1 : 0}>
          {logRows}
        </Box>
      )}
      {data.toggle !== undefined && (
        <Box key="log-more" flexDirection="row" marginTop={1}>
          <Button key="log-toggle" label={data.toggle} onPress={() => toggleLogAll($)} />
        </Box>
      )}
    </Box>
  )
  const hasFeed = live.length > 0 || logList.length > 0

  return (
    <Box flexDirection="column" gap={1} paddingX={1} minWidth={0}>
      {budget !== undefined && (
        <Text color="warning" wrap="truncate-end">
          {budget}
        </Text>
      )}
      {open.length > 0 && card('card-waiting', 'WAITING ON YOU', 'warning', open.length, <Box flexDirection="column" gap={1} minWidth={0}>{waiting}</Box>)}
      {hasFeed && card('card-feed', 'FEED', 'subtle', live.length + logList.length, feed)}
      {open.length === 0 && !hasFeed && <Text dimColor>Nothing waiting on you.</Text>}
    </Box>
  )
}

export const register: Register = (on, _options) => {
  let agentTimer: { cancel: () => void } | undefined
  let refreshTimer: { cancel: () => void } | undefined

  on('session.start', async ($, e, next) => {
    await $.command.register({
      name: 'mentat',
      description: 'Show what waits on you and the Feed in a pane',
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

    // A (re)load: reconcile the agents with the engine's list and start the timers over.
    // The former decisions pane kept settled entries (with closedAt) in this state;
    // nothing shows them now, so they must not come back as open questions.
    await inTurn(() => update($, items, withoutSettled))
    // A submit that was still waiting for a turn is lost with the old load: its question
    // offers its buttons again. A delivered answer stays marked.
    await inTurn(() => update($, sentAtom, list => list.filter(x => x.isDelivered === true)))
    agentTimer?.cancel()
    refreshTimer?.cancel()
    await syncAgents($)
    agentTimer = $.clock.every(1000, () => void agentTick($))
    // A minute tick only redraws, so an idle session shows a rate limit that crossed the warning line.
    refreshTimer = $.clock.every(60_000, () => void invalidate($))
    void startCheck($, e.cwd)

    return next(e)
  })

  // A different conversation starts (/clear, /resume, /branch): the open questions of the old one
  // are not this session's. A mod reload (session.start), a startup and a compaction are the same
  // conversation and keep them.
  on('classic.SessionStart', async ($, e, next) => {
    if (e.source === 'clear' || e.source === 'resume' || e.source === 'fork') {
      // A check still running for the old conversation writes nothing.
      checkEpoch += 1
      // Open questions belong to the conversation they were asked in.
      const at = await $.clock.now()
      await inTurn(async () => {
        await recordGone($, (await read($, items)).map(d => ({ id: d.id, why: 'cleared', source: e.source, at })))
        await update($, items, () => [])
        await update($, sentAtom, () => [])
        // The last check was of the old conversation too.
        await update($, checkResult, () => null)
        // So is the log, and a write that began before this waits no longer holds.
        await update($, logAtom, () => [])
        await update($, conversationAtom, n => n + 1)
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

    return { text: 'Usage: /mentat' }
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
    const kind: Exclude<DecisionKind, 'warning'> = input.kind ?? 'question'
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
      await addLog($, openedAt, [eventDraft('asked', `Asked you: ${question}`, kind)])
      return `d${n}`
    })
    await invalidate($)

    return { result: `Opened decision ${id}.` }
  })

  on('tool.call', { tool: CLOSE_TOOL }, async ($, e) => {
    const input = e as unknown as { id?: unknown; outcome?: unknown }
    const id = typeof input.id === 'string' ? input.id : ''
    const outcome = typeof input.outcome === 'string' ? input.outcome.trim() : ''
    const found = await inTurn(async (): Promise<'open' | GoneEntry | undefined> => {
      const item = (await read($, items)).find(d => d.id === id)
      const isOpen = item !== undefined
      const gone = [...(await read($, goneAtom))].reverse().find(g => g.id === id)
      if (!isOpen && gone === undefined) return undefined
      // A closed decision is dropped: nothing shows settled ones. So is the answer line of one that already left.
      await update($, items, all => all.filter(d => d.id !== id))
      await update($, sentAtom, sent => sent.filter(x => x.id !== id))
      if (item !== undefined) await addLog($, await $.clock.now(), [eventDraft('answered', `Closed: ${item.question}${outcome === '' ? '' : ` · ${outcome}`}`)])

      return isOpen ? 'open' : gone
    })
    if (found === undefined) {
      return { deny: `No open decision with id ${id}, and no record of it being dismissed or cleared.` }
    }
    await invalidate($)
    if (found === 'open') {
      return { result: `Closed decision ${id}.` }
    }
    if (found.why === 'dismissed') {
      return { result: `Decision ${id} was already dismissed in the pane at ${clockAt(found.at, await readZone($))}.` }
    }
    const source = found.source === undefined ? '' : (SOURCE_WORDS[found.source] ?? found.source)

    return { result: `Decision ${id} was already cleared when a new conversation started${source === '' ? '' : ` (${source})`}.` }
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
    const isMainBash = e.tool === 'Bash' && e.agentId === undefined && typeof e.command === 'string'
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
    await inTurn(async () => {
      await update($, agents, list => [...list.filter(a => a.id !== id), row].slice(-30))
    })
    await invalidate($)

    return out
  })

  on('turn.complete', async ($, e, next) => {
    const id = e.agentId
    if (id !== undefined) {
      // A subagent's turn is not its end: only the engine's list says that.
      await syncAgents($)
      await invalidate($)
    }

    return next(e)
  })

  // The footer label: Mentat's state in the prompt footer, before the engine's own mode labels.
  // `● Mentat`: dim until a `mentat check` has run, then green, amber with the warning count, or red. While
  // items wait it reads `● Mentat · N waiting` instead, N counting every open item, only the dot in the
  // check's color. On the terminal the label is a
  // Button that opens the pane (there is no band there); on the desktop it is the same text, and the
  // band is there.
  on('ui.render', { component: 'SessionMode' }, async ($, e, next) => {
    if (e.surface !== 'terminal' && e.surface !== 'desktop') return next(e)
    const result = await read($, checkResult)
    const waiting = (await read($, items)).length
    const { Box, Button, Text } = $.ui.resolve(e)
    const modes = e.props.modes
    const [text, color] =
      result === null
        ? ['● Mentat', undefined]
        : result.state === 'fail'
          ? ['● Mentat check failed', 'error']
          : result.state === 'warn'
            ? [`● Mentat · ${plural(result.warnings.length, 'warning', 'warnings')}`, 'warning']
            : ['● Mentat', 'success']
    // Nothing open: the label as it was, all of it in the check's color. While items wait: only the dot is in
    // the check's color, `Mentat` is plain, and the check's own words are left out (its item carries them).
    const mark = (word: string) => (color === undefined ? <Text key="mark" dimColor>{word}</Text> : <Text key="mark" color={color}>{word}</Text>)
    const parts =
      waiting === 0
        ? [mark(text)]
        : [mark('●'), <Text key="name">{' Mentat'}</Text>, <Text key="sep" dimColor>{' · '}</Text>, <Text key="count" color="warning">{`${waiting} waiting`}</Text>]
    const label = e.surface === 'terminal' ? (
      <Button key="mentat-open" plain label={waiting === 0 ? text : `● Mentat · ${waiting} waiting`} onPress={() => $.ui.open({ id: PANE, title: TITLE })}>
        {parts}
      </Button>
    ) : (
      <Box key="mentat-label" flexDirection="row">
        {parts}
      </Box>
    )

    return (
      <Box flexDirection="row" gap={1}>
        {label}
        {modes.length > 0 && <Text dimColor>{modes.join(' & ')}</Text>}
      </Box>
    )
  })

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    // The terminal has no band of Mentat's: the footer label opens the pane. What is beneath stays.
    if (e.props.hasSurvey || e.surface !== 'desktop') {
      return next(e)
    }
    // The desktop band is always there: what waits on the maintainer, else a budget warning, else the newest
    // Log note, else a quiet line. Nothing in it comes from GitHub.
    const open = await read($, items)
    const now = await $.clock.now()
    const urgent = mostUrgent(open)
    // Budget raises it only when no item waits. It is read when the band is drawn, and the minute timer
    // draws the band again, so a change of usage alone shows within a minute.
    const budget = urgent === undefined ? budgetAlert(limitsOf(await readUsage($), now, await readZone($))) : undefined
    const logList = urgent === undefined && budget === undefined ? await read($, logAtom) : []
    // Only a note is the band's line, never an event line.
    const note = [...logList].reverse().find(isNote)
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
            <Link href={link} label={shortLink(link)} />
          </Text>
        )}
        <Button key="open" label="Details" onPress={() => $.ui.open({ id: PANE, title: TITLE })} />
      </Box>
    )
    // The band is shared: what the plugins beneath draw stays, under this row.
    const beneath = await next(e)
    const { Svg } = $.ui.resolve(e)
    // The mark: the item's kind, the note's icon in its color, the rate limit's; the quiet line has none.
    const mark =
      left.kind === 'quiet'
        ? undefined
        : left.kind === 'note'
          ? { char: left.icon, hue: left.hue, alt: 'Note' }
          : { ...MARK[left.kind], alt: left.kind === 'budget' ? 'Rate limit' : ITEM_ALT[left.kind] }
    // An item's text is bold, the budget line is in the warning color, a note is plain and the quiet line muted.
    const textProps = left.kind === 'quiet' ? { dimColor: true } : left.kind === 'budget' ? { color: 'warning' } : left.kind === 'note' ? {} : { bold: true }

    // One native row, so it follows the divider with no redraw from the mod: the mark, the text (the only part
    // that shrinks, cut with `…`; minWidth 0 because a flex item never shrinks below its content otherwise),
    // the `+N more` pill right after it, a spacer that takes the rest, then the controls.
    // The outer column holds `beneath`, an engine node, and the engine refuses an engine node under a Box
    // with minWidth (it then draws its own band): so no minWidth on this Box or any other above `beneath`.
    return (
      <Box key="band" flexDirection="column">
        <Box key="band-row" flexDirection="row" alignItems="center" gap={1} minWidth={0}>
          {mark !== undefined && (
            <Box key="mark" width={MARK_CELLS} flexShrink={0}>
              <Svg source={markSvg(mark.char, mark.hue)} alt={mark.alt} width={MARK_SIZE} height={MARK_SIZE} />
            </Box>
          )}
          <Box key="text" flexShrink={1} minWidth={0} overflow="hidden">
            <Text wrap="truncate-end" {...textProps}>
              {left.text}
            </Text>
          </Box>
          {more !== '' && (
            <Box key="more" flexShrink={0} paddingX={1} backgroundColor={MORE_TINT}>
              <Text color="warning">{more}</Text>
            </Box>
          )}
          <Box key="spacer" flexGrow={1} minWidth={0} />
          {controls()}
        </Box>
        {beneath}
      </Box>
    )
  })

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    if (e.surface !== 'desktop') return terminalPane($, e, e.props.bodyColumns ?? 50)

    return desktopPane($, e)
  })
}
