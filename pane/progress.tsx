// Mentat's pane. There is no band: on both surfaces the footer label counts what waits and opens the pane.
// The pane has two sections, Waiting on you and the Feed (the agents that have not ended, then the log); the
// desktop draws them as two cards of native rows, the terminal as bordered text.
// Claude Code reads this file as a mod (hooks/hooks.json lists it under "modules");
// it approves, denies or changes no other tool call.
//
// Everything a drawing reads lives in $.state (pane/types.d.ts); render hooks never
// write it. Every $ call is in a hook or in a top-level function that takes $.

import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register, RenderElement } from 'claude-code'

import type { AgentRow, AgentStatus, CheckResult, Decision, DecisionKind, EventKind, EventMark, GoneEntry, LogEntry, LogKind, NoteEntry, SavedConversation } from './types'

const PLUGIN = 'mentat'
const PANE = 'mentat'
const TITLE = 'Mentat'
const OPEN_TOOL = `mcp__${PLUGIN}__open_decision`
const CLOSE_TOOL = `mcp__${PLUGIN}__close_decision`
const NOTE_TOOL = `mcp__${PLUGIN}__note`
// A rate limit this far gone is warned at the top of the pane.
const WARN_PERCENT = 80
// The terminal pane's width classes, in body columns: sections have a border from FRAME_COLUMNS, headed by a
// rule from RULE_COLUMNS, and below that also drop the times, the recommendation and the WARN lines.
const FRAME_COLUMNS = 60
const RULE_COLUMNS = 40
// The Log keeps this many entries; a line is one line of whitespace-collapsed text, cut only past
// LOG_TEXT_LIMIT characters (a safety limit: the Feed wraps text, it does not cut it). The Feed shows the
// newest FEED_SHOWN until `Show all`.
const LOG_LIMIT = 200
const FEED_SHOWN = 10
const LOG_TEXT_LIMIT = 1000
// The record of items that left without close_decision keeps this many entries.
const GONE_LIMIT = 50
// The conversations kept in $.store, one key per session id (several sessions can run at once, and each
// writes only its own key): the newest SESSIONS_KEPT, pruned at a session start.
const STORE_PREFIX = 'conv:'
const storeKey = (sessionId: string): string => `${STORE_PREFIX}${sessionId}`
const SESSIONS_KEPT = 20

const items = atom({ plugin: 'mentat', key: 'decisionsItems' } as const, [])
const nextId = atom({ plugin: 'mentat', key: 'decisionsNextId' } as const, 1)
const sentAtom = atom({ plugin: 'mentat', key: 'decisionsSent' } as const, [])
const agents = atom({ plugin: 'mentat', key: 'agents' } as const, [])
const checkResult = atom({ plugin: 'mentat', key: 'checkResult' } as const, null)
const logAtom = atom({ plugin: 'mentat', key: 'log' } as const, [])
const logAll = atom({ plugin: 'mentat', key: 'logAll' } as const, false)
const goneAtom = atom({ plugin: 'mentat', key: 'decisionsGone' } as const, [])
// The session id the conversation state belongs to; see classic.SessionStart.
const ownerAtom = atom({ plugin: 'mentat', key: 'sessionOwner' } as const, null)

// The id of the item the mod itself pins for a `mentat check`: an alert after a failed run, a
// warning after a passing run with warnings. The next run replaces it, and a clean pass removes it.
const CHECK_ID = 'check'

// The Feed marks only three things, each with an icon and a theme color (so the line reads on the terminal and
// the desktop): a success, a failure, and something that wants attention. Every other entry has no mark, and
// its mark column is a space so the text still lines up.
const MARKS = {
  success: { icon: '✓', color: 'success' },
  failure: { icon: '✕', color: 'error' },
  attention: { icon: '!', color: 'warning' },
  none: { icon: ' ', color: undefined },
} as const
type FeedMark = { icon: string; color: string | undefined }
// The notes Claude Code adds with the `note` tool: a done note is a success and a surprise wants attention; a
// decision, a plan and a wait are plain.
const NOTE_MARK: Record<LogKind, FeedMark> = {
  decision: MARKS.none,
  plan: MARKS.none,
  surprise: MARKS.attention,
  waiting: MARKS.none,
  done: MARKS.success,
}
const NOTE_KINDS: readonly LogKind[] = ['decision', 'plan', 'surprise', 'waiting', 'done']
const isNoteKind = (v: unknown): v is LogKind => NOTE_KINDS.includes(v as LogKind)
// The event lines the pane writes to the Log itself, drawn dim. A `check` line takes the mark of the result.
const EVENT_MARK: Partial<Record<EventKind, FeedMark>> = {
  agentDone: MARKS.success,
  agentFailed: MARKS.failure,
  prOpened: MARKS.none,
  pushed: MARKS.none,
}
const RESULT_MARK: Record<EventMark, FeedMark> = {
  pass: MARKS.success,
  warn: MARKS.attention,
  fail: MARKS.failure,
}
// An entry stored without a source is a note.
export const isNote = (entry: LogEntry): entry is NoteEntry => entry.source !== 'event'
// The icon and color a Log row is drawn with.
const styleOf = (entry: LogEntry): FeedMark => {
  if (isNote(entry)) return NOTE_MARK[entry.kind] ?? MARKS.none
  if (entry.kind === 'check') return (entry.mark === undefined ? undefined : RESULT_MARK[entry.mark]) ?? MARKS.none

  return EVENT_MARK[entry.kind] ?? MARKS.none
}

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
// One line (whitespace collapsed), at most `max` characters, cut with an ellipsis only past that.
const oneLine = (text: string, max: number = LOG_TEXT_LIMIT): string => {
  const chars = [...text.replace(/\s+/g, ' ').trim()]

  return chars.length <= max ? chars.join('') : `${chars.slice(0, max - 1).join('').trimEnd()}…`
}

type Meter = { kind: string; label: string; percent: number; reset: string }
type Usage = Awaited<ReturnType<EngineInterface['session']['usage']>>

// The rate limits as the pane reads them, each with its percent and the reset: a countdown for the
// 5-hour limit, the weekday and local time for the weekly one.
const limitsOf = (usage: Usage | undefined, now: number, zone?: string): Meter[] =>
  (usage?.rateLimits ?? []).map(r => ({
    kind: r.kind,
    label: r.kind === 'five_hour' ? '5-hour' : r.kind === 'seven_day' ? 'Week' : r.kind,
    percent: Math.round(r.percentUsed),
    reset: r.kind === 'seven_day' ? resetAt(r.resetsAt, now, zone) : resetIn(r.resetsAt, now),
  }))

// The pane's budget text, for the most used of the 5-hour and weekly limits when it
// is at WARN_PERCENT or more. The context window never raises it.
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
// Fits the rows to what the engine lists: statuses follow the engine, an agent the mod never saw is added
// without a start, and one the engine no longer lists is ended (unknown), never finished. An agent that
// goes from ended back to live (a builder resumed with a message) starts its time over at the moment the
// mod saw it, so the time it sat idle is not counted.
const reconcile = (rows: AgentRow[], infos: AgentInfoLike[], now: number): AgentRow[] => {
  const next = rows.map(row => {
    const info = infos.find(i => i.id === row.id)
    if (info === undefined) return isEnded(row.status) ? row : { ...row, status: 'unknown' as const, endedAt: now }
    if (isEnded(info.status)) return { ...row, status: info.status, endedAt: row.endedAt ?? now }
    const { endedAt: _endedAt, ...rest } = row
    return { ...rest, status: info.status, ...(isEnded(row.status) ? { startedAt: now } : {}) }
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

// ---- the conversation kept between processes ---------------------------------------------------
// $.state is gone when the process ends, so a `claude --continue` or `--resume` (same session id) would
// start empty. The conversation's own state (not the agent rows, which the engine lists, nor the view
// toggles) is also kept in $.store under its session id, written after each change, newest SESSIONS_KEPT.

// Entries of these kinds were written by earlier versions: the Feed records the work, not the pane's own
// bookkeeping, so they are dropped wherever the log is loaded or read.
const LEFTOVER_KINDS: readonly string[] = ['asked', 'answered', 'dismissed']
const withoutLeftovers = (list: LogEntry[]): LogEntry[] => list.filter(x => x.source !== 'event' || !LEFTOVER_KINDS.includes(x.kind))

// What a stored entry gives back, with every field checked: a value of the wrong shape is empty.
function loadConversation(stored: unknown): Omit<SavedConversation, 'savedAt'> {
  const o = asObj(stored)
  const list = <T,>(v: unknown): T[] => (Array.isArray(v) ? (v as T[]) : [])
  const result = asObj(o.checkResult)
  const hasResult = result.state === 'pass' || result.state === 'warn' || result.state === 'fail'

  return {
    items: withoutSettled(list<Decision>(o.items)),
    nextId: typeof o.nextId === 'number' && Number.isFinite(o.nextId) && o.nextId >= 1 ? o.nextId : 1,
    sent: list(o.sent),
    log: withoutLeftovers(list<LogEntry>(o.log)),
    checkResult: hasResult ? { state: result.state as CheckResult['state'], warnings: list<string>(result.warnings) } : null,
    gone: list(o.gone),
  }
}

// Saves the conversation under the session id its state belongs to, when it differs from what is stored;
// an entry that would be empty is removed instead. Call it inside inTurn, after the change. It never throws:
// a store that fails leaves the pane as it is. A state with no owner yet (a new process before its session
// start) is no conversation's and is not kept; saving it would overwrite what that session start is about to load.
async function saveConversation($: EngineInterface): Promise<void> {
  try {
    const id = await read($, ownerAtom)
    if (id === null) return
    const entry = {
      items: await read($, items),
      nextId: await read($, nextId),
      sent: await read($, sentAtom),
      log: await read($, logAtom),
      checkResult: await read($, checkResult),
      gone: await read($, goneAtom),
    }
    const stored = await $.store.get(storeKey(id))
    const former = stored === undefined ? undefined : loadConversation(stored)
    if (former !== undefined && JSON.stringify(former) === JSON.stringify(loadConversation(entry))) return
    const isEmpty = entry.items.length === 0 && entry.log.length === 0 && entry.gone.length === 0 && entry.sent.length === 0 && entry.checkResult === null
    if (isEmpty) {
      if (former !== undefined) await $.store.delete(storeKey(id))
      return
    }
    await $.store.set(storeKey(id), { savedAt: await $.clock.now(), ...entry })
  } catch {
    // the in-memory state is right; the next change saves again
  }
}

// Deletes the conversations past the newest SESSIONS_KEPT, by when each was saved. Run at a session start,
// not on every save. The session that is starting is never the one dropped: it keeps its place.
async function pruneConversations($: EngineInterface, current: string): Promise<void> {
  try {
    const keys = (await $.store.keys()).filter(k => k.startsWith(STORE_PREFIX) && k !== storeKey(current))
    const saved = await Promise.all(keys.map(async key => ({ key, at: Number(asObj(await $.store.get(key)).savedAt ?? 0) })))
    for (const { key } of saved.sort((a, b) => b.at - a.at).slice(SESSIONS_KEPT - 1)) await $.store.delete(key)
  } catch {
    // the next session start prunes again
  }
}

// inTurn for a change to the kept state: saves the conversation when the change is done.
const inTurnSaved = <T,>($: EngineInterface, work: () => Promise<T>): Promise<T> =>
  inTurn(async () => {
    const out = await work()
    await saveConversation($)

    return out
  })

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
    // No duration: an agent resumed after it finished keeps no honest start to measure from.
    if (row.status === 'completed') {
      drafts.push(eventDraft('agentDone', who))
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
      const events = agentEvents(before, after)
      await addLog($, now, events)
      // The agent rows are not kept; only an event line they wrote is.
      if (events.length > 0) await saveConversation($)
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

// The branches a `git push` pushed, read from the lines git prints for them (`   abc1234..def5678  main -> main`,
// ` + abc1234...def5678  main -> main (forced update)`, ` * [new branch]      topic -> topic`), by the remote's
// name. Git's output has no count of commits, so none is given. Nothing is returned (so no line is written) unless
// every line is one of those or part of the usual chatter: a rejected ref, an error, a dry run, a push that
// printed no ref line (`Everything up-to-date`) or any other doubt writes nothing.
const PUSH_COMMAND = /(?:^|[\s;&|(])git\s+(?:-C\s+\S+\s+)?push(?=$|[\s;&|)])/
const PUSH_DRY_RUN = /(?:^|\s)(?:--dry-run|-n)(?=$|\s)/
const PUSH_RANGE = /^\s*[+ ]?\s*[0-9a-f]{7,40}\.\.\.?[0-9a-f]{7,40}\s+\S+\s+->\s+(\S+)(?:\s+\([^)]*\))?\s*$/
const PUSH_NEW = /^\s*\*\s+\[new branch\]\s+\S+\s+->\s+(\S+)\s*$/
const PUSH_FAILED = /^\s*!\s|^error:|^fatal:|\[(?:remote )?rejected\]|failed to push/
const pushedBranches = (command: string, output: string): string[] => {
  if (!PUSH_COMMAND.test(command) || PUSH_DRY_RUN.test(command)) return []
  const lines = output.replace(/\r/g, '').split('\n')
  if (lines.some(l => PUSH_FAILED.test(l))) return []
  const branches: string[] = []
  for (const l of lines) {
    const found = PUSH_RANGE.exec(l) ?? PUSH_NEW.exec(l)
    if (found !== null && !branches.includes(found[1]!)) branches.push(found[1]!)
  }

  return branches
}

// What the main loop's Bash call says: a pull request it opened, a push it made.
async function afterBash($: EngineInterface, command: string, stdout: string, stderr: string): Promise<void> {
  try {
    const pushed = pushedBranches(command, `${stdout}\n${stderr}`)
    if (pushed.length > 0) {
      const at = await $.clock.now()
      await inTurnSaved($, () => addLog($, at, [eventDraft('pushed', `Pushed ${pushed.join(', ')}`)]))
      await invalidate($)
    }
    if (/\bgh\s+pr\s+create\b/.test(command)) {
      const urls = [...stdout.matchAll(ghPrUrl)]
      const last = urls[urls.length - 1]
      if (last !== undefined) {
        const at = await $.clock.now()
        await inTurnSaved($, () => addLog($, at, [eventDraft('prOpened', `Opened PR #${last[2]}`)]))
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
  await inTurnSaved($, async () => {
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

// ---- Drawn desktop pieces: the small round marks of the pane; text, rows and buttons are native. ----
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
// The mark of each kind of open item on the desktop: its glyph and hue.
const MARK: Record<DecisionKind, { char: string; hue: string }> = {
  alert: { char: '!', hue: HUE.red },
  question: { char: '?', hue: HUE.amber },
  warning: { char: '!', hue: HUE.amber },
  action: { char: '→', hue: HUE.blue },
}
// The description of an item in the alt text of its mark.
const ITEM_ALT: Record<DecisionKind, string> = { question: 'Question', action: 'Waiting on you', alert: 'Alert', warning: 'Check warnings' }
// The items that wait on the maintainer, most urgent first: alert, then question, check warning, action; the
// newest of a kind first. Both panes list them all.
const urgentFirst = (list: Decision[]): Decision[] =>
  [...list].reverse().sort((a, b) => KIND_RANK[kindOf(a)] - KIND_RANK[kindOf(b)])

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
  const isFirst = await inTurnSaved($, async () => {
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
    await inTurnSaved($, () => update($, sentAtom, list => list.filter(x => x.id !== d.id || x.isDelivered === true)))
    $.ui.toast('Answer not sent: Claude Code did not take it. Press again.')
    return false
  }
  // The answer entered the session; the line stops saying it waits.
  await inTurnSaved($, () => update($, sentAtom, list => list.map(x => (x.id === d.id ? { ...x, isDelivered: true } : x))))
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

  return inTurnSaved($, async () => {
    const item = (await read($, items)).find(x => x.id === id)
    await update($, items, all => all.filter(x => x.id !== id))
    await update($, sentAtom, list => list.filter(x => x.id !== id))
    if (item !== undefined) {
      await recordGone($, [{ id, why: 'dismissed', at }])
    }
  })
}
// How close_decision names the way a new conversation started.
const SOURCE_WORDS: Record<string, string> = { clear: '/clear', resume: '/resume', fork: '/branch' }

// ---- the terminal pane: Waiting on you, then the Feed ----

type Layout = 'frame' | 'rule' | 'narrow'
const layoutOf = (cols: number): Layout => (cols >= FRAME_COLUMNS ? 'frame' : cols >= RULE_COLUMNS ? 'rule' : 'narrow')
// The pieces of a heading rule, which together are exactly `cols` characters wide: `── TITLE 3 ───`. The title is
// drawn bold and the count dim, so they are apart. (A frame has a real Box border and a plain heading row.)
const ruleEdge = (title: string, count: number, cols: number): { head: string; title: string; count: string; fill: string } => {
  const head = '── '
  const shown = ` ${count}`
  const room = cols - head.length - title.length - shown.length - 1

  return { head, title, count: shown, fill: ` ${'─'.repeat(Math.max(0, room))}` }
}
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
  // `time` is the clock time of the entry, shown only on the first row of a run of the same time (`isTimed`).
  entries: { entry: LogEntry; n: number; time: string; isTimed: boolean }[]
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
  const logList = withoutLeftovers(await read($, logAtom))
  const isLogAll = await read($, logAll)
  const budget = budgetAlert(limitsOf(await readUsage($), now, zone))
  const newest = logList.map((entry, n) => ({ entry, n })).reverse()
  const toggle = logList.length > FEED_SHOWN ? (isLogAll ? 'Show fewer' : `Show all ${logList.length}`) : undefined

  const shown = (isLogAll ? newest : newest.slice(0, FEED_SHOWN)).map(x => ({ ...x, time: clockAt(x.entry.at, zone) }))
  // The time is written once for a run of consecutive rows with the same displayed time; the rows after it leave it blank.
  const entries = shown.map((x, i) => ({ ...x, isTimed: i === 0 || shown[i - 1]!.time !== x.time }))

  return { now, zone, open, sentList, result, live, logList, isLogAll, entries, toggle, budget }
}
const toggleLogAll = ($: EngineInterface) => inTurn(() => update($, logAll, v => !v))
// True when the recommendation only repeats the answer button's label (trimmed, case-insensitive).
const isSameWords = (a: string, b: string | undefined): boolean => b !== undefined && a.trim().toLowerCase() === b.trim().toLowerCase()
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
    detail: d.recommendation === undefined || isSameWords(d.recommendation, d.accept) ? time : `Recommended: ${d.recommendation} · ${time}`,
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

  // One body row. The text Box grows and shrinks and wraps under itself, so a row that ends in Buttons needs no
  // width arithmetic and the right edge stays where it is; the other parts are top-aligned beside it.
  const row = (key: string, children: RenderElement[], gap = 1) => (
    <Box key={key} flexDirection="row" alignItems="flex-start" gap={gap}>
      {children}
    </Box>
  )
  // A dim line under an item's text, indented to it (the mark and the space after it), wrapped.
  const detail = (key: string, text: string) =>
    row(key, [
      <Box key="text" flexGrow={1} flexShrink={1} paddingLeft={2}>
        <Text dimColor wrap="wrap">
          {text}
        </Text>
      </Box>,
    ])
  // A section: in a frame (from FRAME_COLUMNS) a Box with a dim round border and the heading as its first row;
  // below that the heading is a rule of exactly `cols` characters, with no border.
  const section = (key: string, title: string, count: number, rows: RenderElement[], gap: boolean) => {
    const edge = ruleEdge(title, count, cols)
    const heading =
      layout === 'frame' ? (
        <Box key={`${key}-top`} flexDirection="row" gap={1}>
          <Text bold>{title}</Text>
          <Text dimColor>{count}</Text>
        </Box>
      ) : (
        <Box key={`${key}-top`} flexDirection="row">
          <Text dimColor>{edge.head}</Text>
          <Text bold>{edge.title}</Text>
          <Text dimColor>{edge.count}</Text>
          <Text dimColor>{edge.fill}</Text>
        </Box>
      )

    return layout === 'frame' ? (
      <Box key={key} flexDirection="column" marginTop={gap ? 1 : 0} borderStyle="round" borderDimColor paddingX={1}>
        {heading}
        {rows}
      </Box>
    ) : (
      <Box key={key} flexDirection="column" marginTop={gap ? 1 : 0}>
        {heading}
        {rows}
      </Box>
    )
  }

  // Waiting on you: every open item, most urgent first. The first row holds the mark and the text, full width.
  // Under it a row holds the detail (the recommendation and the time), wrapped at the left, and the buttons at
  // the right; then, for the check's warning item, its WARN lines. Under 40 columns the time and the
  // recommendation are left out and the row holds only the buttons, at the right.
  const waiting = open.map((d, index) => {
    const { kind, sent, answer, link, detail: recommended, warns } = itemView(d, data)
    const mark = ITEM_MARK[kind]
    const lines: RenderElement[] = [
      // The mark never shrinks and keeps its space after it (a margin, which a tight row cannot take away);
      // the text is what wraps.
      row(`item-${d.id}`, [
        <Box key="mark-box" flexShrink={0} marginRight={1}>
          {mark.color === undefined ? <Text key="mark" dimColor>{mark.char}</Text> : <Text key="mark" color={mark.color}>{mark.char}</Text>}
        </Box>,
        <Box key="text" flexGrow={1} flexShrink={1}>
          <Text wrap="wrap">{d.question}</Text>
        </Box>,
      ], 0),
      // The detail grows and shrinks and wraps under itself; the controls keep their size at the right.
      <Box key={`actions-${d.id}`} flexDirection="row" alignItems="flex-start" justifyContent="flex-end" gap={1}>
        {!isShort && (
          <Box key="detail" flexGrow={1} flexShrink={1} paddingLeft={2}>
            <Text dimColor wrap="wrap">
              {recommended}
            </Text>
          </Box>
        )}
        <Box key="controls" flexDirection="row" gap={1} flexShrink={0}>
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
        </Box>
      </Box>,
    ]
    if (!isShort) warns.forEach((w, i) => lines.push(detail(`warn-${i}`, w)))

    // One blank row between items, not after the last.
    return (
      <Box key={`block-${d.id}`} flexDirection="column" marginTop={index === 0 ? 0 : 1}>
        {lines}
      </Box>
    )
  })

  // The Feed: the agents that have not ended, pinned, then the log newest first.
  const feedRows: RenderElement[] = live.map(a => {
    const ran = agentClock(a, now)
    const state = ran === undefined ? a.status : `${a.status} · ${ran}`

    return row(`agent-${a.id}`, [
      <Box key="mark" flexShrink={0}>
        <Text>{ROLE_MARK[roleOf(a.type)]}</Text>
      </Box>,
      <Box key="text" flexGrow={1} flexShrink={1}>
        <Text bold wrap="wrap">
          {a.description}
        </Text>
      </Box>,
      <Box key="state" flexShrink={0}>
        <Text dimColor>{state}</Text>
      </Box>,
    ])
  })
  if (live.length > 0 && logList.length > 0) feedRows.push(row('feed-gap', [<Text key="gap"> </Text>]))
  for (const { entry, n, time, isTimed } of data.entries) {
    const { icon, color } = styleOf(entry)
    feedRows.push(
      row(`log-${n}`, [
        ...(isShort
          ? []
          : [
              <Box key="time" width={8} flexShrink={0} justifyContent="flex-end">
                <Text dimColor>{isTimed ? time : ' '}</Text>
              </Box>,
            ]),
        <Box key="icon" flexShrink={0}>
          <Text {...(color === undefined ? {} : { color })}>{icon}</Text>
        </Box>,
        <Box key="text" flexGrow={1} flexShrink={1}>
          <Text wrap="wrap" {...(isNote(entry) ? {} : { dimColor: true })}>
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
// The space between the items of the desktop's Waiting on you card, in rows: each item reads as its own block.
const WAITING_GAP = 2
const TEXT_INDENT = MARK_CELLS + 1
// A small round tinted mark with a glyph, a fixed 20px Svg; it is the only picture in the pane, and it does
// not take part in the reflow when the divider moves.
const MARK_SIZE = 20
const markSvg = (char: string, hue: string): string =>
  svgOf(MARK_SIZE, MARK_SIZE, `<circle cx="10" cy="10" r="10" fill="${hue}" opacity="0.18"/><text fill="${hue}" x="10" y="14.5" text-anchor="middle" font-family="${FONT}" font-size="12" font-weight="700">${xml(char)}</text>`)

// The pane on the desktop: the same sections, entries and order as the terminal's, drawn as rows of native
// Box and Text. Nothing here is measured: the text Box grows and shrinks (and the text wraps under itself), so
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
  // The text of a row: the only part that shrinks. It wraps under itself, so no overflow is hidden.
  const cut = (text: string, props: { bold?: boolean; dimColor?: boolean } = {}) => (
    <Box flexGrow={1} flexShrink={1} minWidth={0}>
      <Text wrap="wrap" {...props}>
        {text}
      </Text>
    </Box>
  )

  const waiting = open.map(d => {
    const { kind, sent, answer, link, detail, warns } = itemView(d, data)
    const mark = MARK[kind]

    return (
      <Box key={`item-${d.id}`} flexDirection="column" minWidth={0}>
        <Box flexDirection="row" alignItems="flex-start" gap={1} minWidth={0}>
          <Box width={MARK_CELLS} flexShrink={0}>
            <Svg source={markSvg(mark.char, mark.hue)} alt={ITEM_ALT[kind]} width={MARK_SIZE} height={MARK_SIZE} />
          </Box>
          {cut(d.question)}
        </Box>
        <Box key="actions" paddingLeft={TEXT_INDENT} marginTop={1} flexDirection="row" alignItems="center" gap={1} minWidth={0}>
          {cut(detail, { dimColor: true })}
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
        {warns.map((line, i) => (
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
      <Box key={`agent-${a.id}`} flexDirection="row" alignItems="flex-start" gap={1} minWidth={0}>
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
  const logRows = data.entries.map(({ entry, n, time, isTimed }) => {
    const { icon, color } = styleOf(entry)

    return (
      <Box key={`log-${n}`} flexDirection="row" alignItems="flex-start" gap={1} minWidth={0}>
        {timeColumn(<Text dimColor>{isTimed ? time : ' '}</Text>)}
        <Box flexShrink={0}>
          <Text {...(color === undefined ? {} : { color })}>{icon}</Text>
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
      {open.length > 0 && card('card-waiting', 'WAITING ON YOU', 'warning', open.length, <Box key="items" flexDirection="column" gap={WAITING_GAP} minWidth={0}>{waiting}</Box>)}
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
          text: { type: 'string', description: 'One plain line, about 80 characters at most' },
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
    await inTurnSaved($, () => update($, items, withoutSettled))
    await inTurnSaved($, () => update($, logAtom, withoutLeftovers))
    // A submit that was still waiting for a turn is lost with the old load: its question
    // offers its buttons again. A delivered answer stays marked.
    await inTurnSaved($, () => update($, sentAtom, list => list.filter(x => x.isDelivered === true)))
    agentTimer?.cancel()
    refreshTimer?.cancel()
    await syncAgents($)
    agentTimer = $.clock.every(1000, () => void agentTick($))
    // A minute tick only redraws, so an idle session shows a rate limit that crossed the warning line.
    refreshTimer = $.clock.every(60_000, () => void invalidate($))
    void startCheck($, e.cwd)

    return next(e)
  })

  // A conversation starts or goes on (a startup, /clear, /resume, /branch, a `--continue` or `--resume`, a
  // compaction). The state belongs to the session id it was kept for (sessionOwner); one rule decides:
  // - the same id (a compaction, a resume of this conversation inside this process): keep everything;
  // - another id, or no owner yet (a new process): the open items of the former conversation are recorded
  //   as gone, and what $.store holds for the new id is loaded (nothing, for the new id a /clear or /branch
  //   gives, so it starts empty). A mod reload (session.start) and a compaction keep the state as it is.
  on('classic.SessionStart', async ($, e, next) => {
    if (e.source === 'compact') return next(e)
    const at = await $.clock.now()
    let isChanged = false
    let hasCheck = false
    // A startup in a process with no conversation yet: the mod load (session.start) runs its check.
    let isFirstStartup = false
    await inTurn(async () => {
      const former = await read($, ownerAtom)
      if (former === e.session_id) return
      isChanged = true
      isFirstStartup = e.source === 'startup' && former === null
      // A check still running for the former conversation writes nothing.
      if (!isFirstStartup) checkEpoch += 1
      let stored: unknown
      try {
        stored = await $.store.get(storeKey(e.session_id))
      } catch {
        // a store that cannot be read: the conversation starts empty
      }
      const loaded = loadConversation(stored)
      hasCheck = loaded.checkResult !== null
      // Open questions belong to the conversation they were asked in; close_decision still explains them.
      const cleared: GoneEntry[] = (await read($, items)).map(d => ({ id: d.id, why: 'cleared', source: e.source, at }))
      const formerGone = await read($, goneAtom)
      await update($, items, () => loaded.items)
      // Ids keep counting across the switch, so an id that left is never handed out again.
      await update($, nextId, n => Math.max(n, loaded.nextId))
      // An answer still waiting for its turn is lost with the process; a delivered one stays marked.
      await update($, sentAtom, () => loaded.sent.filter(x => x.isDelivered === true))
      await update($, checkResult, () => loaded.checkResult)
      // The log of the former conversation goes.
      await update($, logAtom, () => loaded.log)
      await update($, goneAtom, () => [...loaded.gone, ...formerGone, ...cleared].slice(-GONE_LIMIT))
      await update($, ownerAtom, () => e.session_id)
      await saveConversation($)
      await pruneConversations($, e.session_id)
    })
    if (isChanged) {
      await invalidate($)
      // The new conversation's check, unless the one kept for it is still there.
      if (!hasCheck && !isFirstStartup) void startCheck($)
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
    const id = await inTurnSaved($, async () => {
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
    const found = await inTurnSaved($, async (): Promise<'open' | GoneEntry | undefined> => {
      const item = (await read($, items)).find(d => d.id === id)
      const isOpen = item !== undefined
      const gone = [...(await read($, goneAtom))].reverse().find(g => g.id === id)
      if (!isOpen && gone === undefined) return undefined
      // A closed decision is dropped: nothing shows settled ones. So is the answer line of one that already left.
      await update($, items, all => all.filter(d => d.id !== id))
      await update($, sentAtom, sent => sent.filter(x => x.id !== id))

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
    const text = typeof input.text === 'string' ? oneLine(input.text) : ''
    if (text === '') {
      return { deny: 'note needs a line of text.' }
    }
    if (input.kind !== undefined && !isNoteKind(input.kind)) {
      return { deny: `note kind must be ${NOTE_KINDS.join(', ')}.` }
    }
    const kind: LogKind = input.kind ?? 'plan'
    await inTurnSaved($, async () => addLog($, await $.clock.now(), [{ kind, text }]))
    await invalidate($)

    return { result: 'Noted.' }
  })

  on('tool.call', async ($, e, next) => {
    const isMainBash = e.tool === 'Bash' && e.agentId === undefined && typeof e.command === 'string'
    const ran = await next(e)
    if (isMainBash) {
      const result = asObj((ran as { result?: unknown }).result)
      void afterBash($, e.command as string, str(result.stdout), str(result.stderr))
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
  // check's color. On both surfaces the label is a Button that opens the pane (there is no band).
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
    const label = (
      <Button key="mentat-open" plain label={waiting === 0 ? text : `● Mentat · ${waiting} waiting`} onPress={() => $.ui.open({ id: PANE, title: TITLE })}>
        {parts}
      </Button>
    )

    return (
      <Box flexDirection="row" gap={1}>
        {label}
        {modes.length > 0 && <Text dimColor>{modes.join(' & ')}</Text>}
      </Box>
    )
  })

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    if (e.surface !== 'desktop') return terminalPane($, e, e.props.bodyColumns ?? 50)

    return desktopPane($, e)
  })
}
