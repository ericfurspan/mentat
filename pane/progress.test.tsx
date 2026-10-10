import { expect, mock, test } from 'claude-code/testing'

import { COMMANDS, resetAt, withoutSettled } from './progress'

// Tests for pane/progress.tsx. The test's hooks stand for the engine: `gh` is a
// table of canned answers (nothing talks to GitHub), `$.agent.list` and
// `$.session.usage` are tables too, and the clock moves only when a test moves it.

const OPEN = 'mcp__mentat__open_decision'
const CLOSE = 'mcp__mentat__close_decision'
const NOTE = 'mcp__mentat__note'
const BAND = { plugin: 'mentat', component: 'AbovePrompt', props: { hasSurvey: false } }
const PANE = { plugin: 'mentat', component: 'Pane', requestId: 'mentat' }
const SURFACES = ['terminal', 'desktop'] as const

const T0 = Date.parse('2026-10-09T12:00:00Z')
// The time zone reset times are shown in: the mod reads TZ, and every test sets it, so a weekly
// reset prints the same wherever the tests run.
const ZONE = 'America/New_York'
const REPO = 'o/r'
const ME = 'mentat-bot'
const CODEX = 'chatgpt-codex-connector[bot]'
const H1 = '415e6d9' + 'a'.repeat(33)
const H2 = '9f8e7d6' + 'b'.repeat(33)

// ---- fixtures: what GitHub returns ----------------------------------------

type Run = { exitCode: number; stdout: string; stderr?: string }
type Answer = Run | (() => Run | Promise<Run>)
const ok = (stdout: string): Run => ({ exitCode: 0, stdout })
const failed: Run = { exitCode: 1, stdout: '', stderr: 'gh: could not resolve' }

const CHECK_OK = { __typename: 'CheckRun', status: 'COMPLETED', conclusion: 'SUCCESS' }
const prJson = (o: Record<string, unknown> = {}) =>
  JSON.stringify({
    number: 109,
    title: 'chore: label issues by kind',
    state: 'OPEN',
    isDraft: false,
    headRefOid: H1,
    reviewDecision: 'REVIEW_REQUIRED',
    statusCheckRollup: [CHECK_OK],
    mergeStateStatus: 'BLOCKED',
    updatedAt: '2026-10-09T11:59:00Z',
    ...o,
  })

// The Codex app's summary comment, as GitHub returns it (the format tests/review.sh uses).
const summary = (sha: string, status = 'Completed', login = CODEX) => ({
  id: 1,
  user: { login },
  body: `<!-- codex-pull-request-review-summary -->\n\n## Codex Review Summary\n\n| Review | Status | Commit | Review trigger |\n| --- | --- | --- | --- |\n| 📝 **Code Review** | ✅ **${status}** <relative-time datetime="2026-01-01T00:11:00.123456Z">2026-01-01T00:11:00.123456Z</relative-time> | \`${sha.slice(0, 7)}\` | Draft marked ready |\n`,
})
// A pull request review object (not an inline comment), as GET pulls/N/reviews returns it.
const reviewOf = (sha: string, login = CODEX) => ({ id: 77, user: { login }, commit_id: sha, html_url: 'https://example.test/review' })
const comment = (login: string, body: string, id = 500) => ({ id, user: { login }, body })
const inline = (id: number, sha: string, login = CODEX, inReplyTo?: number) => ({
  id,
  user: { login },
  commit_id: sha,
  path: 'a.ts',
  line: 3,
  body: 'finding',
  ...(inReplyTo === undefined ? {} : { in_reply_to_id: inReplyTo }),
})
const finalCheck = (sha: string, login = ME) => comment(login, `Final check on ${sha.slice(0, 7)}: tests and CI pass.`, 900)
const localReview = (sha: string, result = 'NO FINDINGS', login = ME) =>
  comment(login, `## Local Codex review of ${sha}\n\n- Run locally by the agent.\n\n---\n\nNothing to flag.\n\nREVIEW RESULT: ${result}\n`, 901)
// `gh api --paginate` prints each page as its own array, one after the other.
const pages = (...ps: unknown[][]) => ps.map(p => JSON.stringify(p)).join('')

// ---- the world beneath the plugin -------------------------------------------

type Usage = { context?: number; limits?: { kind: string; percentUsed: number; resetsAt?: string }[] }
type World = {
  repo: Answer
  pr: Answer
  prList: Answer
  me: Answer
  issueComments: Answer
  pullComments: Answer
  reviews: Answer
  // `git rev-parse --is-inside-work-tree`: by default not a work tree, so a session start runs no check.
  git: Answer
  // `mentat check` as the pane runs it at session start; 'missing' stands for no mentat on the PATH.
  check: Answer | 'missing'
  // The directories the commands ran in, by command name.
  cwds: Record<string, string | undefined>
  bash: string
  // The stderr of a Bash call (where gh writes its success lines for pr ready, pr close and issue close).
  bashErr: string
  agents: { id: string; type: string; description: string; status: string }[]
  usage: Usage
  calls: string[][]
  peak: number
  opened: string[]
  sent: string[]
  agentCallId: string
  // When set, a Bash call does not return until it resolves.
  bashGate?: Promise<void>
  // When set, prompt.submit answers that the prompt did not enter.
  dropPrompts: boolean
  // When set, prompt.submit does not answer until it resolves (as while a turn runs).
  promptGate?: Promise<void>
  // When set, prompt.submit rejects.
  rejectPrompts: boolean
  toasts: string[]
  // The turn.step inputs that reached the bottom of the chain.
  steps: unknown[]
  // When set, $.session.usage() throws.
  usageFails: boolean
  // The slash commands the plugin ran through $.command.run, in order.
  commands: string[]
  // The tools the pane registered, as it described them.
  tools: { name: string; description: string; inputSchema: { required: string[]; properties: Record<string, { enum?: string[] }> }; isDeferred: boolean }[]
}

const isCall = (argv: string[], ...words: string[]) => words.every((w, i) => argv[i] === w)

// `band: false` leaves what the band draws beneath the plugin to the test.
const boot = (on: never, opts: { band?: boolean; zone?: string } = {}) => {
  const onFn = on as (event: string, ...rest: unknown[]) => void
  mock.env(on, { TZ: opts.zone ?? ZONE })
  const clock = mock.clock(on, { now: T0 })
  const world: World = {
    repo: ok(`${REPO}\n`),
    pr: ok(prJson()),
    prList: ok('[]'),
    me: ok(`${ME}\n`),
    issueComments: ok(pages([])),
    pullComments: ok(pages([])),
    reviews: ok(pages([])),
    git: { exitCode: 128, stdout: '', stderr: 'fatal: not a git repository' },
    check: 'missing',
    cwds: {},
    bash: '',
    bashErr: '',
    agents: [],
    usage: { context: 12, limits: [] },
    calls: [],
    peak: 0,
    opened: [],
    sent: [],
    agentCallId: '',
    dropPrompts: false,
    rejectPrompts: false,
    toasts: [],
    steps: [],
    usageFails: false,
    commands: [],
    tools: [],
  }
  let active = 0
  onFn('command.register', () => ({ value: { command: 'mentat' } }))
  onFn('tool.register', (_$: unknown, e: World['tools'][number]) => {
    world.tools.push(e)
    return { value: { tool: 'x' } }
  })
  onFn('session.start', (_$: unknown, e: { cwd: string }) => ({ cwd: e.cwd }))
  onFn('ui.invalidate', () => ({ value: undefined }))
  onFn('ui.open', (_$: unknown, e: { id: string }) => {
    world.opened.push(e.id)
    return { value: { isPlaced: true } }
  })
  onFn('session.cwd', () => ({ value: '/work/r' }))
  onFn('agent.list', () => ({ value: world.agents }))
  onFn('agent.spawn', (_$: unknown, e: { tool_use_id: string }) => ({ model: 'claude-opus-4-8', agentId: e.tool_use_id }))
  onFn('turn.complete', (_$: unknown, e: { answer: string }) => ({ text: e.answer }))
  onFn('turn.step', async function* (_$: unknown, e: { turnId: string; index: number }) {
    world.steps.push(e)
    return { turnId: e.turnId, index: e.index, answer: 'ok', toolUses: [] }
  })
  onFn('session.usage', () => {
    if (world.usageFails) throw new Error('no usage')

    return {
      value: {
        startedAt: T0,
        context: { window: 200000, percent: world.usage.context },
        rateLimits: world.usage.limits ?? [],
      },
    }
  })
  onFn('tool.call', { tool: 'Bash' }, async () => {
    await world.bashGate
    return { result: { stdout: world.bash, stderr: world.bashErr } }
  })
  onFn('classic.SessionStart', (_$: unknown, e: unknown) => e)
  onFn('tool.call', { tool: 'Agent' }, (_$: unknown, e: { tool_use_id: string }) => {
    world.agentCallId = e.tool_use_id
    return { result: {} }
  })
  onFn('prompt.submit', async (_$: unknown, e: { text: string }) => {
    await world.promptGate
    if (world.rejectPrompts) throw new Error('the engine reloaded')
    if (world.dropPrompts) return { drop: 'a turn is running' }
    world.sent.push(e.text)
    return { text: e.text }
  })
  onFn('command.run', async (_$: unknown, e: { command: string }) => {
    world.commands.push(e.command)
    return { text: '' }
  })
  onFn('ui.toast', (_$: unknown, e: { text?: string }) => {
    world.toasts.push(JSON.stringify(e))
    return { value: undefined }
  })
  onFn('process.run', async (_$: unknown, e: { argv: string[]; init?: { cwd?: string } }) => {
    const argv = [...e.argv]
    world.calls.push(argv)
    world.cwds[argv[0]!] = e.init?.cwd
    active += 1
    world.peak = Math.max(world.peak, active)
    try {
      let answer: Answer = { exitCode: 127, stdout: '', stderr: `unexpected: ${argv.join(' ')}` }
      if (isCall(argv, 'git', 'rev-parse', '--is-inside-work-tree')) answer = world.git
      else if (isCall(argv, 'mentat', 'check')) {
        if (world.check === 'missing') throw new Error('spawn mentat ENOENT')
        answer = world.check
      } else if (isCall(argv, 'gh', 'repo', 'view')) answer = world.repo
      else if (isCall(argv, 'gh', 'pr', 'view')) answer = world.pr
      else if (isCall(argv, 'gh', 'pr', 'list')) answer = world.prList
      else if (isCall(argv, 'gh', 'api', 'user')) answer = world.me
      else if (argv[0] === 'gh' && argv[1] === 'api' && argv.some(a => a.endsWith('/issues/109/comments'))) answer = world.issueComments
      else if (argv[0] === 'gh' && argv[1] === 'api' && argv.some(a => a.endsWith('/pulls/109/comments'))) answer = world.pullComments
      else if (argv[0] === 'gh' && argv[1] === 'api' && argv.some(a => a.endsWith('/pulls/109/reviews'))) answer = world.reviews
      const run = typeof answer === 'function' ? await answer() : answer

      return { value: { exitCode: run.exitCode, stdout: run.stdout, stderr: run.stderr ?? '' } }
    } finally {
      active -= 1
    }
  })
  if (opts.band !== false) {
    // What the engine itself draws in the band, beneath every plugin.
    onFn('ui.render', ($: { ui: { resolve: (e: never) => { Box: (p: object) => unknown } } }, e: never) => {
      const { Box } = $.ui.resolve(e)
      return Box({ key: 'engine-own' })
    })
  }

  return { world, clock }
}

// ---- helpers over the drawing ---------------------------------------------------

type Found = { text?: string; key?: string; props?: Record<string, unknown> }
type Drawing = {
  findAll: (q: { type: string; text?: string | RegExp }) => Promise<Found[]>
  press: (t: { key: string }) => Promise<unknown>
  input: (t: { key: string; text: string }) => Promise<unknown>
  unmount: () => Promise<unknown>
}
const mount = async ($: never, spec: object, surface: 'terminal' | 'desktop', props: object = {}) =>
  (await ($ as { ui: { mount: (t: unknown) => Promise<unknown> } }).ui.mount({
    ...spec,
    surface,
    props: { ...(spec as { props?: object }).props, ...props },
  })) as Drawing
// The keys of a drawing's buttons, without the Commands card's toggle.
const cardKeys = async (d: Drawing) =>
  (await d.findAll({ type: 'Button' })).map(b => b.key).filter(k => k !== 'commands-toggle')
// What each Svg element of the drawing says: its alt text and the text drawn in it.
const svgsOf = async (d: Drawing) =>
  (await d.findAll({ type: 'Svg' })).map(x => {
    const source = String(x.props?.source ?? '')
    const drawn = [...source.replace(/<style>[\s\S]*?<\/style>/, '').matchAll(/>([^<>]+)</g)]
      .map(m => m[1]!.replace(/&quot;/g, '"').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&amp;/g, '&').trim())
      .filter(t => t !== '')
    return { alt: String(x.props?.alt ?? ''), source, drawn }
  })
// Every Text of the drawing, and on the desktop the text drawn inside its Svg elements.
const textsOf = async (d: Drawing) => [
  ...(await d.findAll({ type: 'Text' })).map(t => t.text ?? ''),
  ...(await svgsOf(d)).flatMap(v => v.drawn),
]
// Mounts, reads every Text, unmounts.
const paneTexts = async ($: never, surface: 'terminal' | 'desktop' = 'terminal', cols = 60) => {
  const d = await mount($, PANE, surface, { bodyColumns: cols })
  const t = await textsOf(d)
  await d.unmount()

  return t
}
const bandTexts = async ($: never, surface: 'terminal' | 'desktop' = 'terminal') => {
  const d = await mount($, BAND, surface)
  const t = await textsOf(d)
  await d.unmount()

  return t
}
// Waits (real time) for a drawing to show the text; reads are fire and forget in the plugin.
const untilPane = async ($: never, text: string, cols = 60) => {
  let last: string[] = []
  for (let i = 0; i < 300; i++) {
    last = await paneTexts($, 'terminal', cols)
    if (last.includes(text)) return last
    await new Promise(r => setTimeout(r, 5))
  }
  throw new Error(`pane never showed "${text}"; it showed ${JSON.stringify(last)}`)
}
const until = async (cond: () => boolean, what: string) => {
  for (let i = 0; i < 300; i++) {
    if (cond()) return
    await new Promise(r => setTimeout(r, 5))
  }
  throw new Error(`timed out waiting for ${what}`)
}
const prViews = (w: World) => w.calls.filter(a => isCall(a, 'gh', 'pr', 'view')).length

const eng = ($: never) =>
  $ as unknown as {
    tool: { call: (a: Record<string, unknown>) => Promise<{ result?: unknown; deny?: string }> }
    command: { run: (a: { command: string; args: string }) => Promise<{ text?: string }> }
    session: { start: (a: unknown) => Promise<unknown> }
    agent: { spawn: (a: unknown) => Promise<{ agentId?: string }> }
    turn: { complete: (a: unknown) => Promise<unknown>; step: (a: unknown) => AsyncGenerator<unknown, unknown> }
  }
const startSession = ($: never) => eng($).session.start({ cwd: '/work/r', surface: 'terminal', isInteractive: true })
const bash = (w: World, $: never, command: string, stdout = '', extra: object = {}, stderr = '') => {
  w.bash = stdout
  w.bashErr = stderr

  return eng($).tool.call({ tool: 'Bash', command, ...extra })
}
const follow = async ($: never, args = 'pr 109') => (await eng($).command.run({ command: 'mentat', args })).text
// Follows PR 109 and waits for the first read to land.
const follow109 = async ($: never) => {
  await startSession($)
  await follow($)
  await untilPane($, '#109')
}
// An Agent call with an effort, as the model makes it; resolves with the id the engine gave it.
const callAgent = async (w: World, $: never, effort: string) => {
  await eng($).tool.call({ tool: 'Agent', effort })
  return w.agentCallId
}
const spawn = (n: string, description = 'Check the docs', type = 'general-purpose') =>
  ({ tool_use_id: n, prompt: 'p', description, subagentType: type, provider: { plugin: 'engine', tier: 'core' } })
const turnDone = (agentId: string, usage?: object) =>
  ({ answer: 'ok', durationMs: 1, isAborted: false, turnId: `turn-${agentId}`, agentId, reason: 'end_turn', usage })
// One model request of an agent's loop (or of the main session, without agentId), run to its end.
const step = async ($: never, agentId: string | undefined, effort?: string | number, index = 0) => {
  const input = { turnId: `turn-${agentId ?? 'main'}`, index, model: 'claude-opus-4-8', messageCount: 3, ...(effort === undefined ? {} : { effort }), ...(agentId === undefined ? {} : { agentId }) }
  const stream = eng($).turn.step(input)
  for (;;) if ((await stream.next()).done) return input
}

// ---- decisions (ported from tests/decisions-pane.test.tsx) ----------------------------

test('an opened question shows in the band and pane, and closing it removes it', async ($, on) => {
  const { world } = boot(on)
  void world
  const opened = await eng($).tool.call({ tool: OPEN, question: 'Open the issue?', recommendation: 'yes' })
  expect(String(opened.result)).toContain('d1')

  for (const surface of SURFACES) {
    const band = await bandTexts($, surface)
    // The desktop band shows the one question itself and so leaves out the count.
    if (surface === 'terminal') expect(band).toContain('1 question')
    else expect(band).toContain('Open the issue?')
    const t = await paneTexts($, surface)
    expect(t).toContain('Open the issue?')
    expect(t).toContain('→ yes')
  }

  await eng($).tool.call({ tool: CLOSE, id: 'd1', outcome: 'opened' })
  expect((await bandTexts($)).some(t => t.includes('question'))).toBe(false)
  expect((await paneTexts($)).includes('Open the issue?')).toBe(false)
})

test('settled entries a former decisions pane stored are dropped on load', async ($, on) => {
  boot(on)
  // The kit cannot write a plugin's state from a test, so the load's filter is tried on
  // the shape the old pane stored, and the load itself must leave real questions alone.
  const legacy = [
    { id: 'd1', question: 'Answered already?', openedAt: 1, closedAt: 2, outcome: 'yes' },
    { id: 'd2', question: 'Still open?', openedAt: 3 },
    { id: 'd3', question: 'Dismissed?', openedAt: 4, closedAt: 5, outcome: 'dismissed in the pane' },
  ]
  expect(withoutSettled(legacy).map(d => d.id)).toEqual(['d2'])
  expect(withoutSettled([])).toEqual([])

  await eng($).tool.call({ tool: OPEN, question: 'Open before the load' })
  await startSession($)
  await startSession($)
  expect(await bandTexts($)).toContain('1 question')
  expect(await paneTexts($)).toContain('Open before the load')
})

test('with only questions raising it, the band shows the newest question on the left', async ($, on) => {
  boot(on)
  await eng($).tool.call({ tool: OPEN, question: 'First one?' })
  await eng($).tool.call({ tool: OPEN, question: 'Newest one?' })
  for (const surface of SURFACES) {
    const t = await bandTexts($, surface)
    expect(t).toContain('Newest one?')
    expect(t).not.toContain('First one?')
    expect(t).toContain('2 questions')
    expect(t.some(x => x.includes('Final check'))).toBe(false)
  }
  // The question is cut to fit, not wrapped.
  const d = await mount($, BAND, 'terminal')
  expect((await d.findAll({ type: 'Button' })).map(b => b.key)).toContain('open')
  await d.unmount()
})

test('with a final-checked pull request an open question takes the left of the band, and the pull request returns when it is closed', async ($, on) => {
  const { world } = boot(on)
  world.issueComments = ok(pages([finalCheck(H1)]))
  await follow109($)
  await eng($).tool.call({ tool: OPEN, question: 'A question too?' })
  const t = await bandTexts($)
  expect(t).toContain('A question too?')
  expect(t).toContain('1 question')
  expect(t.some(x => x.includes('Final check'))).toBe(false)
  await eng($).tool.call({ tool: CLOSE, id: 'd1' })
  expect(await bandTexts($)).toContain('· Final check posted')
})

test('on the desktop the band and each card are one drawn Svg, found by alt text; the terminal draws text', async ($, on) => {
  const { world } = boot(on)
  world.issueComments = ok(pages([summary(H1), finalCheck(H1)]))
  world.pullComments = ok(pages([inline(1, H1)]))
  world.prList = ok(JSON.stringify([{ number: 109 }, { number: 7 }]))
  world.usage = { context: 41, limits: [{ kind: 'five_hour', percentUsed: 85, resetsAt: new Date(T0 + 3600_000).toISOString() }] }
  await follow109($)
  // Desktop band with only the final-checked PR: the drawn row and a native Details button.
  const prBand = await mount($, BAND, 'desktop')
  const prBandSvg = await svgsOf(prBand)
  expect(prBandSvg.map(v => v.alt)).toEqual(['#109 final check posted'])
  expect(prBandSvg[0]!.drawn).toEqual(expect.arrayContaining(['#109', 'Label issues by kind', 'Final check posted']))
  expect((await prBand.findAll({ type: 'Button' })).map(b => b.key)).toEqual(['open'])
  await prBand.unmount()
  await eng($).tool.call({ tool: OPEN, question: 'Open it?', recommendation: 'Yes', accept: 'Yes' })
  const id = await callAgent(world, $, 'high')
  world.agents = [{ id, type: 'general-purpose', description: 'Check the docs', status: 'running' }]
  await eng($).agent.spawn(spawn(id))

  // Desktop band with the question open: it is the question that is drawn, alone, with its Details button.
  const band = await mount($, BAND, 'desktop')
  const bandSvg = await svgsOf(band)
  expect(bandSvg.map(v => v.alt)).toEqual(['Question: Open it?'])
  expect(bandSvg[0]!.drawn).toEqual(['?', 'Open it?'])
  expect((await band.findAll({ type: 'Button' })).map(b => b.key)).toEqual(['open'])
  await band.unmount()

  // Desktop pane: the question card and the agents card; no PR card (the app has its own chip) and no usage tiles (its own popover shows those).
  const pane = await mount($, PANE, 'desktop', { bodyColumns: 60 })
  const svgs = await svgsOf(pane)
  const alt = (prefix: string) => svgs.find(v => v.alt.startsWith(prefix))
  expect(svgs.map(v => v.alt)).toEqual([
    'Question: Open it?',
    'Running agents: 1',
  ])
  expect(svgs.flatMap(v => v.drawn).some(x => /context|5-hour|%/i.test(x))).toBe(false)
  expect(alt('Question')!.drawn).toEqual(expect.arrayContaining(['Open it?', '→ Yes']))
  expect(alt('#109')).toBeUndefined()
  expect(alt('Running agents')!.drawn).toEqual(expect.arrayContaining(['Running · 1', 'Check the docs', 'general-purpose', 'Opus 4.8 · high']))
  // The buttons stay native, under the question card.
  expect((await cardKeys(pane))).toEqual(['accept-d1', 'answer-open-d1', 'dismiss-d1'])
  await pane.unmount()

  // The terminal draws no Svg at all, only text.
  const tBand = await mount($, BAND, 'terminal')
  expect((await tBand.findAll({ type: 'Svg' })).length).toBe(0)
  expect(await textsOf(tBand)).toEqual(expect.arrayContaining(['Open it?', '1 question']))
  await tBand.unmount()
  const tPane = await mount($, PANE, 'terminal', { bodyColumns: 60 })
  expect((await tPane.findAll({ type: 'Svg' })).length).toBe(0)
  const t = await textsOf(tPane)
  for (const x of ['Open it?', 'Approval required', '✓', '1 other open PR in this repository', 'Check the docs']) expect(t).toContain(x)
  expect(t.some(x => /[█░]|Context|resets in/.test(x))).toBe(false)
  await tPane.unmount()
})

test('the desktop band hides the question count for a single question and shows it for two', async ($, on) => {
  boot(on)
  await eng($).tool.call({ tool: OPEN, question: 'Only one?' })
  let band = await mount($, BAND, 'desktop')
  let drawn = (await svgsOf(band)).flatMap(v => v.drawn)
  expect(drawn).toContain('Only one?')
  expect(drawn.some(x => x.includes('question'))).toBe(false)
  await band.unmount()

  await eng($).tool.call({ tool: OPEN, question: 'And another?' })
  band = await mount($, BAND, 'desktop')
  drawn = (await svgsOf(band)).flatMap(v => v.drawn)
  expect(drawn).toContain('And another?')
  expect(drawn).toContain('2 questions')
  await band.unmount()
})

test('a new conversation (clear, resume, branch) drops the open questions too; a reload and a compaction keep them', async ($, on) => {
  boot(on)
  const classic = ($ as never as { classic: { SessionStart: (a: { source: string }) => Promise<unknown> } }).classic
  for (const source of ['clear', 'resume', 'fork']) {
    await eng($).tool.call({ tool: OPEN, question: `Asked before ${source}?` })
    await classic.SessionStart({ source })
    expect((await paneTexts($)).some(t => t.includes('Asked before'))).toBe(false)
    expect((await bandTexts($)).some(t => t.includes('question'))).toBe(false)
  }
  await eng($).tool.call({ tool: OPEN, question: 'Kept?' })
  await startSession($)
  await classic.SessionStart({ source: 'startup' })
  await classic.SessionStart({ source: 'compact' })
  expect(await paneTexts($)).toContain('Kept?')
})

test('an answer the conversation did not take raises a toast and can be sent again', async ($, on) => {
  const { world } = boot(on)
  // Once an answer is sent its question takes no other, so each surface has its own.
  for (const [i, surface] of SURFACES.entries()) {
    const id = `d${i + 1}`
    await eng($).tool.call({ tool: OPEN, question: 'Mock it?', recommendation: 'Yes', accept: 'Yes' })
    world.sent.length = 0
    world.toasts.length = 0
    world.dropPrompts = true
    const pane = await mount($, PANE, surface)
    await pane.press({ key: `accept-${id}` })
    expect(world.sent).toEqual([])
    expect(world.toasts.length).toBe(1)
    expect(world.toasts[0]).toContain('Answer not sent')
    expect(world.toasts[0]).toContain('Press again')

    // A typed answer that was not taken keeps its field open.
    await pane.press({ key: `answer-open-${id}` })
    await pane.input({ key: `answer-${id}`, text: 'maybe' })
    expect(world.toasts.length).toBe(2)
    expect((await pane.findAll({ type: 'Input' })).map(x => x.key)).toEqual([`answer-${id}`])

    world.dropPrompts = false
    await pane.press({ key: `accept-${id}` })
    expect(world.sent).toEqual([`Answer to decision ${id} ("Mock it?"): Yes`])
    expect(world.toasts.length).toBe(2)
    // Taken: the question shows it is sent, with no field and no answer buttons.
    expect((await pane.findAll({ type: 'Input' })).length).toBe(0)
    expect((await pane.findAll({ type: 'Button' })).map(x => x.key).filter(k => k?.endsWith(`-${id}`))).toEqual([`dismiss-${id}`])
    expect(await textsOf(pane)).toContain(DELIVERED_LINE)
    await pane.unmount()
  }
})

// A held promise stands for a running turn: the plugin's prompt runs once it is idle.
const held = () => {
  let release: () => void = () => undefined
  const gate = new Promise<void>(r => (release = r))
  return { gate, release }
}
// The ids of the questions marked sent, as last written to state.
const watchSent = (on: never) => {
  let ids: string[] = []
  ;(on as (e: string, ...r: unknown[]) => void)('state.set', async (_$: never, e: { plugin: string; key: string; value: { id: string }[] }, next: (e: unknown) => unknown) => {
    if (e.plugin === 'mentat' && e.key === 'decisionsSent') ids = e.value.map(x => x.id)

    return next(e)
  })

  return async (_$: never): Promise<string[]> => ids
}
// While the submit is pending, and once the prompt has entered the session.
const SENT_LINE = 'Sent: Yes. Claude Code reads it after its current turn.'
const DELIVERED_LINE = 'Sent: Yes.'

test('pressing the accept button again while the turn runs submits nothing more', async ($, on) => {
  const { world } = boot(on)
  const turn = held()
  world.promptGate = turn.gate
  await eng($).tool.call({ tool: OPEN, question: 'Mock it?', recommendation: 'Yes', accept: 'Yes' })
  const pane = await mount($, PANE, 'terminal')
  // A press waits for its handler, which waits for the turn: press three times meanwhile,
  // the last two before the drawing could have changed.
  const presses = [pane.press({ key: 'accept-d1' }), pane.press({ key: 'accept-d1' }), pane.press({ key: 'accept-d1' })]
  await new Promise(r => setTimeout(r, 20))
  turn.release()
  await Promise.all(presses)
  expect(world.sent).toEqual(['Answer to decision d1 ("Mock it?"): Yes'])
  await pane.unmount()
})

test('after a press the question shows it is sent, with only Dismiss left, and the line changes once the answer is in', async ($, on) => {
  const { world } = boot(on)
  for (const [i, surface] of SURFACES.entries()) {
    const id = `d${i + 1}`
    const turn = held()
    world.promptGate = turn.gate
    await eng($).tool.call({ tool: OPEN, question: `Mock it ${id}?`, recommendation: 'Yes', accept: 'Yes' })
    const pane = await mount($, PANE, surface)
    expect((await textsOf(pane)).some(t => t.startsWith('Sent:'))).toBe(false)
    await pane.press({ key: `answer-open-${id}` })
    expect((await pane.findAll({ type: 'Input' })).length).toBe(1)
    const press = pane.press({ key: `accept-${id}` })
    await new Promise(r => setTimeout(r, 20))
    // The press is still waiting for the turn.
    expect(world.sent).toEqual([])
    const shown = await textsOf(pane)
    expect(shown).toContain(SENT_LINE)
    expect(shown.some(t => t.includes(`Mock it ${id}?`))).toBe(true)
    expect(shown.some(t => t.includes('—'))).toBe(false)
    expect((await pane.findAll({ type: 'Button' })).map(x => x.key).filter(k => k?.endsWith(`-${id}`))).toEqual([`dismiss-${id}`])
    expect((await pane.findAll({ type: 'Input' })).length).toBe(0)
    turn.release()
    await press
    // The prompt entered the session: the line no longer says it waits.
    const after = await textsOf(pane)
    expect(after).toContain(DELIVERED_LINE)
    expect(after).not.toContain(SENT_LINE)
    expect((await pane.findAll({ type: 'Button' })).map(x => x.key).filter(k => k?.endsWith(`-${id}`))).toEqual([`dismiss-${id}`])
    await pane.unmount()
    // The mark is in state, so a pane opened again shows it too.
    expect(await paneTexts($, surface)).toContain(DELIVERED_LINE)
    expect(world.sent).toEqual([`Answer to decision ${id} ("Mock it ${id}?"): Yes`])
    world.sent.length = 0
    await eng($).tool.call({ tool: CLOSE, id })
  }
})

test('the answer field marks the question sent too, and a second submit adds nothing', async ($, on) => {
  const { world } = boot(on)
  for (const [i, surface] of SURFACES.entries()) {
    const id = `d${i + 1}`
    const turn = held()
    world.promptGate = turn.gate
    world.sent.length = 0
    await eng($).tool.call({ tool: OPEN, question: 'Keep it?' })
    const pane = await mount($, PANE, surface)
    await pane.press({ key: `answer-open-${id}` })
    const send = pane.input({ key: `answer-${id}`, text: 'yes, for now' })
    const again = pane.input({ key: `answer-${id}`, text: 'yes, for now' }).catch(() => undefined)
    await new Promise(r => setTimeout(r, 20))
    const shown = await textsOf(pane)
    expect(shown).toContain('Sent: yes, for now. Claude Code reads it after its current turn.')
    expect((await pane.findAll({ type: 'Input' })).length).toBe(0)
    expect((await pane.findAll({ type: 'Button' })).map(x => x.key).filter(k => k?.endsWith(`-${id}`))).toEqual([`dismiss-${id}`])
    turn.release()
    await Promise.all([send, again])
    expect(await textsOf(pane)).toContain('Sent: yes, for now.')
    expect(world.sent).toEqual([`Answer to decision ${id} ("Keep it?"): yes, for now`])
    await pane.unmount()
  }
})

test('a submit the conversation drops brings the buttons back', async ($, on) => {
  const { world } = boot(on)
  const sentIds = watchSent(on)
  for (const [i, surface] of SURFACES.entries()) {
    const id = `d${i + 1}`
    const turn = held()
    world.promptGate = turn.gate
    world.dropPrompts = true
    await eng($).tool.call({ tool: OPEN, question: 'Mock it?', recommendation: 'Yes', accept: 'Yes' })
    const pane = await mount($, PANE, surface)
    const press = pane.press({ key: `accept-${id}` })
    await new Promise(r => setTimeout(r, 20))
    expect(await textsOf(pane)).toContain(SENT_LINE)
    expect(await sentIds($)).toEqual([id])
    turn.release()
    await press
    expect((await cardKeys(pane))).toEqual([`accept-${id}`, `answer-open-${id}`, `dismiss-${id}`])
    expect((await textsOf(pane)).some(t => t.startsWith('Sent:'))).toBe(false)
    expect(world.toasts.at(-1)).toContain('Answer not sent')
    expect(await sentIds($)).toEqual([])
    await pane.unmount()
    await eng($).tool.call({ tool: CLOSE, id })
  }
})

test('Dismiss on a sent card removes the question and its sent entry, while the answer waits or after it is in', async ($, on) => {
  const { world } = boot(on)
  const sentIds = watchSent(on)
  for (const [i, surface] of SURFACES.entries()) {
    for (const [j, isPending] of [true, false].entries()) {
      const id = `d${i * 2 + j + 1}`
      const turn = held()
      world.promptGate = turn.gate
      await eng($).tool.call({ tool: OPEN, question: `Clear ${id}?`, accept: 'Yes' })
      const pane = await mount($, PANE, surface)
      const press = pane.press({ key: `accept-${id}` })
      await new Promise(r => setTimeout(r, 20))
      if (!isPending) {
        turn.release()
        await press
      }
      expect(await sentIds($)).toEqual([id])
      await pane.press({ key: `dismiss-${id}` })
      expect(await sentIds($)).toEqual([])
      expect((await textsOf(pane)).some(t => t.includes(`Clear ${id}?`))).toBe(false)
      if (isPending) {
        // The held submit ends later: it must not bring a mark back.
        turn.release()
        await press
        expect(await sentIds($)).toEqual([])
      }
      await pane.unmount()
      expect((await eng($).tool.call({ tool: CLOSE, id })).deny).toContain('No open decision')
    }
  }
})

test('a session start (restart or reload) forgets an answer still waiting for a turn and keeps a delivered one', async ($, on) => {
  const { world } = boot(on)
  const sentIds = watchSent(on)
  await eng($).tool.call({ tool: OPEN, question: 'Delivered?', accept: 'Yes' })
  await eng($).tool.call({ tool: OPEN, question: 'Waiting?', accept: 'Yes' })
  const pane = await mount($, PANE, 'terminal')
  await pane.press({ key: 'accept-d1' })
  // The submit of d2 is lost with the old load: it ends in a rejection, after the restart.
  let lose: () => void = () => undefined
  world.promptGate = new Promise<void>((_, reject) => (lose = () => reject(new Error('the engine reloaded'))))
  const lost = pane.press({ key: 'accept-d2' })
  await new Promise(r => setTimeout(r, 20))
  expect(await sentIds($)).toEqual(['d1', 'd2'])
  expect(await textsOf(pane)).toContain('Sent: Yes. Claude Code reads it after its current turn.')

  await startSession($)
  await new Promise(r => setTimeout(r, 20))
  expect(await sentIds($)).toEqual(['d1'])
  const keys = (await cardKeys(pane))
  expect(keys).toEqual(['dismiss-d1', 'accept-d2', 'answer-open-d2', 'dismiss-d2'])
  expect(await textsOf(pane)).toContain('Sent: Yes.')
  // The waiting one can be answered again.
  world.promptGate = undefined
  await pane.press({ key: 'accept-d2' })
  expect(world.sent).toEqual(['Answer to decision d1 ("Delivered?"): Yes', 'Answer to decision d2 ("Waiting?"): Yes'])
  // The lost submit ends now; it neither throws nor takes back the new, delivered mark.
  lose()
  await lost
  expect(await sentIds($)).toEqual(['d1', 'd2'])
  await pane.unmount()
})

test('a submit the engine rejects is treated like a drop: a toast, and the buttons come back', async ($, on) => {
  const { world } = boot(on)
  const sentIds = watchSent(on)
  await eng($).tool.call({ tool: OPEN, question: 'Mock it?', accept: 'Yes' })
  const pane = await mount($, PANE, 'terminal')
  world.rejectPrompts = true
  await pane.press({ key: 'accept-d1' })
  expect(world.toasts.length).toBe(1)
  expect(world.toasts[0]).toContain('Answer not sent')
  expect(await sentIds($)).toEqual([])
  expect((await cardKeys(pane))).toEqual(['accept-d1', 'answer-open-d1', 'dismiss-d1'])
  world.rejectPrompts = false
  await pane.press({ key: 'accept-d1' })
  expect(world.sent).toEqual(['Answer to decision d1 ("Mock it?"): Yes'])
  await pane.unmount()
})

test('closing a question, or a new conversation, forgets that it was sent', async ($, on) => {
  const { world } = boot(on)
  const sentIds = watchSent(on)
  for (const q of ['One?', 'Two?', 'Three?']) await eng($).tool.call({ tool: OPEN, question: q, accept: 'Yes' })
  const pane = await mount($, PANE, 'terminal')
  for (const id of ['d1', 'd2', 'd3']) await pane.press({ key: `accept-${id}` })
  await pane.unmount()
  expect(world.sent.length).toBe(3)
  expect(await sentIds($)).toEqual(['d1', 'd2', 'd3'])
  await eng($).tool.call({ tool: CLOSE, id: 'd2' })
  expect(await sentIds($)).toEqual(['d1', 'd3'])
  // A sent question has no Dismiss to press; a new conversation drops the questions and their marks.
  const classic = ($ as never as { classic: { SessionStart: (a: { source: string }) => Promise<unknown> } }).classic
  await classic.SessionStart({ source: 'clear' })
  expect(await sentIds($)).toEqual([])
})

test('a question needs text', async ($, on) => {
  boot(on)
  const ran = await eng($).tool.call({ tool: OPEN, question: '   ' })
  expect(ran.deny).toContain('needs a question')
})

test('closing an unknown id is refused', async ($, on) => {
  boot(on)
  const ran = await eng($).tool.call({ tool: CLOSE, id: 'd99' })
  expect(ran.deny).toContain('No open decision')
})

test('typing an answer in the pane sends it to chat as a prompt', async ($, on) => {
  const { world } = boot(on)
  await eng($).tool.call({ tool: OPEN, question: 'Keep it?' })
  await eng($).tool.call({ tool: OPEN, question: 'Keep it?' })

  for (const [i, surface] of SURFACES.entries()) {
    const pane = await mount($, PANE, surface)
    await pane.press({ key: `answer-open-d${i + 1}` })
    await pane.input({ key: `answer-d${i + 1}`, text: 'yes, for now' })
    await pane.unmount()
  }
  expect(world.sent).toEqual([
    'Answer to decision d1 ("Keep it?"): yes, for now',
    'Answer to decision d2 ("Keep it?"): yes, for now',
  ])
})

test('the accept button sends its label as the answer, the same path as typing', async ($, on) => {
  const { world } = boot(on)
  // d1 and d2 for the two surfaces; d3 has no one-press answer.
  await eng($).tool.call({ tool: OPEN, question: 'Mock it?', recommendation: 'Yes', accept: 'Yes' })
  await eng($).tool.call({ tool: OPEN, question: 'Mock it?', recommendation: 'Yes', accept: 'Yes' })
  await eng($).tool.call({ tool: OPEN, question: 'No one-press answer?' })

  for (const [i, surface] of SURFACES.entries()) {
    const pane = await mount($, PANE, surface)
    const buttons = (await cardKeys(pane))
    expect(buttons).toContain(`accept-d${i + 1}`)
    expect(buttons).not.toContain('accept-d3')
    await pane.press({ key: `accept-d${i + 1}` })
    await pane.unmount()
  }
  expect(world.sent).toEqual(['Answer to decision d1 ("Mock it?"): Yes', 'Answer to decision d2 ("Mock it?"): Yes'])
  // Sending an answer does not settle the question: the model closes it.
  expect((await bandTexts($)).includes('3 questions')).toBe(true)
})

test('dismiss settles a question', async ($, on) => {
  boot(on)
  await eng($).tool.call({ tool: OPEN, question: 'Drop it?' })
  const pane = await mount($, PANE, 'terminal')
  await pane.press({ key: 'dismiss-d1' })
  await pane.unmount()
  expect((await paneTexts($)).includes('Drop it?')).toBe(false)
  const again = await eng($).tool.call({ tool: CLOSE, id: 'd1' })
  expect(again.deny).toContain('No open decision')
})

test('two questions opened at once get different ids and both are kept', async ($, on) => {
  boot(on)
  const [a, b] = await Promise.all([
    eng($).tool.call({ tool: OPEN, question: 'First?' }),
    eng($).tool.call({ tool: OPEN, question: 'Second?' }),
  ])
  expect([a, b].map(r => String(r.result)).sort()).toEqual(['Opened decision d1.', 'Opened decision d2.'])
  expect(await bandTexts($)).toContain('2 questions')
})

test('an open question is kept however many come after it', async ($, on) => {
  boot(on)
  for (let i = 1; i <= 60; i++) {
    await eng($).tool.call({ tool: OPEN, question: `Question ${i}?` })
  }
  const closed = await eng($).tool.call({ tool: CLOSE, id: 'd1' })
  expect(String(closed.result)).toBe('Closed decision d1.')
})

test('the band keeps what other plugins draw there, and stays out of a survey', async ($, on) => {
  boot(on, { band: false })
  on('ui.render', ($, e) => {
    const { Text } = $.ui.resolve(e)
    return <Text>another plugin's band</Text>
  })
  await eng($).tool.call({ tool: OPEN, question: 'Keep both?' })

  for (const surface of SURFACES) {
    const shown = await bandTexts($, surface)
    expect(shown).toContain(surface === 'terminal' ? '1 question' : 'Keep both?')
    expect(shown).toContain("another plugin's band")
  }
  const survey = await mount($, BAND, 'terminal', { hasSurvey: true })
  const surveyTexts = await textsOf(survey)
  expect(surveyTexts).not.toContain('1 question')
  expect(surveyTexts).toContain("another plugin's band")
  await survey.unmount()
})

test('the band draws nothing of its own when nothing waits on the maintainer', async ($, on) => {
  boot(on)
  const d = await mount($, BAND, 'terminal')
  expect((await d.findAll({ type: 'Button' })).length).toBe(0)
  await d.unmount()
})

test('Details in the band opens the pane', async ($, on) => {
  const { world } = boot(on)
  await eng($).tool.call({ tool: OPEN, question: 'Open it?' })
  const band = await mount($, BAND, 'terminal')
  await band.press({ key: 'open' })
  await band.unmount()
  expect(world.opened).toContain('mentat')
})

// ---- which pull request is this session's ---------------------------------------------

test('a gh pr create in the main loop names the session\'s pull request by its URL', async ($, on) => {
  const { world } = boot(on)
  await startSession($)
  await bash(world, $, 'gh pr create --fill', `https://github.com/${REPO}/pull/109\n`)
  const t = await untilPane($, '#109')
  expect(t).toContain('Label issues by kind')
  expect(world.calls.some(a => a.join(' ').includes('pr view 109 --repo o/r --json number,title,state,isDraft,headRefOid,reviewDecision,statusCheckRollup,mergeStateStatus,updatedAt'))).toBe(true)
})

test('mentat review <N> takes the repository from the checkout', async ($, on) => {
  const { world } = boot(on)
  await startSession($)
  await bash(world, $, 'mentat review 109', 'The Codex app found nothing\n')
  await untilPane($, '#109')
  expect(world.calls.some(a => isCall(a, 'gh', 'repo', 'view'))).toBe(true)
})

test('mentat review --local <N> names the pull request too, and --repo overrides the checkout', async ($, on) => {
  const { world } = boot(on)
  world.repo = failed
  await startSession($)
  await bash(world, $, 'mentat review --local 109 --repo o/r', '')
  await untilPane($, '#109')
})

test('commands from an agent, failed commands and other commands do not name a pull request', async ($, on) => {
  const { world } = boot(on)
  await startSession($)
  await bash(world, $, 'gh pr create --fill', `https://github.com/${REPO}/pull/109\n`, { agentId: 'sub1' })
  await bash(world, $, 'gh pr create --fill', 'a pull request already exists\n')
  await bash(world, $, 'echo mentat review 109', '')
  await bash(world, $, 'gh pr list', 'https://github.com/o/r/pull/7\n')
  await new Promise(r => setTimeout(r, 30))
  expect(prViews(world)).toBe(0)
  expect((await paneTexts($)).includes('#109')).toBe(false)
})

test('a mentat review call follows its pull request at once, while the review is still running', async ($, on) => {
  const { world } = boot(on)
  world.pr = ok(prJson({ number: 7 }))
  await startSession($)
  let release: () => void = () => undefined
  world.bashGate = new Promise<void>(r => { release = r })
  const call = bash(world, $, 'mentat review 7', 'The Codex app found nothing\n')
  const t = await untilPane($, '#7')
  expect(t).toContain('Label issues by kind')
  expect(world.calls.some(a => isCall(a, 'gh', 'pr', 'view') && a[3] === '7')).toBe(true)
  release()
  await call
})

test('a new conversation (clear, resume, branch) drops the followed pull request; a reload and a compaction keep it', async ($, on) => {
  const { world } = boot(on)
  const classic = ($ as never as { classic: { SessionStart: (a: { source: string }) => Promise<unknown> } }).classic
  for (const source of ['clear', 'resume', 'fork']) {
    await follow109($)
    await classic.SessionStart({ source })
    const t = await paneTexts($)
    expect(t).not.toContain('#109')
    expect(t.some(x => x.includes('o/r#'))).toBe(false)
    expect(t).not.toContain('GitHub')
  }

  await follow109($)
  await startSession($)
  await classic.SessionStart({ source: 'startup' })
  await classic.SessionStart({ source: 'compact' })
  await new Promise(r => setTimeout(r, 30))
  expect(await paneTexts($)).toContain('#109')
  expect(world.calls.length).toBeGreaterThan(0)
})

test('/mentat pr sets the pull request by hand, and says when it cannot', async ($, on) => {
  const { world } = boot(on)
  await startSession($)
  expect(await follow($, 'pr banana')).toContain('Usage')
  expect(await follow($, 'pr 109')).toContain('o/r#109')
  await untilPane($, '#109')
  expect(prViews(world)).toBeGreaterThan(0)
  expect(await follow($, 'pr x/y#7')).toContain('x/y#7')
})

// ---- the GitHub and CI lines ---------------------------------------------------------------

const GITHUB_CASES: [string, Record<string, unknown>, string][] = [
  ['merged', { state: 'MERGED', reviewDecision: 'APPROVED' }, 'Merged'],
  ['closed', { state: 'CLOSED' }, 'Closed'],
  ['draft', { isDraft: true, reviewDecision: 'REVIEW_REQUIRED' }, 'Draft'],
  ['conflicts', { mergeStateStatus: 'DIRTY', reviewDecision: 'CHANGES_REQUESTED' }, 'Conflicts'],
  ['changes requested', { reviewDecision: 'CHANGES_REQUESTED', mergeStateStatus: 'BLOCKED' }, 'Changes requested'],
  ['approved', { reviewDecision: 'APPROVED', mergeStateStatus: 'CLEAN' }, 'Approved'],
  ['approval required', { reviewDecision: 'REVIEW_REQUIRED' }, 'Approval required'],
  ['blocked with no review rule', { reviewDecision: null, mergeStateStatus: 'BEHIND' }, 'Merge blocked · behind'],
  ['mergeable with no review rule', { reviewDecision: '', mergeStateStatus: 'CLEAN' }, 'Mergeable'],
]
for (const [name, fields, label] of GITHUB_CASES) {
  test(`the GitHub line says ${name}`, async ($, on) => {
    const { world } = boot(on)
    world.pr = ok(prJson(fields))
    await follow109($)
    expect(await paneTexts($)).toContain(label)
  })
}

const CI_CASES: [string, unknown[] | null, string][] = [
  ['none without checks', [], 'none'],
  ['none when GitHub gives null', null, 'none'],
  ['a tick when everything passed', [CHECK_OK, { __typename: 'StatusContext', state: 'SUCCESS' }, { __typename: 'CheckRun', status: 'COMPLETED', conclusion: 'SKIPPED' }], '✓'],
  ['running while a check runs', [CHECK_OK, { __typename: 'CheckRun', status: 'IN_PROGRESS', conclusion: null }], 'running'],
  ['running for a pending status', [{ __typename: 'StatusContext', state: 'PENDING' }], 'running'],
  ['the failed count first', [{ __typename: 'CheckRun', status: 'COMPLETED', conclusion: 'FAILURE' }, { __typename: 'StatusContext', state: 'ERROR' }, { __typename: 'CheckRun', status: 'IN_PROGRESS', conclusion: null }, CHECK_OK], '✕ 2 failed'],
  ['cancelled as failed', [{ __typename: 'CheckRun', status: 'COMPLETED', conclusion: 'CANCELLED' }], '✕ 1 failed'],
]
for (const [name, rollup, label] of CI_CASES) {
  test(`the CI line says ${name}`, async ($, on) => {
    const { world } = boot(on)
    world.pr = ok(prJson({ statusCheckRollup: rollup }))
    await follow109($)
    expect(await paneTexts($)).toContain(label)
  })
}

// ---- the Codex line ----------------------------------------------------------------------------

const codexLine = async ($: never) => {
  const t = await untilPane($, 'Codex')
  const i = t.indexOf('Codex')

  return t[i + 1]
}

test('Codex: completed on the head, findings and the ones the agent replied to', async ($, on) => {
  const { world } = boot(on)
  world.issueComments = ok(pages([summary(H1)]))
  world.pullComments = ok(pages([
    inline(1, H1),
    inline(2, H1),
    inline(3, H1, CODEX, 1),
    inline(4, H1, ME, 1),
    inline(5, H1, ME, 1),
    inline(6, H1, 'someone-else', 2),
  ]))
  await follow109($)
  // Two findings; one has a reply from the agent account (two replies count once);
  // a reply from someone else and the app's own reply do not count.
  expect(await codexLine($)).toBe('2 findings · 1 replied · 415e6d9')
})

test('Codex: one finding is singular, none is said plainly, and an older commit\'s findings are not counted', async ($, on) => {
  const { world } = boot(on)
  world.issueComments = ok(pages([summary(H1)]))
  world.pullComments = ok(pages([inline(1, H1), inline(2, H2)]))
  await follow109($)
  expect(await codexLine($)).toBe('1 finding · 0 replied · 415e6d9')

  world.pullComments = ok(pages([inline(2, H2)]))
  await bash(world, $, 'git push', '')
  await until(() => prViews(world) >= 2, 'a second read')
  for (let i = 0; i < 200 && (await codexLine($)) !== 'No findings · 415e6d9'; i++) await new Promise(r => setTimeout(r, 5))
  expect(await codexLine($)).toBe('No findings · 415e6d9')
})

test('Codex: running on the head, failed, and a summary about another commit', async ($, on) => {
  const { world } = boot(on)
  world.issueComments = ok(pages([summary(H1, 'In progress')]))
  await follow109($)
  expect(await codexLine($)).toBe('Running · 415e6d9')

  world.issueComments = ok(pages([summary(H1, 'Failed')]))
  await bash(world, $, 'mentat review 109', '')
  for (let i = 0; i < 200 && (await codexLine($)) !== 'Failed · 415e6d9'; i++) await new Promise(r => setTimeout(r, 5))
  expect(await codexLine($)).toBe('Failed · 415e6d9')

  world.issueComments = ok(pages([summary(H2, 'Completed')]))
  await bash(world, $, 'mentat review 109', '')
  for (let i = 0; i < 200 && (await codexLine($)) !== 'Not on this commit'; i++) await new Promise(r => setTimeout(r, 5))
  expect(await codexLine($)).toBe('Not on this commit')
})

test('Codex: a summary in a format it does not know is unknown, and so is a status it does not know', async ($, on) => {
  const { world } = boot(on)
  world.issueComments = ok(pages([comment(CODEX, '<!-- codex-pull-request-review-summary -->\nsomething else')]))
  world.pullComments = ok(pages([inline(1, H1)]))
  await follow109($)
  expect(await codexLine($)).toBe('unknown')

  world.issueComments = ok(pages([summary(H1, 'Pondering')]))
  await bash(world, $, 'mentat review 109', '')
  await new Promise(r => setTimeout(r, 50))
  expect(await codexLine($)).toBe('unknown')
})

test('Codex: a summary from someone else is not the app\'s, and a missing one says so', async ($, on) => {
  const { world } = boot(on)
  world.issueComments = ok(pages([summary(H1, 'Completed', 'someone')]))
  await follow109($)
  expect(await codexLine($)).toBe('No review yet')
})

test('Codex: a local review shows as posted with its result line, not counted', async ($, on) => {
  const { world } = boot(on)
  world.issueComments = ok(pages([localReview(H1, 'FINDINGS')]))
  world.pullComments = ok(pages([inline(1, H1)]))
  await follow109($)
  expect(await codexLine($)).toBe('Local review posted · Findings · 415e6d9')

  world.issueComments = ok(pages([localReview(H1, 'NO FINDINGS')]))
  await bash(world, $, 'mentat review --local 109', '')
  for (let i = 0; i < 200 && (await codexLine($)) !== 'Local review posted · No findings · 415e6d9'; i++) await new Promise(r => setTimeout(r, 5))
  expect(await codexLine($)).toBe('Local review posted · No findings · 415e6d9')
})

test('Codex: a same-head local review shows over an app summary that is running or failed, not over a completed one', async ($, on) => {
  const { world } = boot(on)
  world.issueComments = ok(pages([summary(H1, 'Failed'), localReview(H1, 'NO FINDINGS')]))
  await follow109($)
  expect(await codexLine($)).toBe('Local review posted · No findings · 415e6d9')

  world.issueComments = ok(pages([summary(H1, 'In progress'), localReview(H1, 'FINDINGS')]))
  await bash(world, $, 'mentat review --local 109', '')
  for (let i = 0; i < 200 && (await codexLine($)) !== 'Local review posted · Findings · 415e6d9'; i++) await new Promise(r => setTimeout(r, 5))
  expect(await codexLine($)).toBe('Local review posted · Findings · 415e6d9')

  // A local review of another commit does not displace Running; a completed app result wins.
  world.issueComments = ok(pages([summary(H1, 'In progress'), localReview(H2)]))
  await bash(world, $, 'mentat review 109', '')
  for (let i = 0; i < 200 && (await codexLine($)) !== 'Running · 415e6d9'; i++) await new Promise(r => setTimeout(r, 5))
  expect(await codexLine($)).toBe('Running · 415e6d9')
  world.issueComments = ok(pages([summary(H1, 'Completed'), localReview(H1, 'FINDINGS')]))
  await bash(world, $, 'mentat review 109', '')
  for (let i = 0; i < 200 && (await codexLine($)) !== 'No findings · 415e6d9'; i++) await new Promise(r => setTimeout(r, 5))
  expect(await codexLine($)).toBe('No findings · 415e6d9')
})

test('Codex: a local review of another commit, or by someone else, is not shown', async ($, on) => {
  const { world } = boot(on)
  world.issueComments = ok(pages([localReview(H2), localReview(H1, 'NO FINDINGS', 'someone')]))
  await follow109($)
  expect(await codexLine($)).toBe('No review yet')
})

test('Codex: a review on the head with no inline comment is findings without a count, never No findings', async ($, on) => {
  const { world } = boot(on)
  world.issueComments = ok(pages([summary(H1)]))
  world.reviews = ok(pages([reviewOf(H1)]))
  await follow109($)
  expect(await codexLine($)).toBe('Findings in review · 415e6d9')

  // Inline comments, when there are some, keep their count.
  world.pullComments = ok(pages([inline(1, H1)]))
  await bash(world, $, 'mentat review 109', '')
  for (let i = 0; i < 200 && (await codexLine($)) !== '1 finding · 0 replied · 415e6d9'; i++) await new Promise(r => setTimeout(r, 5))
  expect(await codexLine($)).toBe('1 finding · 0 replied · 415e6d9')
})

test('Codex: a review on an older commit, or by someone else, is not findings', async ($, on) => {
  const { world } = boot(on)
  world.issueComments = ok(pages([summary(H1)]))
  world.reviews = ok(pages([reviewOf(H2), reviewOf(H1, 'someone-else')]))
  await follow109($)
  expect(await codexLine($)).toBe('No findings · 415e6d9')
})

test('a failed read of the reviews is a failed review read, not No findings', async ($, on) => {
  const { world } = boot(on)
  world.issueComments = ok(pages([summary(H1)]))
  world.reviews = failed
  await follow109($)
  const t = await untilPane($, 'Review read failed')
  expect(t[t.indexOf('Codex') + 1]).toBe('unknown')
  expect(t).not.toContain('No findings · 415e6d9')
})

test('review comments are read across pages', async ($, on) => {
  const { world } = boot(on)
  world.issueComments = ok(pages([comment('a', 'x', 1)], [summary(H1)]))
  world.pullComments = ok(pages([inline(1, H1)], [inline(2, H1)], [inline(3, H1, ME, 2)]))
  world.reviews = ok(pages([reviewOf(H2)], [reviewOf(H2)]))
  await follow109($)
  expect(await codexLine($)).toBe('2 findings · 1 replied · 415e6d9')
  expect(world.calls.filter(a => isCall(a, 'gh', 'api')).every(a => a.includes('--paginate') || a[2] === 'user')).toBe(true)
})

test('a head change discards the review data of the old head', async ($, on) => {
  const { world } = boot(on)
  world.issueComments = ok(pages([summary(H1), finalCheck(H1)]))
  world.pullComments = ok(pages([inline(1, H1)]))
  await follow109($)
  expect(await codexLine($)).toBe('1 finding · 0 replied · 415e6d9')
  expect(await bandTexts($)).toContain('· Final check posted')

  // The branch moved; the review reads of the new head cannot be read yet.
  world.pr = ok(prJson({ headRefOid: H2 }))
  world.issueComments = failed
  await bash(world, $, 'git push', '')
  await until(() => world.calls.filter(a => a.join(' ').includes('/issues/109/comments')).length >= 2, 'the second review read')
  for (let i = 0; i < 200 && (await codexLine($)) !== 'unknown'; i++) await new Promise(r => setTimeout(r, 5))
  expect(await codexLine($)).toBe('unknown')
  expect((await bandTexts($)).some(t => t.includes('Final check'))).toBe(false)
})

// ---- the final check and the band ------------------------------------------------------------------

test('the band is raised by a final check on the current head, in short labels', async ($, on) => {
  const { world } = boot(on)
  world.issueComments = ok(pages([summary(H1), finalCheck(H1)]))
  await follow109($)
  for (const surface of SURFACES) {
    const t = await bandTexts($, surface)
    expect(t).toContain('#109')
    expect(t).toContain('Label issues by kind')
    expect(t).toContain(surface === 'terminal' ? '· Final check posted' : 'Final check posted')
  }
})

test('a final check on another commit, by someone else, or on a merged pull request does not raise the band', async ($, on) => {
  const { world } = boot(on)
  world.issueComments = ok(pages([finalCheck(H2), comment('someone', `Final check on ${H1.slice(0, 7)}`, 7), comment(ME, `The final check on ${H1.slice(0, 7)} is below`, 8)]))
  await follow109($)
  expect((await bandTexts($)).some(t => t.includes('Final check'))).toBe(false)

  world.issueComments = ok(pages([finalCheck(H1)]))
  world.pr = ok(prJson({ state: 'MERGED' }))
  await bash(world, $, 'gh pr merge 109', '')
  for (let i = 0; i < 200 && !(await paneTexts($)).includes('Merged'); i++) await new Promise(r => setTimeout(r, 5))
  expect((await bandTexts($)).some(t => t.includes('Final check'))).toBe(false)
})

test('the final check may name the head by a short or the full SHA', async ($, on) => {
  const { world } = boot(on)
  world.issueComments = ok(pages([comment(ME, `Final check on ${H1}\n\nAll good.`, 3)]))
  await follow109($)
  expect(await bandTexts($)).toContain('· Final check posted')
})

test('with a final check and two questions the band shows the newest question and the count, and the desktop pane has no pull request card', async ($, on) => {
  const { world } = boot(on)
  world.issueComments = ok(pages([finalCheck(H1)]))
  await follow109($)
  await eng($).tool.call({ tool: OPEN, question: 'One?' })
  await eng($).tool.call({ tool: OPEN, question: 'Two?' })
  const t = await bandTexts($)
  expect(t).toContain('2 questions')
  expect(t).toContain('Two?')
  expect(t.some(x => x.includes('Final check'))).toBe(false)
  const d = await mount($, PANE, 'desktop', { bodyColumns: 60 })
  // The pane has no pull request card on the desktop; the final check stays with the band.
  expect((await svgsOf(d)).some(v => v.alt.startsWith('#109'))).toBe(false)
  await d.unmount()
})

test('a failed read of the pull request takes the final check off the band; a later good read puts it back', async ($, on) => {
  const { world, clock } = boot(on)
  world.issueComments = ok(pages([finalCheck(H1)]))
  await follow109($)
  expect(await bandTexts($)).toContain('· Final check posted')

  // The branch may have moved; the read that would show it failed.
  world.pr = failed
  await clock.advance(60_000)
  await untilPane($, 'PR read failed (last ok 1m ago)')
  let t = await bandTexts($)
  expect(t.some(x => x.includes('Final check'))).toBe(false)
  expect(await paneTexts($)).toContain('Approval required')
  // Questions still raise the band; the band shows the question, not the final check.
  await eng($).tool.call({ tool: OPEN, question: 'Still asked?' })
  t = await bandTexts($)
  expect(t).toContain('Still asked?')
  expect(t).toContain('1 question')
  await eng($).tool.call({ tool: CLOSE, id: 'd1' })

  world.pr = ok(prJson())
  await clock.advance(60_000)
  for (let i = 0; i < 300 && !(await bandTexts($)).includes('· Final check posted'); i++) await new Promise(r => setTimeout(r, 5))
  t = await bandTexts($)
  expect(t).toContain('· Final check posted')
})

test('a failed read of the review sources takes the final check off the band too', async ($, on) => {
  const { world, clock } = boot(on)
  world.issueComments = ok(pages([finalCheck(H1)]))
  await follow109($)
  expect(await bandTexts($)).toContain('· Final check posted')
  world.pullComments = failed
  await clock.advance(60_000)
  await untilPane($, 'Review read failed (last ok 1m ago)')
  expect((await bandTexts($)).some(x => x.includes('Final check'))).toBe(false)
})

test('a read older than five minutes does not raise the band', async ($, on) => {
  const { world, clock } = boot(on)
  world.issueComments = ok(pages([finalCheck(H1)]))
  await follow109($)
  expect(await bandTexts($)).toContain('· Final check posted')

  // Reads hang: nothing failed, but nothing newer arrives either.
  world.pr = () => new Promise<Run>(() => undefined)
  await clock.advance(4 * 60_000)
  await until(() => prViews(world) >= 2, 'a read to hang')
  expect(await bandTexts($)).toContain('· Final check posted')
  await clock.advance(2 * 60_000)
  expect((await bandTexts($)).some(x => x.includes('Final check'))).toBe(false)
  expect((await paneTexts($)).some(x => x.startsWith('PR read 6m old'))).toBe(true)
})

// ---- other open pull requests, freshness, failed reads ------------------------------------------------

test('other open pull requests are counted without this one, singular and plural', async ($, on) => {
  const { world } = boot(on)
  world.prList = ok(JSON.stringify([{ number: 109 }, { number: 7 }]))
  await follow109($)
  await untilPane($, '1 other open PR in this repository')

  world.prList = ok(JSON.stringify([{ number: 109 }, { number: 7 }, { number: 8 }]))
  await bash(world, $, 'gh pr ready 109', '')
  await untilPane($, '2 other open PRs in this repository')
})

test('other open pull requests say 100+ when the list hit its limit', async ($, on) => {
  const { world } = boot(on)
  world.prList = ok(JSON.stringify(Array.from({ length: 100 }, (_, i) => ({ number: i + 1 }))))
  await follow109($)
  await untilPane($, '100+ other open PRs in this repository')
  expect(world.calls.some(a => isCall(a, 'gh', 'pr', 'list') && a.includes('--limit') && a.includes('100') && a.includes('open'))).toBe(true)
})

// ---- the desktop pane has no pull request card (the app has its own chip); the terminal card stays ----------------

// The terminal pane's texts; the desktop pane's pull request Svgs (none are expected).
const cardOf = async ($: never) => {
  const pane = await mount($, PANE, 'terminal', { bodyColumns: 60 })
  const drawn = await textsOf(pane)
  await pane.unmount()

  return drawn
}
const untilCard = async ($: never, cond: (t: string[]) => boolean, what: string) => {
  let last: string[] = []
  for (let i = 0; i < 300; i++) {
    last = await cardOf($)
    if (cond(last)) return last
    await new Promise(r => setTimeout(r, 5))
  }
  throw new Error(`card never showed ${what}; it showed ${JSON.stringify(last)}`)
}
// Every Svg alt and drawn text of the desktop pane.
const desktopPane = async ($: never) => {
  const pane = await mount($, PANE, 'desktop', { bodyColumns: 60 })
  const svgs = await svgsOf(pane)
  const texts = await textsOf(pane)
  await pane.unmount()

  return { alts: svgs.map(v => v.alt), texts }
}

test('terminal card: CI shows always; the desktop pane draws no pull request card or CI line', async ($, on) => {
  const { world } = boot(on)
  await follow109($)
  await untilCard($, t => t.includes('Approval required'), 'the card')
  for (const [rollup, terminal] of [[[CHECK_OK], '✓'], [[CHECK_OK, { __typename: 'CheckRun', status: 'IN_PROGRESS', conclusion: null }], 'running'], [[], 'none']] as [unknown[], string][]) {
    world.pr = ok(prJson({ statusCheckRollup: rollup }))
    await bash(world, $, 'gh pr ready 109', '')
    await untilCard($, t => t.includes(terminal), `CI ${terminal}`)
    const d = await desktopPane($)
    expect(d.alts.some(a => a.startsWith('#109'))).toBe(false)
    expect(d.texts.some(t => t.startsWith('CI') || t === 'No CI' || t === 'running' || t === 'Approval required')).toBe(false)
  }

  world.pr = ok(prJson({ statusCheckRollup: [{ __typename: 'CheckRun', status: 'COMPLETED', conclusion: 'FAILURE' }, CHECK_OK] }))
  await bash(world, $, 'gh pr ready 109', '')
  expect(await untilCard($, t => t.includes('✕ 1 failed'), 'the terminal CI')).toContain('CI')
  expect((await desktopPane($)).texts.some(t => t.startsWith('CI'))).toBe(false)
})

test('the desktop pane draws no pull request card while the band still raises a final-checked pull request', async ($, on) => {
  const { world } = boot(on)
  world.issueComments = ok(pages([summary(H1), finalCheck(H1)]))
  await follow109($)
  await untilCard($, t => t.includes('Approval required'), 'the card')
  const pane = await desktopPane($)
  expect(pane.alts).toEqual([])
  expect(pane.texts.some(t => t.includes('Label issues by kind') || t.includes('Codex') || t.includes('Final check'))).toBe(false)
  // The band reads the same pull request and still raises it, on the desktop.
  const band = await mount($, BAND, 'desktop')
  const bandSvg = await svgsOf(band)
  expect(bandSvg.map(v => v.alt)).toEqual(['#109 final check posted'])
  await band.unmount()
  // The terminal card keeps its lines; the final check is the band's business there.
  const t = await cardOf($)
  expect(t).toContain('Label issues by kind')
  expect(t).toContain('Codex')
  expect(t.some(x => x.includes('Final check posted ·'))).toBe(false)
})

test('terminal card: other open pull requests and freshness stay; the desktop pane says neither', async ($, on) => {
  const { world, clock } = boot(on)
  world.prList = ok(JSON.stringify([{ number: 109 }, { number: 7 }, { number: 8 }]))
  await follow109($)
  await untilPane($, '2 other open PRs in this repository')
  expect((await desktopPane($)).texts.some(t => t.includes('other open'))).toBe(false)

  world.pr = failed
  await clock.advance(60_000)
  await untilCard($, x => x.includes('PR read failed (last ok 1m ago)'), 'the freshness line')
  expect((await desktopPane($)).texts.some(t => t.includes('read failed'))).toBe(false)
})

test('on the desktop a followed pull request whose first read failed draws no pull request line: the pane says nothing waits', async ($, on) => {
  const { world } = boot(on)
  world.pr = failed
  await startSession($)
  await follow($)
  await untilPane($, 'PR read failed', 60)
  const desktop = await mount($, PANE, 'desktop', { bodyColumns: 60 })
  expect(await textsOf(desktop)).toEqual(['Nothing waiting on you.'])
  await desktop.unmount()
})

test('a failed first read shows the pull request as named and says the read failed', async ($, on) => {
  const { world } = boot(on)
  world.pr = failed
  await startSession($)
  await follow($)
  const t = await untilPane($, 'PR read failed')
  expect(t).toContain('o/r#109')
  expect(t.includes('Approval required')).toBe(false)
})

test('a failed read keeps the last good facts and says how old they are, only once old or failed', async ($, on) => {
  const { world, clock } = boot(on)
  await follow109($)
  expect((await paneTexts($)).some(t => t.startsWith('PR read'))).toBe(false)
  expect((await paneTexts($)).some(t => t.startsWith('Review read'))).toBe(false)

  world.pr = failed
  world.issueComments = failed
  await clock.advance(60_000)
  await untilPane($, 'PR read failed (last ok 1m ago)')
  const t = await paneTexts($)
  expect(t).toContain('Approval required')
  // The review reads depend on the head, which could not be read: they were not tried.
  expect(t.some(x => x.startsWith('Review read'))).toBe(false)

  world.pr = ok(prJson())
  await clock.advance(60_000)
  await until(() => world.calls.filter(a => a.join(' ').includes('/issues/109/comments')).length >= 2, 'a review read')
  await untilPane($, 'Review read failed (last ok 2m ago)')
})

test('a failed read of the agent account is named, not called a review failure', async ($, on) => {
  const { world } = boot(on)
  world.me = failed
  await follow109($)
  const t = await untilPane($, 'GitHub user read failed')
  expect(t).not.toContain('Review read failed')
  // The comments cannot be attributed, so Codex is unknown; the pull request's own facts stand.
  expect(t).toContain('Approval required')
  expect(t[t.indexOf('Codex') + 1]).toBe('unknown')
  expect(world.calls.some(a => a.join(' ').includes('/issues/109/comments'))).toBe(false)

  // Once the account can be read, the line goes and the review is read.
  world.me = ok(`${ME}\n`)
  world.issueComments = ok(pages([summary(H1)]))
  await bash(world, $, 'git push', '')
  for (let i = 0; i < 300 && (await paneTexts($)).includes('GitHub user read failed'); i++) await new Promise(r => setTimeout(r, 5))
  const after = await paneTexts($)
  expect(after).not.toContain('GitHub user read failed')
  expect(after[after.indexOf('Codex') + 1]).toBe('No findings · 415e6d9')
})

test('data older than five minutes is marked old', async ($, on) => {
  const { world, clock } = boot(on)
  await follow109($)
  world.pr = { exitCode: 1, stdout: '' }
  await clock.advance(6 * 60_000)
  const t = await untilPane($, 'PR read failed (last ok 6m ago)')
  expect(t).toContain('Approval required')
})

test('a read that cannot be parsed is a failed read', async ($, on) => {
  const { world } = boot(on)
  world.pr = ok('not json')
  await startSession($)
  await follow($)
  await untilPane($, 'PR read failed')
})

// ---- the refresh contract -----------------------------------------------------------------------------

test('the first read runs at once, then every 60 seconds and right after gh pr, git push and mentat review', async ($, on) => {
  const { world, clock } = boot(on)
  await follow109($)
  const n = () => prViews(world)
  const first = n()
  await clock.advance(60_000)
  await until(() => n() > first, 'the 60 s read')
  const second = n()
  for (const cmd of ['gh pr ready 109', 'git push origin HEAD', 'mentat review --local 109']) {
    const before = n()
    await bash(world, $, cmd, '')
    await until(() => n() > before, `a read after ${cmd}`)
  }
  const afterAll = n()
  await bash(world, $, 'ls', '')
  await bash(world, $, 'git status', '', {})
  await bash(world, $, 'gh pr view 109', '', { agentId: 'sub1' })
  await new Promise(r => setTimeout(r, 30))
  expect(n()).toBe(afterAll)
  expect(second).toBeGreaterThan(first)
})

test('one read at a time: a request while one runs is folded into one more read', async ($, on) => {
  const { world } = boot(on)
  await follow109($)
  let release: (r: Run) => void = () => undefined
  const gate = new Promise<Run>(r => { release = r })
  const before = prViews(world)
  world.pr = () => gate
  await bash(world, $, 'git push', '')
  await until(() => prViews(world) === before + 1, 'a read to start')
  await bash(world, $, 'git push', '')
  await bash(world, $, 'gh pr ready', '')
  await bash(world, $, 'mentat review 109', '')
  await new Promise(r => setTimeout(r, 30))
  expect(prViews(world)).toBe(before + 1)
  world.pr = ok(prJson({ title: 'chore: second' }))
  release(ok(prJson({ title: 'chore: first' })))
  await untilPane($, 'Second')
  expect(prViews(world)).toBe(before + 2)
  expect(world.peak).toBeLessThanOrEqual(3)
})

test('two reads finishing in reverse order: the older result is dropped', async ($, on) => {
  const { world } = boot(on)
  await startSession($)
  await follow($)
  await untilPane($, '#109')

  // A read starts and hangs; the mod restarts (a reload raises session.start again)
  // and its newer read finishes first. The old read then finishes with old data.
  let releaseOld: (r: Run) => void = () => undefined
  world.pr = () => new Promise<Run>(r => { releaseOld = r })
  await bash(world, $, 'git push', '')
  await until(() => prViews(world) >= 2, 'the old read to start')

  world.pr = ok(prJson({ title: 'chore: newer', headRefOid: H2 }))
  world.issueComments = ok(pages([summary(H2)]))
  await startSession($)
  await untilPane($, 'Newer')

  releaseOld(ok(prJson({ title: 'chore: older' })))
  await new Promise(r => setTimeout(r, 50))
  const t = await paneTexts($)
  expect(t).toContain('Newer')
  expect(t).not.toContain('Older')
})

test('a result for a pull request that is no longer followed is dropped', async ($, on) => {
  const { world } = boot(on)
  await startSession($)
  let release: (r: Run) => void = () => undefined
  world.pr = () => new Promise<Run>(r => { release = r })
  await follow($, 'pr 109')
  await until(() => prViews(world) >= 1, 'the read to start')
  // Nothing newer for #7 can be read, so only the old result could put 109's facts there.
  world.pr = failed
  await follow($, 'pr o/r#7')
  release(ok(prJson({ title: 'chore: stale 109' })))
  await untilPane($, 'PR read failed')
  const t = await paneTexts($)
  expect(t).toContain('o/r#7')
  expect(t).not.toContain('Stale 109')
})

// ---- agents ----------------------------------------------------------------------------------------------

// Waits for the agents' row to show the fact, on the surface.
const untilFacts = async ($: never, surface: 'terminal' | 'desktop', description: string, fact: string) => {
  let last: string[] = []
  for (let i = 0; i < 300; i++) {
    last = await paneTexts($, surface)
    if (last.some(x => x.includes(fact)) && last.includes(description)) return last
    await new Promise(r => setTimeout(r, 5))
  }
  throw new Error(`the ${surface} pane never showed "${fact}"; it showed ${JSON.stringify(last)}`)
}

// The facts line of a terminal row: the text after the description, past the status mark at the end of its line.
const MARKS = ['●', '✓', '✕', '○']
const rowFor = (t: string[], description: string) => {
  const i = t.indexOf(description)
  if (i === -1) return undefined

  return MARKS.includes(t[i + 1]!) ? t[i + 2] : t[i + 1]
}

test('an agent shows its description, type, model, effort, status and elapsed time; elapsed freezes when it ends', async ($, on) => {
  const { world, clock } = boot(on)
  await startSession($)
  const id = await callAgent(world, $, 'high')
  world.agents = [{ id, type: 'general-purpose', description: 'Check the docs', status: 'running' }]
  await eng($).agent.spawn(spawn(id))
  await clock.advance(65_000)
  await new Promise(r => setTimeout(r, 30))
  expect(rowFor(await paneTexts($), 'Check the docs')).toBe('general-purpose · Opus 4.8 · high · running · 1m 05s')

  world.agents = [{ id, type: 'general-purpose', description: 'Check the docs', status: 'completed' }]
  await clock.advance(1_000)
  await new Promise(r => setTimeout(r, 30))
  expect(rowFor(await paneTexts($), 'Check the docs')).toBe('general-purpose · Opus 4.8 · high · completed · 1m 06s')
  await clock.advance(120_000)
  await new Promise(r => setTimeout(r, 30))
  expect(rowFor(await paneTexts($), 'Check the docs')).toBe('general-purpose · Opus 4.8 · high · completed · 1m 06s')
})

test('a turn that completes is not the end of a waiting agent; tokens are those last reported', async ($, on) => {
  const { world, clock } = boot(on)
  await startSession($)
  world.agents = [{ id: 'a1', type: 'Explore', description: 'Look around', status: 'waiting' }]
  await eng($).agent.spawn(spawn('a1', 'Look around', 'Explore'))
  await eng($).turn.complete(turnDone('a1', { input_tokens: 100, cache_creation_input_tokens: 400, output_tokens: 500, cache_read_input_tokens: 99999, model: 'm' }))
  await clock.advance(10_000)
  expect(rowFor(await paneTexts($), 'Look around')).toBe('Explore · Opus 4.8 · waiting · 10s · 1.0k reported')

  await eng($).turn.complete(turnDone('a1', { input_tokens: 1, cache_creation_input_tokens: 2, output_tokens: 12000, cache_read_input_tokens: 0, model: 'm' }))
  await clock.advance(114_000)
  expect(rowFor(await paneTexts($), 'Look around')).toBe('Explore · Opus 4.8 · waiting · 2m 04s · 12k reported')
})

test('every agent status is shown as it is, running and waiting first', async ($, on) => {
  const { world, clock } = boot(on)
  await startSession($)
  const statuses = ['completed', 'failed', 'killed', 'idle', 'waiting', 'running']
  world.agents = statuses.map(s => ({ id: s, type: 'general-purpose', description: `Agent ${s}`, status: s }))
  for (const s of statuses) await eng($).agent.spawn(spawn(s, `Agent ${s}`))
  // The next check of the engine's list (once a second) brings the statuses in.
  await clock.advance(1_000)
  await new Promise(r => setTimeout(r, 30))
  const t = await paneTexts($)
  const order = t.filter(x => x.startsWith('Agent '))
  expect(order.slice(0, 2).sort()).toEqual(['Agent running', 'Agent waiting'])
  for (const s of statuses) expect(rowFor(t, `Agent ${s}`)).toContain(` · ${s} · `)
})

test('after a reload the mod keeps what it knew, shows unknown agents without a model or elapsed time, and notices ends', async ($, on) => {
  const { world, clock } = boot(on)
  await startSession($)
  world.agents = [{ id: 'a1', type: 'general-purpose', description: 'Known one', status: 'running' }]
  await eng($).agent.spawn(spawn('a1', 'Known one'))
  await clock.advance(30_000)

  // The reload: the engine lists a1 as ended, and an agent this mod never saw.
  world.agents = [
    { id: 'a1', type: 'general-purpose', description: 'Known one', status: 'completed' },
    { id: 'z9', type: 'Explore', description: 'Unseen one', status: 'running' },
  ]
  await startSession($)
  await new Promise(r => setTimeout(r, 30))
  const t = await paneTexts($)
  expect(rowFor(t, 'Known one')).toBe('general-purpose · Opus 4.8 · completed · 30s')
  expect(rowFor(t, 'Unseen one')).toBe('Explore · running')
})

test('an agent that vanishes from the engine\'s list is shown as ended, not as finished', async ($, on) => {
  const { world, clock } = boot(on)
  await startSession($)
  world.agents = [{ id: 'a1', type: 'general-purpose', description: 'Gone one', status: 'running' }]
  await eng($).agent.spawn(spawn('a1', 'Gone one'))
  await clock.advance(4_000)
  world.agents = []
  await clock.advance(1_000)
  await new Promise(r => setTimeout(r, 30))
  expect(rowFor(await paneTexts($), 'Gone one')).toBe('general-purpose · Opus 4.8 · ended · 5s')
})

// ---- the effort of each agent, and finished agents dimmed ---------------------------------------------------

test('a subagent\'s requests set the effort of its row on both surfaces; the Agent call\'s effort shows until then', async ($, on) => {
  const { world } = boot(on)
  await startSession($)
  const id = await callAgent(world, $, 'low')
  world.agents = [{ id, type: 'general-purpose', description: 'Check the docs', status: 'running' }]
  await eng($).agent.spawn(spawn(id))
  expect(rowFor(await paneTexts($), 'Check the docs')).toBe('general-purpose · Opus 4.8 · low · running · 0s')

  await step($, id, 'high')
  await until(() => world.steps.length === 1, 'the step')
  for (const surface of SURFACES) {
    const t = await untilFacts($, surface, 'Check the docs', 'high')
    if (surface === 'terminal') expect(rowFor(t, 'Check the docs')).toBe('general-purpose · Opus 4.8 · high · running · 0s')
    else expect(t).toContain('Opus 4.8 · high')
  }

  await step($, id, 'xhigh', 1)
  for (const surface of SURFACES) {
    const t = await untilFacts($, surface, 'Check the docs', 'xhigh')
    expect(t.join('|')).not.toMatch(/(^|[^x])high/)
  }

  // A number is a budget.
  await step($, id, 8000, 2)
  expect(rowFor(await untilFacts($, 'terminal', 'Check the docs', '8.0k budget'), 'Check the docs')).toContain('· 8.0k budget ·')
})

test('a request of the main session changes no row, and a request of an agent without effort changes nothing', async ($, on) => {
  const { world } = boot(on)
  await startSession($)
  const id = await callAgent(world, $, 'medium')
  world.agents = [{ id, type: 'general-purpose', description: 'Check the docs', status: 'running' }]
  await eng($).agent.spawn(spawn(id))
  await step($, undefined, 'max')
  await step($, id, undefined, 1)
  // The next request, which does change the row, shows the two before it changed nothing.
  await step($, id, 'high', 2)
  const t = await untilFacts($, 'terminal', 'Check the docs', 'high')
  expect(rowFor(t, 'Check the docs')).toBe('general-purpose · Opus 4.8 · high · running · 0s')
  expect(t.join('|')).not.toContain('max')
})

test('a request that comes before the agent\'s row is kept for the row', async ($, on) => {
  const { world } = boot(on)
  await startSession($)
  await step($, 'a1', 'xhigh')
  world.agents = [{ id: 'a1', type: 'general-purpose', description: 'Late row', status: 'running' }]
  await eng($).agent.spawn(spawn('a1', 'Late row'))
  expect(rowFor(await paneTexts($), 'Late row')).toBe('general-purpose · Opus 4.8 · xhigh · running · 0s')
})

test('an agent the mod never saw spawn takes the effort its requests used when the engine\'s list brings it in', async ($, on) => {
  const { world, clock } = boot(on)
  await startSession($)
  // z9 steps before it is listed, and a reload lists it.
  await step($, 'z9', 'xhigh')
  await until(() => world.steps.length === 1, 'the step')
  world.agents = [{ id: 'z9', type: 'Explore', description: 'Unseen one', status: 'running' }]
  await startSession($)
  expect(rowFor(await untilFacts($, 'terminal', 'Unseen one', 'xhigh'), 'Unseen one')).toBe('Explore · xhigh · running')
  expect(await untilFacts($, 'desktop', 'Unseen one', 'xhigh')).toContain('xhigh')

  // y8 steps, and the engine's next check of its list (once a second, while an agent runs) brings it in.
  await step($, 'y8', 'low')
  await until(() => world.steps.length === 2, 'the step')
  world.agents = [...world.agents, { id: 'y8', type: 'Plan', description: 'Other one', status: 'running' }]
  await clock.advance(1_000)
  expect(rowFor(await untilFacts($, 'terminal', 'Other one', 'low'), 'Other one')).toBe('Plan · low · running')
})

test('turn.step passes the request on unchanged and returns what is beneath', async ($, on) => {
  const { world } = boot(on)
  await startSession($)
  const id = await callAgent(world, $, 'low')
  world.agents = [{ id, type: 'general-purpose', description: 'Check the docs', status: 'running' }]
  await eng($).agent.spawn(spawn(id))
  const input = await step($, id, 'high')
  await step($, undefined, 'max', 1)
  expect(world.steps).toEqual([input, expect.objectContaining({ effort: 'max', index: 1 })])
  expect(world.steps[0]).toEqual(input)
})

test('finished agents are drawn dimmed, on the desktop in the muted color and on the terminal with dimColor; running ones are not', async ($, on) => {
  const { world, clock } = boot(on)
  await startSession($)
  world.agents = [
    { id: 'r1', type: 'general-purpose', description: 'Still going', status: 'running' },
    { id: 'c1', type: 'general-purpose', description: 'Finished fine', status: 'completed' },
    { id: 'f1', type: 'general-purpose', description: 'Finished badly', status: 'failed' },
  ]
  for (const [n, d] of [['r1', 'Still going'], ['c1', 'Finished fine'], ['f1', 'Finished badly']] as const) await eng($).agent.spawn(spawn(n, d))
  await clock.advance(1_000)
  await new Promise(r => setTimeout(r, 30))

  const desktop = await mount($, PANE, 'desktop', { bodyColumns: 60 })
  // The running and the finished agents are two drawings; the muted colors are read over both.
  const agentsSvg = { source: (await svgsOf(desktop)).filter(v => /^(Running|Finished) agents/.test(v.alt)).map(v => v.source).join('\n') }
  await desktop.unmount()
  expect(agentsSvg.source).toContain('Still going')
  const classOf = (title: string) => new RegExp(`<text class="(\\w+)"[^>]*>${title}</text>`).exec(agentsSvg.source)?.[1]
  expect(classOf('Still going')).toBe('t')
  expect(classOf('Finished fine')).toBe('m')
  expect(classOf('Finished badly')).toBe('m')
  // The time, and the model and the facts after the type, are muted too; the mark keeps its color.
  expect(agentsSvg.source).toMatch(/<tspan class="m"[^>]*>/)
  expect(agentsSvg.source).toMatch(/<tspan class="s"[^>]*>/)
  expect(agentsSvg.source).toMatch(/<text class="m"[^>]*text-anchor="end"/)
  expect(agentsSvg.source).toMatch(/<text class="s"[^>]*text-anchor="end"/)
  expect(agentsSvg.source).toContain('stroke="#')

  const terminal = await mount($, PANE, 'terminal', { bodyColumns: 60 })
  const texts = await terminal.findAll({ type: 'Text' })
  await terminal.unmount()
  const dim = (t: string) => texts.find(x => x.text === t)?.props?.dimColor
  expect(dim('Still going')).toBeFalsy()
  expect(dim('Finished fine')).toBe(true)
  expect(dim('Finished badly')).toBe(true)
  expect(texts.find(x => x.text?.startsWith('general-purpose · Opus 4.8 · running'))?.props?.dimColor).toBe(true)
})

// ---- the agents card: role icon, status on the right, running and finished groups ---------------------------

const HUES = { violet: '#8B5CF6', blue: '#3D7FE6', teal: '#1E9E9A', grey: '#8f8f8a', green: '#2F9461', red: '#D0453F' }
const agentSvgs = async (d: Drawing) => {
  const all = await svgsOf(d)

  return { live: all.find(v => v.alt.startsWith('Running agents')), done: all.find(v => v.alt.startsWith('Finished agents')) }
}
const toggleOf = async (d: Drawing) => (await d.findAll({ type: 'Button' })).find(b => b.key === 'finished-toggle')
// Waits for the terminal pane to show each agent with its status.
const untilRowsAre = async ($: never, list: { description: string; status: string }[]) => {
  let last: string[] = []
  for (let i = 0; i < 300; i++) {
    last = await paneTexts($, 'terminal')
    if (list.every(a => rowFor(last, a.description)?.includes(` · ${a.status === 'unknown' ? 'ended' : a.status}`))) return
    await new Promise(r => setTimeout(r, 5))
  }
  throw new Error(`the rows never showed ${JSON.stringify(list)}; the pane showed ${JSON.stringify(last)}`)
}
// Puts agents in the world and waits for the engine's next check of its list to bring in their statuses.
const seedAgents = async (w: World, clock: { advance: (ms: number) => Promise<unknown> }, $: never, list: { id: string; type: string; description: string; status: string }[]) => {
  w.agents = list
  for (const a of list) await eng($).agent.spawn(spawn(a.id, a.description, a.type))
  await clock.advance(1_000)
  await untilRowsAre($, list)
}

test('each agent row has the icon of its role, a role label in the role color, and the model and effort after it', async ($, on) => {
  const { world, clock } = boot(on)
  await startSession($)
  await seedAgents(world, clock, $, [
    { id: 'b1', type: 'mentat:builder', description: 'Build it', status: 'running' },
    { id: 'b2', type: 'builder', description: 'Build more', status: 'running' },
    { id: 'e1', type: 'Explore', description: 'Look around', status: 'running' },
    { id: 'p1', type: 'Plan', description: 'Plan it', status: 'running' },
    { id: 'o1', type: 'general-purpose', description: 'Do other things', status: 'running' },
  ])
  const d = await mount($, PANE, 'desktop', { bodyColumns: 60 })
  const { live } = await agentSvgs(d)
  await d.unmount()
  const src = live!.source
  const count = (re: RegExp) => (src.match(re) ?? []).length
  // One glyph per row, by role: the wrench is the builder's (both type names), the others each their own.
  expect(count(/data-role="builder"/g)).toBe(2)
  for (const role of ['explore', 'plan', 'other']) expect(count(new RegExp(`data-role="${role}"`, 'g'))).toBe(1)
  expect(count(/data-role=/g)).toBe(5)
  // The glyph and the label share the role's color.
  const labelOf = (hue: string, text: string) => new RegExp(`<tspan fill="${hue}"[^>]*>${text}</tspan>`).test(src)
  expect(count(new RegExp(`<tspan fill="${HUES.violet}"[^>]*>builder</tspan>`, 'g'))).toBe(2)
  expect(labelOf(HUES.blue, 'explore')).toBe(true)
  expect(labelOf(HUES.teal, 'plan')).toBe(true)
  expect(labelOf(HUES.grey, 'general-purpose')).toBe(true)
  expect(src).toContain(`<g data-role="explore" transform="translate(21 ${55 + 64 * 2}) scale(0.75)" fill="none" stroke="${HUES.blue}"`)
  // The model and effort follow the label, in the secondary color.
  expect(live!.drawn).toEqual(expect.arrayContaining(['builder', 'explore', 'plan', 'Opus 4.8']))
})

test('the status mark is at the right edge of the row, after the title; the role icon is at the left', async ($, on) => {
  const { world, clock } = boot(on)
  await startSession($)
  await seedAgents(world, clock, $, [
    { id: 'r1', type: 'general-purpose', description: 'Still going', status: 'running' },
    { id: 'c1', type: 'general-purpose', description: 'Finished fine', status: 'completed' },
    { id: 'f1', type: 'general-purpose', description: 'Finished badly', status: 'failed' },
    { id: 'u1', type: 'general-purpose', description: 'Gone one', status: 'unknown' },
  ])
  const W = 60 * 8 - 24
  const d = await mount($, PANE, 'desktop', { bodyColumns: 60 })
  const { live, done } = await agentSvgs(d)
  await d.unmount()
  const titleX = Number(/<text class="t" x="(\d+)"[^>]*>Still going<\/text>/.exec(live!.source)![1])
  const markX = (src: string, hue: string) => Number(new RegExp(`<circle cx="([\\d.]+)" cy="[\\d.]+" r="[\\d.]+" fill="${hue}"`).exec(src)![1])
  const iconX = Number(/<g data-role="other" transform="translate\((\d+) /.exec(live!.source)![1])
  for (const x of [markX(live!.source, HUES.blue), markX(done!.source, HUES.green), markX(done!.source, HUES.red)]) {
    expect(x).toBeGreaterThan(titleX)
    expect(x).toBeGreaterThan(W - 40)
    expect(x).toBeLessThan(W)
  }
  // The unknown agent's ring is at the right too, and the icon is left of the title.
  expect(Number(/<circle cx="([\d.]+)"[^>]*class="m"/.exec(done!.source)![1])).toBeGreaterThan(W - 40)
  expect(iconX).toBeLessThan(titleX)
})

test('agents are in a Running group and a Finished group, each headed with its count; the terminal does the same', async ($, on) => {
  const { world, clock } = boot(on)
  await startSession($)
  await seedAgents(world, clock, $, [
    { id: 'r1', type: 'Explore', description: 'First running', status: 'running' },
    { id: 'r2', type: 'Plan', description: 'Second running', status: 'waiting' },
    { id: 'c1', type: 'builder', description: 'Finished fine', status: 'completed' },
  ])
  const d = await mount($, PANE, 'desktop', { bodyColumns: 60 })
  const { live, done } = await agentSvgs(d)
  expect(live!.drawn).toEqual(expect.arrayContaining(['Running · 2', 'First running', 'Second running']))
  expect(live!.drawn).not.toContain('Finished fine')
  expect(done!.drawn).toContain('Finished fine')
  expect((await toggleOf(d))!.props?.label).toBe('▾ Finished · 1')
  await d.unmount()

  const t = await mount($, PANE, 'terminal', { bodyColumns: 60 })
  const texts = await textsOf(t)
  expect(texts).toEqual(expect.arrayContaining(['Running · 2', 'First running', 'Second running', 'Finished fine']))
  expect(texts.indexOf('Running · 2')).toBeLessThan(texts.indexOf('First running'))
  expect(texts.indexOf('Second running')).toBeLessThan(texts.indexOf('Finished fine'))
  expect((await toggleOf(t))!.props?.label).toBe('▾ Finished · 1')
  await t.unmount()
})

test('the Finished button hides the finished rows and shows them again, on both surfaces; running rows stay', async ($, on) => {
  const { world, clock } = boot(on)
  await startSession($)
  await seedAgents(world, clock, $, [
    { id: 'r1', type: 'Explore', description: 'Still going', status: 'running' },
    { id: 'c1', type: 'builder', description: 'Finished fine', status: 'completed' },
    { id: 'f1', type: 'builder', description: 'Finished badly', status: 'failed' },
  ])
  for (const surface of SURFACES) {
    let d = await mount($, PANE, surface, { bodyColumns: 60 })
    const shown = async () => await textsOf(d)
    expect(await shown()).toEqual(expect.arrayContaining(['Still going', 'Finished fine', 'Finished badly']))

    await d.press({ key: 'finished-toggle' })
    let t = await shown()
    expect(t).toContain('Still going')
    expect(t).not.toContain('Finished fine')
    expect(t).not.toContain('Finished badly')
    expect((await toggleOf(d))!.props?.label).toBe('▸ Finished · 2')
    if (surface === 'desktop') expect((await agentSvgs(d)).done).toBeUndefined()

    // The choice is kept for the next drawing of the pane.
    await d.unmount()
    d = await mount($, PANE, surface, { bodyColumns: 60 })
    expect(await shown()).not.toContain('Finished fine')

    await d.press({ key: 'finished-toggle' })
    t = await shown()
    expect(t).toEqual(expect.arrayContaining(['Still going', 'Finished fine', 'Finished badly']))
    expect((await toggleOf(d))!.props?.label).toBe('▾ Finished · 2')
    await d.unmount()
  }
})

test('a group with no rows is not drawn: no Finished button when none finished, no Running header when none run', async ($, on) => {
  const { world, clock } = boot(on)
  await startSession($)
  await seedAgents(world, clock, $, [{ id: 'r1', type: 'Explore', description: 'Only running', status: 'running' }])
  for (const surface of SURFACES) {
    const d = await mount($, PANE, surface, { bodyColumns: 60 })
    expect(await toggleOf(d)).toBeUndefined()
    const t = await textsOf(d)
    expect(t).toContain('Only running')
    expect(t.some(x => x.startsWith('Finished'))).toBe(false)
    if (surface === 'desktop') expect((await agentSvgs(d)).done).toBeUndefined()
    await d.unmount()
  }

  world.agents = [{ id: 'r1', type: 'Explore', description: 'Only running', status: 'completed' }]
  await clock.advance(1_000)
  await untilRowsAre($, [{ description: 'Only running', status: 'completed' }])
  for (const surface of SURFACES) {
    const d = await mount($, PANE, surface, { bodyColumns: 60 })
    expect((await toggleOf(d))!.props?.label).toBe('▾ Finished · 1')
    const t = await textsOf(d)
    expect(t).toContain('Only running')
    expect(t.some(x => x.startsWith('Running'))).toBe(false)
    if (surface === 'desktop') expect((await agentSvgs(d)).live).toBeUndefined()
    await d.unmount()
  }
})

test('the third line has the tokens and the elapsed time, and leaves out what is missing', async ($, on) => {
  const { world, clock } = boot(on)
  await startSession($)
  await seedAgents(world, clock, $, [
    { id: 'a1', type: 'Explore', description: 'With both', status: 'running' },
    { id: 'a2', type: 'Explore', description: 'Time only', status: 'running' },
  ])
  await eng($).turn.complete(turnDone('a1', { input_tokens: 1, cache_creation_input_tokens: 2, output_tokens: 12000, cache_read_input_tokens: 0, model: 'm' }))
  await clock.advance(124_000)
  world.agents = [...world.agents, { id: 'z9', type: 'Explore', description: 'Seen after a reload', status: 'running' }]
  await startSession($)
  await untilRowsAre($, [{ description: 'Seen after a reload', status: 'running' }])
  const d = await mount($, PANE, 'desktop', { bodyColumns: 60 })
  const { live } = await agentSvgs(d)
  await d.unmount()
  const stats = [...live!.source.matchAll(/<text class="s"[^>]*text-anchor="end"[^>]*>([^<]*)<\/text>/g)].map(m => m[1])
  expect(stats).toContain('12k tokens · 2m 05s')
  expect(stats).toContain('2m 05s')
  // An agent with neither has no third line at all.
  expect(stats.length).toBe(2)
  expect(live!.source).toMatch(/text-anchor="end"/)
})

// ---- the session card and width --------------------------------------------------------------------------------

test('below 48 columns secondary agent facts drop', async ($, on) => {
  const { world } = boot(on)
  world.usage = { context: 10, limits: [{ kind: 'five_hour', percentUsed: 12, resetsAt: new Date(T0 + 3600_000).toISOString() }] }
  await startSession($)
  const id = await callAgent(world, $, 'high')
  world.agents = [{ id, type: 'general-purpose', description: 'Narrow one', status: 'running' }]
  await eng($).agent.spawn(spawn(id, 'Narrow one'))
  await eng($).turn.complete(turnDone(id, { input_tokens: 1000, cache_creation_input_tokens: 0, output_tokens: 0, cache_read_input_tokens: 0, model: 'm' }))
  const wide = await paneTexts($, 'terminal', 60)
  expect(rowFor(wide, 'Narrow one')).toContain('reported')
  const narrow = await paneTexts($, 'terminal', 40)
  const facts = rowFor(narrow, 'Narrow one') ?? ''
  expect(facts).not.toContain('reported')
  expect(facts).not.toContain('high')
  expect(facts).toContain('running')
})

test('the pane shows no usage on either surface: no tiles, no meters, no resets', async ($, on) => {
  const { world } = boot(on)
  world.usage = { context: 41, limits: [limit('five_hour', 85, RESET_5H()), limit('seven_day', 8, RESET_WEEK())] }
  const usage = /context|session|5-hour|week|resets|%|[█░]/i
  for (const surface of SURFACES) {
    const empty = await mount($, PANE, surface, { bodyColumns: 60 })
    expect((await empty.findAll({ type: 'Svg' })).length).toBe(0)
    expect((await textsOf(empty)).some(t => usage.test(t))).toBe(false)
    await empty.unmount()
  }
  // The band still warns at 80%.
  expect(await bandTexts($, 'terminal')).toContain('5-hour limit 85% · resets in 1h 29m')
  // With something to show, still no usage; the desktop draws only its own cards.
  await eng($).tool.call({ tool: OPEN, question: 'Anything?' })
  const withCard = await mount($, PANE, 'desktop', { bodyColumns: 60 })
  expect((await altsOf(withCard)).filter(a => !a.startsWith('Question'))).toEqual([])
  expect((await textsOf(withCard)).some(t => usage.test(t))).toBe(false)
  await withCard.unmount()
  const terminal = await mount($, PANE, 'terminal', { bodyColumns: 60 })
  expect((await terminal.findAll({ type: 'Svg' })).length).toBe(0)
  expect((await textsOf(terminal)).some(t => usage.test(t))).toBe(false)
  await terminal.unmount()
})

test('no card is drawn for what there is not: no pull request, no agents, no questions', async ($, on) => {
  boot(on)
  const t = await paneTexts($)
  expect(t.some(x => x.toUpperCase().startsWith('AGENTS'))).toBe(false)
  expect(t).not.toContain('GitHub')
  expect(t.some(x => x.toLowerCase().includes('no ') && x.toLowerCase().includes('yet'))).toBe(false)
})

const RESET_5H = () => new Date(T0 + 3600_000 + 29 * 60_000).toISOString()
// Thu 2026-10-15 23:00Z: Thu 7:00 PM in New York.
const RESET_WEEK = () => new Date(T0 + 6 * 86400_000 + 11 * 3600_000).toISOString()
const limit = (kind: string, percentUsed: number, resetsAt?: string) => ({ kind, percentUsed, resetsAt })

test('/mentat opens the pane at once when there is something to show', async ($, on) => {
  const { world } = boot(on)
  await startSession($)
  await eng($).tool.call({ tool: OPEN, question: 'Anything?' })
  const ran = await eng($).command.run({ command: 'mentat', args: '' })
  expect(world.opened).toContain('mentat')
  expect(ran.text ?? '').not.toBe('')
})

test('/mentat with nothing else to show opens the pane, so the Commands card is reachable', async ($, on) => {
  const { world } = boot(on)
  world.usage = { context: 10, limits: [limit('five_hour', 12, RESET_5H()), limit('seven_day', 8, RESET_WEEK())] }
  await startSession($)
  const ran = await eng($).command.run({ command: 'mentat', args: '' })
  expect(ran.text).toBe('Mentat pane opened.')
  expect(world.opened).toEqual(['mentat'])

  // The same with no usage, or when the engine cannot answer.
  world.opened.length = 0
  world.usage = { limits: [] }
  world.usageFails = true
  expect((await eng($).command.run({ command: 'mentat', args: '' })).text).toBe('Mentat pane opened.')
  expect(world.opened).toEqual(['mentat'])
})

test('/mentat opens the pane for an open question, a followed pull request or an agent row', async ($, on) => {
  const { world } = boot(on)
  await startSession($)
  await eng($).tool.call({ tool: OPEN, question: 'Open one?' })
  await eng($).command.run({ command: 'mentat', args: '' })
  expect(world.opened).toEqual(['mentat'])
  await eng($).tool.call({ tool: CLOSE, id: 'd1' })

  // An agent row, ended or not, is something the pane lists.
  const id = await callAgent(world, $, 'high')
  world.agents = [{ id, type: 'general-purpose', description: 'Done already', status: 'completed' }]
  await eng($).agent.spawn(spawn(id, 'Done already'))
  world.opened.length = 0
  const withAgent = await eng($).command.run({ command: 'mentat', args: '' })
  expect(world.opened).toEqual(['mentat'])
  expect(withAgent.text).toBe('Mentat pane opened.')
})

test('/mentat opens the pane for a followed pull request', async ($, on) => {
  const { world } = boot(on)
  await follow109($)
  world.opened.length = 0
  await eng($).command.run({ command: 'mentat', args: '' })
  expect(world.opened).toEqual(['mentat'])
})

// ---- the band for budget ------------------------------------------------------------

test('the band shows for a rate limit at 80 and not at 79, on both surfaces', async ($, on) => {
  const { world } = boot(on)
  world.usage = { context: 5, limits: [limit('five_hour', 79, RESET_5H()), limit('seven_day', 10)] }
  for (const surface of SURFACES) expect((await bandTexts($, surface)).some(t => t.includes('limit'))).toBe(false)

  world.usage = { context: 5, limits: [limit('five_hour', 80, RESET_5H()), limit('seven_day', 10)] }
  for (const surface of SURFACES) {
    const t = await bandTexts($, surface)
    expect(t).toContain('5-hour limit 80% · resets in 1h 29m')
    // Both keep their Details button: the pane holds the Commands card.
    const d = await mount($, BAND, surface)
    expect((await d.findAll({ type: 'Button' })).map(b => b.key)).toEqual(['open'])
    await d.unmount()
  }

  world.usage = { context: 5, limits: [limit('five_hour', 40), limit('seven_day', 91, RESET_WEEK())] }
  expect(await bandTexts($)).toContain('Week limit 91% · resets Thu 7:00 PM')

  // Both over: the higher one.
  world.usage = { context: 5, limits: [limit('five_hour', 84), limit('seven_day', 91)] }
  const both = await bandTexts($)
  expect(both).toContain('Week limit 91%')
  expect(both.some(t => t.includes('5-hour'))).toBe(false)
})

test('the context meter alone does not raise the band, and a failed usage read means no budget band', async ($, on) => {
  const { world } = boot(on)
  world.usage = { context: 90, limits: [limit('five_hour', 12), limit('seven_day', 8)] }
  for (const surface of SURFACES) expect((await bandTexts($, surface)).some(t => t.includes('%'))).toBe(false)
  const d = await mount($, BAND, 'terminal')
  expect((await d.findAll({ type: 'Button' })).length).toBe(0)
  await d.unmount()

  world.usageFails = true
  const failed = await mount($, BAND, 'terminal')
  expect((await failed.findAll({ type: 'Button' })).length).toBe(0)
  await failed.unmount()
})

test('a budget band keeps its Details button when the pane has agents too', async ($, on) => {
  const { world } = boot(on)
  world.usage = { context: 5, limits: [limit('five_hour', 90, RESET_5H())] }
  const id = await callAgent(world, $, 'high')
  world.agents = [{ id, type: 'general-purpose', description: 'Working', status: 'running' }]
  await eng($).agent.spawn(spawn(id, 'Working'))
  expect(await bandTexts($, 'terminal')).toContain('5-hour limit 90% · resets in 1h 29m')
  for (const surface of SURFACES) {
    const d = await mount($, BAND, surface)
    expect((await d.findAll({ type: 'Button' })).map(b => b.key)).toEqual(['open'])
    await d.unmount()
  }
})

test('the desktop pane with nothing to show says so in one line; the terminal pane draws no such line', async ($, on) => {
  boot(on)
  const desktop = await mount($, PANE, 'desktop', { bodyColumns: 60 })
  expect(await textsOf(desktop)).toEqual(['Nothing waiting on you.'])
  expect((await desktop.findAll({ type: 'Svg' })).length).toBe(0)
  // The Commands card's toggle stays beside the line.
  expect(await cardKeys(desktop)).toEqual([])
  expect((await desktop.findAll({ type: 'Button' })).map(b => b.key)).toEqual(['commands-toggle'])
  await desktop.unmount()

  // Something open: the line goes.
  await eng($).tool.call({ tool: OPEN, question: 'Anything?' })
  const busy = await mount($, PANE, 'desktop', { bodyColumns: 60 })
  expect(await textsOf(busy)).not.toContain('Nothing waiting on you.')
  await busy.unmount()
})

test('the weekly reset prints as weekday and local time in the band; the 5-hour one stays a countdown', async ($, on) => {
  const { world } = boot(on)
  world.usage = { context: 10, limits: [limit('five_hour', 12, RESET_5H()), limit('seven_day', 91, RESET_WEEK())] }
  expect(await bandTexts($, 'terminal')).toContain('Week limit 91% · resets Thu 7:00 PM')
  expect(await bandTexts($, 'desktop')).toContain('Week limit 91% · resets Thu 7:00 PM')

  // The 5-hour limit alone keeps its countdown in the band.
  world.usage = { context: 10, limits: [limit('five_hour', 90, RESET_5H()), limit('seven_day', 8, RESET_WEEK())] }
  expect(await bandTexts($)).toContain('5-hour limit 90% · resets in 1h 29m')
})

test('the weekly reset follows TZ', async ($, on) => {
  const { world } = boot(on, { zone: 'Asia/Kolkata' })
  world.usage = { context: 10, limits: [limit('seven_day', 91, RESET_WEEK())] }
  // 23:00Z is 4:30 AM the next day in India (UTC+5:30).
  expect(await bandTexts($)).toContain('Week limit 91% · resets Fri 4:30 AM')
})

test('resetAt words the weekly reset in 12-hour time with a short weekday, in the zone given', () => {
  const now = T0
  const at = '2026-10-15T23:00:00Z'
  expect(resetAt(at, now, 'America/New_York')).toBe('resets Thu 7:00 PM')
  expect(resetAt(at, now, 'UTC')).toBe('resets Thu 11:00 PM')
  expect(resetAt(at, now, 'Asia/Tokyo')).toBe('resets Fri 8:00 AM')
  expect(resetAt('2026-10-16T04:00:00Z', now, 'America/Los_Angeles')).toBe('resets Thu 9:00 PM')
  // Midnight and noon read 12 AM and 12 PM.
  expect(resetAt('2026-10-16T00:00:00Z', now, 'UTC')).toBe('resets Fri 12:00 AM')
  expect(resetAt('2026-10-16T12:05:00Z', now, 'UTC')).toBe('resets Fri 12:05 PM')
  // No reset known, or one already past: nothing.
  expect(resetAt(undefined, now, 'UTC')).toBe('')
  expect(resetAt('2026-10-09T11:00:00Z', now, 'UTC')).toBe('')
  expect(resetAt('not a date', now, 'UTC')).toBe('')
  // An unknown zone name still words the reset, in the process's own zone.
  expect(resetAt(at, now, 'Not/AZone')).toMatch(/^resets \w{3} \d{1,2}:\d{2} [AP]M$/)
})

test('a question comes before budget in the band, and so does a final-checked pull request', async ($, on) => {
  const { world } = boot(on)
  world.usage = { context: 5, limits: [limit('five_hour', 95, RESET_5H())] }
  world.issueComments = ok(pages([finalCheck(H1)]))
  await startSession($)
  await eng($).tool.call({ tool: OPEN, question: 'Ask first?' })
  for (const surface of SURFACES) {
    const t = await bandTexts($, surface)
    expect(t.some(x => x.includes('limit'))).toBe(false)
    expect(t).toContain('Ask first?')
  }
  await eng($).tool.call({ tool: CLOSE, id: 'd1' })
  expect((await bandTexts($)).some(x => x.includes('limit'))).toBe(true)

  await follow($)
  await untilPane($, '#109')
  for (const surface of SURFACES) {
    const t = await bandTexts($, surface)
    expect(t).toContain(surface === 'terminal' ? '· Final check posted' : 'Final check posted')
    expect(t.some(x => x.includes('limit'))).toBe(false)
  }
})

// ---- the answer field -------------------------------------------------------------------

test('the answer field starts focused and sits in a full-width box, tinted like the question card on the desktop only', async ($, on) => {
  boot(on)
  await eng($).tool.call({ tool: OPEN, question: 'Keep it?' })
  const opener = await mount($, PANE, 'terminal')
  expect(await opener.findAll({ type: 'Input' })).toEqual([])
  await opener.press({ key: 'answer-open-d1' })
  await opener.unmount()
  for (const surface of SURFACES) {
    const pane = await mount($, PANE, surface)
    const [input] = await pane.findAll({ type: 'Input' })
    expect(input?.props?.autoFocus).toBe(true)
    const boxes = (await pane.findAll({ type: 'Box' })).filter(b => b.props?.width === '100%')
    expect(boxes.length).toBe(1)
    // Only the desktop tints it; a terminal draws an 8-digit hex tint as opaque grey.
    expect(boxes[0]!.props?.backgroundColor).toBe(surface === 'desktop' ? '#d2992224' : undefined)
    await pane.unmount()
  }
})

// ---- kinds of open item: question, action, alert ------------------------------------------

const RED = '#D0453F'
const BLUE = '#3D7FE6'
const AMBER = '#C98A0E'
// Opens an item with kind (none: a call without kind); call the result with $.
const open = (kind: string | undefined, question: string, extra: object = {}) => ($: never) =>
  eng($).tool.call({ tool: OPEN, ...(kind === undefined ? {} : { kind }), question, ...extra })
// Every Button key, Link href and Svg alt of a drawing.
const keysOf = cardKeys
const hrefsOf = async (d: Drawing) => (await d.findAll({ type: 'Link' })).map(l => String(l.props?.href))
const altsOf = async (d: Drawing) => (await svgsOf(d)).map(v => v.alt)

test('an alert card is red, labelled ALERT, with Dismiss and no answer buttons, on both surfaces', async ($, on) => {
  boot(on)
  await open('alert', 'CI is red and I cannot fix it', { accept: 'Yes', recommendation: 'Look at the log' })($)
  const term = await mount($, PANE, 'terminal', { bodyColumns: 60 })
  const t = await textsOf(term)
  expect(t).toEqual(expect.arrayContaining(['ALERT', 'CI is red and I cannot fix it', '→ Look at the log']))
  expect(t).not.toContain('QUESTION FOR YOU')
  expect((await term.findAll({ type: 'Text', text: 'ALERT' }))[0]!.props?.color).toBe('error')
  expect((await term.findAll({ type: 'Box' })).some(b => b.props?.backgroundColor !== undefined)).toBe(false)
  expect(await keysOf(term)).toEqual(['dismiss-d1'])
  expect(await term.findAll({ type: 'Input' })).toEqual([])
  await term.unmount()

  const desk = await mount($, PANE, 'desktop', { bodyColumns: 60 })
  const [card] = (await svgsOf(desk)).filter(v => v.alt.startsWith('Alert'))
  expect(card!.alt).toBe('Alert: CI is red and I cannot fix it')
  expect(card!.drawn).toEqual(expect.arrayContaining(['ALERT', 'CI is red and I cannot fix it', '→ Look at the log']))
  expect(card!.source).toContain(RED)
  expect(card!.source).toContain('class="qr"')
  expect(card!.source).not.toContain(AMBER)
  expect(await keysOf(desk)).toEqual(['dismiss-d1'])
  await desk.unmount()
})

test('an action card is blue, labelled WAITING ON YOU, with Dismiss and no answer buttons, on both surfaces', async ($, on) => {
  boot(on)
  await open('action', 'Merge #112 when ready', { accept: 'Yes' })($)
  const term = await mount($, PANE, 'terminal', { bodyColumns: 60 })
  expect(await textsOf(term)).toEqual(expect.arrayContaining(['WAITING ON YOU', 'Merge #112 when ready']))
  expect((await term.findAll({ type: 'Box' })).some(b => b.props?.backgroundColor !== undefined)).toBe(false)
  expect(await keysOf(term)).toEqual(['dismiss-d1'])
  await term.unmount()

  const desk = await mount($, PANE, 'desktop', { bodyColumns: 60 })
  const [card] = (await svgsOf(desk)).filter(v => v.alt.startsWith('Waiting on you'))
  expect(card!.alt).toBe('Waiting on you: Merge #112 when ready')
  expect(card!.drawn).toEqual(expect.arrayContaining(['WAITING ON YOU', 'Merge #112 when ready']))
  expect(card!.source).toContain(BLUE)
  expect(card!.source).toContain('class="qb"')
  expect(await keysOf(desk)).toEqual(['dismiss-d1'])
  await desk.unmount()
})

test('a question with kind question and one without a kind are the same amber card with answer buttons', async ($, on) => {
  boot(on)
  await open(undefined, 'Plain?', { accept: 'Yes' })($)
  await open('question', 'Explicit?', { accept: 'Yes' })($)
  for (const surface of SURFACES) {
    const d = await mount($, PANE, surface, { bodyColumns: 60 })
    expect(await keysOf(d)).toEqual(['accept-d1', 'answer-open-d1', 'dismiss-d1', 'accept-d2', 'answer-open-d2', 'dismiss-d2'])
    expect(await textsOf(d)).toEqual(expect.arrayContaining(['QUESTION FOR YOU', 'Plain?', 'Explicit?']))
    if (surface === 'desktop') {
      const cards = (await svgsOf(d)).filter(v => v.alt.startsWith('Question'))
      expect(cards.map(c => c.alt)).toEqual(['Question: Plain?', 'Question: Explicit?'])
      for (const c of cards) expect(c.source).toContain(AMBER)
      // The same drawing for both: only the text differs.
      expect(cards[0]!.source.replace('Plain?', 'Explicit?')).toBe(cards[1]!.source)
    }
    await d.unmount()
  }
})

test('an unknown kind is refused with a message and records nothing', async ($, on) => {
  boot(on)
  const refused = await eng($).tool.call({ tool: OPEN, kind: 'urgent', question: 'Now?' })
  expect(refused.deny).toBe('open_decision kind must be question, action or alert.')
  expect(await paneTexts($)).not.toContain('Now?')
  expect((await bandTexts($)).length).toBe(0)
})

test('the pane lists alerts, then questions, then actions, in the order opened within each kind', async ($, on) => {
  boot(on)
  await open('action', 'Action one')($)
  await open(undefined, 'Question one')($)
  await open('alert', 'Alert one')($)
  await open('action', 'Action two')($)
  await open('alert', 'Alert two')($)
  await open('question', 'Question two')($)
  const want = ['Alert one', 'Alert two', 'Question one', 'Question two', 'Action one', 'Action two']
  const t = await paneTexts($, 'terminal')
  expect(want.map(w => t.indexOf(w))).toEqual([...want.map(w => t.indexOf(w))].sort((a, b) => a - b))
  expect(want.every(w => t.includes(w))).toBe(true)
  const d = await mount($, PANE, 'desktop', { bodyColumns: 60 })
  expect((await altsOf(d)).filter(a => /^(Alert|Question|Waiting)/.test(a))).toEqual([
    'Alert: Alert one',
    'Alert: Alert two',
    'Question: Question one',
    'Question: Question two',
    'Waiting on you: Action one',
    'Waiting on you: Action two',
  ])
  await d.unmount()
})

test('an action or alert shows its link as a Link element beside Dismiss, only when it is an https URL', async ($, on) => {
  boot(on)
  const url = 'https://github.com/o/r/issues/112'
  await open('action', 'With a link', { link: url })($)
  await open('alert', 'Alert link', { link: `  ${url}  ` })($)
  for (const bad of ['http://github.com/o/r', 'javascript:alert(1)', 'ftp://x/y', 'github.com/o/r', 'https://', 'https:// spaced', 'file:///etc/passwd', '']) {
    await open('action', `Bad ${bad}`, { link: bad })($)
  }
  for (const surface of SURFACES) {
    const d = await mount($, PANE, surface, { bodyColumns: 60 })
    expect(await hrefsOf(d)).toEqual([url, url])
    const links = await d.findAll({ type: 'Link' })
    expect(links.every(l => l.props?.label === 'github.com/o/r/issues/112')).toBe(true)
    // Dismiss is drawn for every card, link or not.
    expect((await keysOf(d)).filter(k => String(k).startsWith('dismiss-')).length).toBe(10)
    await d.unmount()
  }
})

test('a question draws no link, and a call without kind or link behaves as before', async ($, on) => {
  boot(on)
  await open(undefined, 'No link?', { link: 'https://github.com/o/r/issues/1' })($)
  for (const surface of SURFACES) {
    const d = await mount($, PANE, surface, { bodyColumns: 60 })
    expect(await hrefsOf(d)).toEqual([])
    await d.unmount()
  }
})

// Band priority. A final-checked pull request, a rate limit over 80% and the items open together.
const bandWith = async ($: never, surface: 'terminal' | 'desktop') => {
  const d = await mount($, BAND, surface)
  const out = { texts: await textsOf(d), alts: await altsOf(d) }
  await d.unmount()
  return out
}
const pillFor = (t: string[]) => t.find(x => /^\d+ (question|questions|item|items)$/.test(x))

test('the band shows the newest alert over everything else, then a question, a final-checked pull request, a budget warning and an action', async ($, on) => {
  const { world } = boot(on)
  world.usage = { context: 5, limits: [limit('five_hour', 95, RESET_5H())] }
  world.issueComments = ok(pages([finalCheck(H1)]))
  await follow109($)
  await open('action', 'Do the thing')($)
  await open(undefined, 'Ask first?')($)
  await open('alert', 'Old alert')($)
  await open('alert', 'New alert')($)
  const ids = { action: 'd1', question: 'd2', old: 'd3', fresh: 'd4' }

  // Everything raises it: the alert wins and the count is of all four.
  for (const surface of SURFACES) {
    const { texts, alts } = await bandWith($, surface)
    expect(texts).toContain('New alert')
    expect(texts).not.toContain('Old alert')
    expect(texts.some(x => x.includes('Final check') || x.includes('limit') || x.includes('Ask first?') || x.includes('Do the thing'))).toBe(false)
    expect(pillFor(texts)).toBe('4 items')
    if (surface === 'desktop') {
      expect(alts).toEqual(['Alert: New alert'])
      expect(texts).toContain('!')
    }
  }
  const term = await mount($, BAND, 'terminal')
  expect((await term.findAll({ type: 'Text', text: '!' }))[0]!.props?.color).toBe('error')
  expect((await term.findAll({ type: 'Box' })).some(b => b.props?.backgroundColor !== undefined)).toBe(false)
  await term.unmount()
  const desk = await mount($, BAND, 'desktop')
  const band = (await svgsOf(desk))[0]!.source
  expect(band).toContain(RED)
  await desk.unmount()

  // The alerts closed: the question, with the count of the two left.
  await eng($).tool.call({ tool: CLOSE, id: ids.fresh })
  await eng($).tool.call({ tool: CLOSE, id: ids.old })
  for (const surface of SURFACES) {
    const { texts, alts } = await bandWith($, surface)
    expect(texts).toContain('Ask first?')
    expect(texts.some(x => x.includes('Final check') || x.includes('limit') || x.includes('Do the thing'))).toBe(false)
    expect(pillFor(texts)).toBe('2 items')
    if (surface === 'desktop') expect(alts).toEqual(['Question: Ask first?'])
  }

  // The question closed: the final-checked pull request, with the action counted; then the same
  // with the pull request not final-checked would show the budget (the next test).
  await eng($).tool.call({ tool: CLOSE, id: ids.question })
  for (const surface of SURFACES) {
    const { texts, alts } = await bandWith($, surface)
    expect(texts).toContain(surface === 'terminal' ? '· Final check posted' : 'Final check posted')
    expect(texts.some(x => x.includes('limit') || x.includes('Do the thing'))).toBe(false)
    expect(pillFor(texts)).toBe('1 item')
    if (surface === 'desktop') expect(alts).toEqual(['#109 final check posted'])
  }
})

test('without alerts or a final check the band shows the newest question over a budget warning, then the budget over an action', async ($, on) => {
  const { world } = boot(on)
  world.usage = { context: 5, limits: [limit('five_hour', 95, RESET_5H())] }
  await open('action', 'Do the thing')($)
  // An action alone does not outrank a budget warning; the count says it is there.
  for (const surface of SURFACES) {
    const { texts } = await bandWith($, surface)
    expect(texts).toContain('5-hour limit 95% · resets in 1h 29m')
    expect(texts).not.toContain('Do the thing')
    expect(pillFor(texts)).toBe('1 item')
  }
  await open(undefined, 'Ask first?')($)
  for (const surface of SURFACES) {
    const { texts } = await bandWith($, surface)
    expect(texts).toContain('Ask first?')
    expect(texts.some(x => x.includes('limit'))).toBe(false)
    expect(pillFor(texts)).toBe('2 items')
  }
})

test('a lone action raises the band, with its text on the left and no count on the desktop', async ($, on) => {
  boot(on)
  await open('action', 'Run the plugin update', { link: 'https://github.com/o/r/pull/9' })($)
  const term = await bandWith($, 'terminal')
  expect(term.texts).toEqual(expect.arrayContaining(['→', 'Run the plugin update', '1 item']))
  const desk = await bandWith($, 'desktop')
  expect(desk.alts).toEqual(['Waiting on you: Run the plugin update'])
  expect(desk.texts).toContain('Run the plugin update')
  expect(pillFor(desk.texts)).toBeUndefined()
  // A second item brings the count back, and the band's Details button stays.
  await open('action', 'Another')($)
  expect(pillFor((await bandWith($, 'desktop')).texts)).toBe('2 items')
  const d = await mount($, BAND, 'terminal')
  expect(await keysOf(d)).toEqual(['open'])
  await d.unmount()
})

test('the count says questions when every open item is a question, and items otherwise', async ($, on) => {
  boot(on)
  await open(undefined, 'One?')($)
  await open('question', 'Two?')($)
  expect(pillFor((await bandWith($, 'terminal')).texts)).toBe('2 questions')
  await open('alert', 'Down')($)
  expect(pillFor((await bandWith($, 'terminal')).texts)).toBe('3 items')
  expect(pillFor((await bandWith($, 'desktop')).texts)).toBe('3 items')
})

test('/mentat opens the pane for an open action or alert', async ($, on) => {
  const { world } = boot(on)
  await open('action', 'Do it')($)
  await eng($).command.run({ command: 'mentat', args: '' })
  expect(world.opened).toEqual(['mentat'])
})

test('closing an alert or an action by id removes it, and a new conversation drops them too', async ($, on) => {
  boot(on)
  const classic = ($ as never as { classic: { SessionStart: (a: { source: string }) => Promise<unknown> } }).classic
  await open('alert', 'Down')($)
  await open('action', 'Do it')($)
  await eng($).tool.call({ tool: CLOSE, id: 'd1' })
  expect(await paneTexts($)).not.toContain('Down')
  expect(await paneTexts($)).toContain('Do it')
  await classic.SessionStart({ source: 'clear' })
  expect(await paneTexts($)).not.toContain('Do it')
  expect((await bandTexts($)).length).toBe(0)
})

// ---- the `mentat check` signal ----------------------------------------------------------------

const FAILED_RUN = 'OK: gh is installed\nPROBLEM: codex is not installed\nPROBLEM: gh is not logged in\nCheck failed: 2 problem(s)\n'
const alertsOf = async ($: never) => {
  const d = await mount($, PANE, 'desktop', { bodyColumns: 60 })
  const cards = (await svgsOf(d)).filter(v => v.alt.startsWith('Alert'))
  await d.unmount()
  return cards
}
const HUE_AMBER = '#C98A0E'
const toastTexts = (w: World) => w.toasts.map(t => (JSON.parse(t) as { text: string }).text)

test('a failed mentat check pins one alert with its PROBLEM lines, in the pane and the band', async ($, on) => {
  const { world } = boot(on)
  await bash(world, $, 'cd "a b" && mentat check 2>&1', FAILED_RUN)
  const [card, ...more] = await alertsOf($)
  expect(more).toEqual([])
  expect(card!.alt).toBe('Alert: Check failed: 2 problem(s)')
  expect(card!.drawn).toEqual(expect.arrayContaining(['ALERT', 'Check failed: 2 problem(s)', 'codex is not installed', 'gh is not logged in']))
  expect(card!.drawn).not.toContain('gh is installed')
  const term = await paneTexts($, 'terminal')
  expect(term).toEqual(expect.arrayContaining(['ALERT', 'Check failed: 2 problem(s)', 'codex is not installed', 'gh is not logged in']))
  for (const surface of SURFACES) expect((await bandTexts($, surface)).includes('Check failed: 2 problem(s)')).toBe(true)
  // Only Dismiss: no answer buttons, no toast for a failure.
  const d = await mount($, PANE, 'terminal', { bodyColumns: 60 })
  expect(await keysOf(d)).toEqual(['dismiss-check'])
  await d.unmount()
  expect(toastTexts(world)).toEqual([])
})

test('a second failed run replaces the alert, so there is still one', async ($, on) => {
  const { world } = boot(on)
  await open(undefined, 'A question stays?')($)
  await bash(world, $, 'mentat check', FAILED_RUN)
  await bash(world, $, '/Users/me/.local/bin/mentat check | cat', 'PROBLEM: gh is not logged in\nCheck failed: 1 problem(s)')
  const cards = await alertsOf($)
  expect(cards.length).toBe(1)
  expect(cards[0]!.alt).toBe('Alert: Check failed: 1 problem(s)')
  expect(cards[0]!.drawn).toContain('gh is not logged in')
  expect(cards[0]!.drawn).not.toContain('codex is not installed')
  // The agent's own question is untouched, and the alert is still the first card.
  const d = await mount($, PANE, 'desktop', { bodyColumns: 60 })
  expect((await altsOf(d)).filter(a => /^(Alert|Question)/.test(a))).toEqual(['Alert: Check failed: 1 problem(s)', 'Question: A question stays?'])
  await d.unmount()
})

const WARN_RUN = 'OK: gh is installed\nWARN: gh is old\nWARN: codex is old\nCheck OK (2 warning(s))\n'
const CLEAN_RUN = 'OK: gh is installed\nCheck OK (0 warning(s))\n'
const SESSION_MODE = { plugin: 'mentat', component: 'SessionMode' }
// The footer label as drawn: each Text with its color and dim flag, in order.
const footerOf = async ($: never, surface: 'terminal' | 'desktop', modes: string[] = []) => {
  const d = await mount($, SESSION_MODE, surface, { modes })
  const texts = (await d.findAll({ type: 'Text' })).map(t => ({ text: t.text ?? '', color: t.props?.color as string | undefined, dim: t.props?.dimColor === true }))
  await d.unmount()
  return texts
}
const checkItemsOf = async ($: never) => {
  const d = await mount($, PANE, 'desktop', { bodyColumns: 60 })
  const cards = (await svgsOf(d)).filter(v => v.alt.startsWith('Check warnings'))
  await d.unmount()
  return cards
}

test('a passing mentat check removes the alert; with no warnings nothing is pinned and no toast is raised', async ($, on) => {
  const { world } = boot(on)
  await bash(world, $, 'mentat check', FAILED_RUN)
  expect((await alertsOf($)).length).toBe(1)

  await bash(world, $, 'mentat check', CLEAN_RUN)
  expect(await alertsOf($)).toEqual([])
  expect(await checkItemsOf($)).toEqual([])
  expect((await paneTexts($, 'terminal')).includes('ALERT')).toBe(false)
  expect((await bandTexts($)).length).toBe(0)
  expect(toastTexts(world)).toEqual([])
})

test('the footer label shows the last check: dim before one, green on a pass, amber with the count, red on a fail, with the engine modes after it', async ($, on) => {
  const { world } = boot(on)
  for (const surface of SURFACES) {
    expect(await footerOf($, surface)).toEqual([{ text: '● Mentat', color: undefined, dim: true }])
    expect(await footerOf($, surface, ['focus', 'memory paused'])).toEqual([
      { text: '● Mentat', color: undefined, dim: true },
      { text: 'focus & memory paused', color: undefined, dim: true },
    ])
  }

  await bash(world, $, 'mentat check', CLEAN_RUN)
  for (const surface of SURFACES) {
    expect(await footerOf($, surface, ['focus'])).toEqual([
      { text: '● Mentat', color: 'success', dim: false },
      { text: 'focus', color: undefined, dim: true },
    ])
  }

  await bash(world, $, 'mentat check', WARN_RUN)
  for (const surface of SURFACES) {
    expect(await footerOf($, surface, ['focus'])).toEqual([
      { text: '● Mentat · 2 warnings', color: 'warning', dim: false },
      { text: 'focus', color: undefined, dim: true },
    ])
  }
  await bash(world, $, 'mentat check', 'WARN: gh is old\nCheck OK (1 warning(s))\n')
  expect((await footerOf($, 'terminal'))[0]).toEqual({ text: '● Mentat · 1 warning', color: 'warning', dim: false })

  await bash(world, $, 'mentat check', FAILED_RUN)
  for (const surface of SURFACES) {
    expect(await footerOf($, surface, ['focus'])).toEqual([
      { text: '● Mentat check failed', color: 'error', dim: false },
      { text: 'focus', color: undefined, dim: true },
    ])
  }
  // A run that says nothing certain leaves the label as it was.
  await bash(world, $, 'mentat check', 'usage: mentat check\n')
  expect((await footerOf($, 'terminal'))[0]!.text).toBe('● Mentat check failed')
  // A subagent's check does not change it either.
  await bash(world, $, 'mentat check', CLEAN_RUN, { agentId: 'a1' })
  expect((await footerOf($, 'terminal'))[0]!.text).toBe('● Mentat check failed')
  expect(toastTexts(world)).toEqual([])
})

test('the footer label leaves other surfaces (mobile) to the engine', async ($, on) => {
  boot(on)
  const d = await mount($, SESSION_MODE, 'mobile' as never, { modes: ['focus'] })
  expect((await d.findAll({ type: 'Text' })).map(t => t.text)).not.toContain('● Mentat')
  expect((await d.findAll({ type: 'Box' })).map(b => b.key)).toEqual(['engine-own'])
  await d.unmount()
})

test('a pass with warnings pins one warning card with the WARN lines, a clean pass removes it, a fail makes it the red alert', async ($, on) => {
  const { world } = boot(on)
  await open(undefined, 'A question stays?')($)
  await bash(world, $, 'cd "a b" && mentat check 2>&1', WARN_RUN)

  const [card, ...more] = await checkItemsOf($)
  expect(more).toEqual([])
  expect(card!.alt).toBe('Check warnings: Check passed with 2 warnings')
  expect(card!.drawn).toEqual(expect.arrayContaining(['CHECK WARNINGS', 'Check passed with 2 warnings', 'gh is old', 'codex is old']))
  expect(card!.drawn).not.toContain('gh is installed')
  expect(card!.source).toContain(HUE_AMBER)
  const term = await mount($, PANE, 'terminal', { bodyColumns: 60 })
  expect(await textsOf(term)).toEqual(expect.arrayContaining(['CHECK WARNINGS', 'Check passed with 2 warnings', 'gh is old', 'codex is old']))
  expect((await term.findAll({ type: 'Text', text: 'CHECK WARNINGS' }))[0]!.props?.color).toBe('warning')
  expect((await term.findAll({ type: 'Box' })).some(b => b.props?.backgroundColor !== undefined)).toBe(false)
  // Only Dismiss: no answer buttons and no link.
  expect(await keysOf(term)).toEqual(expect.arrayContaining(['dismiss-check']))
  expect((await keysOf(term)).filter(k => String(k).includes('check'))).toEqual(['dismiss-check'])
  expect(await hrefsOf(term)).toEqual([])
  await term.unmount()
  // The next warned run replaces it, so there is still one.
  await bash(world, $, 'mentat check', 'WARN: only one\nCheck OK (1 warning(s))\n')
  const again = await checkItemsOf($)
  expect(again.length).toBe(1)
  expect(again[0]!.alt).toBe('Check warnings: Check passed with 1 warning')
  expect(again[0]!.drawn).toContain('only one')
  expect(again[0]!.drawn).not.toContain('gh is old')

  // A fail turns it into the red alert; there is one item with the id check.
  await bash(world, $, 'mentat check', FAILED_RUN)
  expect(await checkItemsOf($)).toEqual([])
  expect((await alertsOf($)).length).toBe(1)

  // A clean pass after a warned one removes it; the agent's question is untouched.
  await bash(world, $, 'mentat check', WARN_RUN)
  expect((await alertsOf($)).length).toBe(0)
  expect((await checkItemsOf($)).length).toBe(1)
  await bash(world, $, 'mentat check', CLEAN_RUN)
  expect(await checkItemsOf($)).toEqual([])
  expect(await paneTexts($, 'terminal')).not.toContain('CHECK WARNINGS')
  expect(await paneTexts($, 'terminal')).toContain('A question stays?')
  expect(toastTexts(world)).toEqual([])
})

test('a warning count the output does not show is still counted, and many warnings are cut to six lines', async ($, on) => {
  const { world } = boot(on)
  await bash(world, $, 'mentat check', 'WARN: seen\nCheck OK (2 warning(s))\n')
  expect((await footerOf($, 'terminal'))[0]!.text).toBe('● Mentat · 2 warnings')
  const [card] = await checkItemsOf($)
  expect(card!.drawn).toEqual(expect.arrayContaining(['seen', 'A warning whose text was not in the output']))

  const warns = Array.from({ length: 8 }, (_, i) => `warning number ${i + 1}`)
  await bash(world, $, 'mentat check', `${warns.map(w => `WARN: ${w}`).join('\n')}\nCheck OK (8 warning(s))`)
  const [many] = await checkItemsOf($)
  expect(many!.drawn).toEqual(expect.arrayContaining([...warns.slice(0, 5), '+3 more']))
  expect(many!.drawn).not.toContain('warning number 6')
})

test('the pane lists alerts, then questions, then the check warning, then actions', async ($, on) => {
  const { world } = boot(on)
  await open('action', 'Do the thing')($)
  await bash(world, $, 'mentat check', WARN_RUN)
  await open(undefined, 'Ask first?')($)
  await open('alert', 'Down')($)
  const d = await mount($, PANE, 'desktop', { bodyColumns: 60 })
  expect((await altsOf(d)).filter(a => /^(Alert|Question|Check warnings|Waiting on you)/.test(a))).toEqual([
    'Alert: Down',
    'Question: Ask first?',
    'Check warnings: Check passed with 2 warnings',
    'Waiting on you: Do the thing',
  ])
  await d.unmount()
  const t = await paneTexts($, 'terminal')
  const at = (x: string) => t.indexOf(x)
  expect([at('ALERT'), at('QUESTION FOR YOU'), at('CHECK WARNINGS'), at('WAITING ON YOU')]).toEqual([...[at('ALERT'), at('QUESTION FOR YOU'), at('CHECK WARNINGS'), at('WAITING ON YOU')]].sort((a, b) => a - b))
  expect(Math.min(at('ALERT'), at('QUESTION FOR YOU'), at('CHECK WARNINGS'), at('WAITING ON YOU'))).toBeGreaterThanOrEqual(0)
})

const LONG_WARN = 'o/r has 2 Actions secret(s); a workflow the agent pushes on a branch may be able to read them (access controls not checked)'
const LONG_PROBLEM = 'the repository settings could not be read because the signed in account lacks the admin scope the check needs to list them'

test('a long WARN line is wrapped whole on the desktop card, which grows to hold it, and wraps on the terminal', async ($, on) => {
  const { world } = boot(on)
  await bash(world, $, 'mentat check', 'WARN: short one\nCheck OK (1 warning(s))\n')
  const [short] = await checkItemsOf($)
  const heightOf = (source: string) => Number(/ height="(\d+)"/.exec(source)![1])
  await bash(world, $, 'mentat check', `WARN: ${LONG_WARN}\nCheck OK (1 warning(s))\n`)
  const [card] = await checkItemsOf($)
  const drawn = card!.drawn.join(' ')
  expect(drawn).toContain('(access controls not checked)')
  expect(drawn).not.toContain('…')
  expect(drawn.replace(/^.*Check passed with 1 warning /, '')).toBe(LONG_WARN)
  expect(heightOf(card!.source)).toBeGreaterThan(heightOf(short!.source))
  // The terminal Text is not cut.
  const term = await mount($, PANE, 'terminal', { bodyColumns: 60 })
  const line = (await term.findAll({ type: 'Text', text: LONG_WARN }))[0]
  expect(line).toBeDefined()
  expect(line!.props?.wrap).toBeUndefined()
  await term.unmount()
})

test('a long PROBLEM line is wrapped whole in the red alert on the desktop', async ($, on) => {
  const { world } = boot(on)
  await bash(world, $, 'mentat check', 'PROBLEM: short\nCheck failed: 1 problem(s)')
  const [short] = await alertsOf($)
  await bash(world, $, 'mentat check', `PROBLEM: ${LONG_PROBLEM}\nCheck failed: 1 problem(s)`)
  const [card] = await alertsOf($)
  const drawn = card!.drawn.join(' ')
  expect(drawn).toContain('list them')
  expect(drawn).not.toContain('…')
  expect(drawn.replace(/^.*Check failed: 1 problem\(s\) /, '')).toBe(LONG_PROBLEM)
  const heightOf = (source: string) => Number(/ height="(\d+)"/.exec(source)![1])
  expect(heightOf(card!.source)).toBeGreaterThan(heightOf(short!.source))
})

test('the agent cannot open a warning: open_decision refuses the kind and records nothing', async ($, on) => {
  boot(on)
  const refused = await eng($).tool.call({ tool: OPEN, kind: 'warning', question: 'Careful?' })
  expect(refused.deny).toBe('open_decision kind must be question, action or alert.')
  expect(await paneTexts($, 'terminal')).not.toContain('Careful?')
  expect((await bandTexts($)).length).toBe(0)
})

test('the band shows an alert, then a question, then the check warning, then a final-checked pull request, a budget warning and an action', async ($, on) => {
  const { world } = boot(on)
  world.usage = { context: 5, limits: [limit('five_hour', 95, RESET_5H())] }
  world.issueComments = ok(pages([finalCheck(H1)]))
  await follow109($)
  await open('action', 'Do the thing')($)
  await bash(world, $, 'mentat check', WARN_RUN)
  const none = (texts: string[], ...words: string[]) => expect(texts.some(x => words.some(w => x.includes(w)))).toBe(false)

  // The warning outranks the pull request, the budget and the action.
  for (const surface of SURFACES) {
    const { texts, alts } = await bandWith($, surface)
    expect(texts).toContain('Check passed with 2 warnings')
    none(texts, 'Final check', 'limit', 'Do the thing')
    expect(pillFor(texts)).toBe('2 items')
    if (surface === 'desktop') {
      expect(alts).toEqual(['Check warnings: Check passed with 2 warnings'])
      expect(texts).toContain('!')
    }
  }
  const term = await mount($, BAND, 'terminal')
  expect((await term.findAll({ type: 'Text', text: '!' }))[0]!.props?.color).toBe('warning')
  expect((await term.findAll({ type: 'Box' })).some(b => b.props?.backgroundColor !== undefined)).toBe(false)
  await term.unmount()
  const desk = await mount($, BAND, 'desktop')
  expect((await svgsOf(desk))[0]!.source).toContain(HUE_AMBER)
  await desk.unmount()

  // A question outranks the warning.
  await open(undefined, 'Ask first?')($)
  for (const surface of SURFACES) {
    const { texts } = await bandWith($, surface)
    expect(texts).toContain('Ask first?')
    none(texts, 'Check passed')
    expect(pillFor(texts)).toBe('3 items')
  }
  // An alert (the failed check replaces the warning) outranks the question.
  await bash(world, $, 'mentat check', FAILED_RUN)
  for (const surface of SURFACES) expect((await bandWith($, surface)).texts).toContain('Check failed: 2 problem(s)')

  // Back to the warning, then a clean pass: the question is gone too, so the pull request shows.
  await bash(world, $, 'mentat check', WARN_RUN)
  await eng($).tool.call({ tool: CLOSE, id: 'd2' })
  await bash(world, $, 'mentat check', CLEAN_RUN)
  for (const surface of SURFACES) {
    const { texts } = await bandWith($, surface)
    expect(texts).toContain(surface === 'terminal' ? '· Final check posted' : 'Final check posted')
    none(texts, 'Check passed', 'Do the thing')
  }
})

test('a new conversation drops the check result and its warning card, and a mod reload keeps them', async ($, on) => {
  const { world } = boot(on)
  const classic = ($ as never as { classic: { SessionStart: (a: { source: string }) => Promise<unknown> } }).classic
  await bash(world, $, 'mentat check', WARN_RUN)
  await startSession($)
  expect((await footerOf($, 'terminal'))[0]!.text).toBe('● Mentat · 2 warnings')
  expect((await checkItemsOf($)).length).toBe(1)
  await classic.SessionStart({ source: 'startup' })
  await classic.SessionStart({ source: 'compact' })
  expect((await footerOf($, 'terminal'))[0]!.text).toBe('● Mentat · 2 warnings')

  for (const source of ['clear', 'resume', 'fork']) {
    await bash(world, $, 'mentat check', FAILED_RUN)
    expect((await footerOf($, 'terminal'))[0]!.text).toBe('● Mentat check failed')
    await classic.SessionStart({ source })
    expect(await footerOf($, 'terminal')).toEqual([{ text: '● Mentat', color: undefined, dim: true }])
    expect(await alertsOf($)).toEqual([])
    expect(await checkItemsOf($)).toEqual([])
  }
})

test('Dismiss removes the check alert, and a later failed run pins it again', async ($, on) => {
  const { world } = boot(on)
  await bash(world, $, 'mentat check', FAILED_RUN)
  const d = await mount($, PANE, 'desktop', { bodyColumns: 60 })
  await d.press({ key: 'dismiss-check' })
  await d.unmount()
  expect(await alertsOf($)).toEqual([])
  expect((await bandTexts($)).length).toBe(0)

  await bash(world, $, 'mentat check', FAILED_RUN)
  expect((await alertsOf($)).length).toBe(1)
})

test('a subagent running mentat check changes nothing', async ($, on) => {
  const { world } = boot(on)
  await bash(world, $, 'mentat check', FAILED_RUN, { agentId: 'a1' })
  expect(await alertsOf($)).toEqual([])
  await bash(world, $, 'mentat check', FAILED_RUN)
  await bash(world, $, 'mentat check', 'Check OK (0 warning(s))', { agentId: 'a1' })
  expect((await alertsOf($)).length).toBe(1)
  expect(toastTexts(world)).toEqual([])
})

test('other Bash output is ignored: no mentat check command, no final line, or text that only looks like one', async ($, on) => {
  const { world } = boot(on)
  await bash(world, $, 'cat check.log', FAILED_RUN)
  await bash(world, $, 'echo mentat checkout', FAILED_RUN)
  await bash(world, $, 'mentat checks', FAILED_RUN)
  await bash(world, $, 'mentat check', 'PROBLEM: cut off by a pipe\n')
  await bash(world, $, 'mentat check', 'usage: mentat check\n')
  await bash(world, $, 'mentat check', 'Check failed: lots\nCheck OK soon')
  await bash(world, $, 'ls', 'Check OK (0 warning(s))')
  expect(await alertsOf($)).toEqual([])
  expect(toastTexts(world)).toEqual([])

  // A run whose output has both final lines says nothing certain either.
  await bash(world, $, 'mentat check', 'Check failed: 1 problem(s)\nCheck OK (0 warning(s))')
  expect(await alertsOf($)).toEqual([])
  expect(toastTexts(world)).toEqual([])
})

test('a long list of problems is cut to six lines, the last counting the rest, on both surfaces', async ($, on) => {
  const { world } = boot(on)
  const problems = Array.from({ length: 9 }, (_, i) => `problem number ${i + 1}`)
  await bash(world, $, 'mentat check', `${problems.map(p => `PROBLEM: ${p}`).join('\n')}\nCheck failed: 9 problem(s)`)
  const [card] = await alertsOf($)
  expect(card!.drawn).toEqual(expect.arrayContaining([...problems.slice(0, 5), '+4 more']))
  expect(card!.drawn).not.toContain('problem number 6')
  const t = await paneTexts($, 'terminal')
  expect(t).toEqual(expect.arrayContaining([...problems.slice(0, 5), '+4 more']))
  expect(t).not.toContain('problem number 6')
})

// ---- the Commands card -------------------------------------------------------------------

// The card is one Markdown element: a two-column table, a header row and one row per command.
const TABLE = [
  '| Command | Use |',
  '| --- | --- |',
  '| `/mentat` | open this pane |',
  '| `/mentat pr <n>` | follow a pull request |',
  '| `/mentat:come-again` | restate the last message |',
  '| `/mentat:retro` | look back at a session that went badly |',
  '| `/mentat:codex-review-off` | turn Codex reviews off for the session |',
  '| `/mentat:codex-review-on` | turn Codex reviews back on for the session |',
  '| `mentat check` | in a terminal: check what Mentat needs |',
].join('\n')
const toggleLabel = async (d: Drawing) =>
  (await d.findAll({ type: 'Button' })).filter(b => b.key === 'commands-toggle').map(b => String(b.text ?? b.props?.label ?? ''))
// The text of each Markdown element of the drawing.
const commandLines = async (d: Drawing) => (await d.findAll({ type: 'Markdown' })).map(m => String(m.props?.text ?? ''))

test('the Commands card starts collapsed on both surfaces: only the toggle shows, above the open items and beside the empty-pane line', async ($, on) => {
  boot(on)
  for (const surface of SURFACES) {
    const empty = await mount($, PANE, surface, { bodyColumns: 60 })
    expect(await toggleLabel(empty)).toEqual(['▸ Commands'])
    expect((await empty.findAll({ type: 'Button' })).map(b => b.key)).toEqual(['commands-toggle'])
    expect(await commandLines(empty)).toEqual([])
    expect((await textsOf(empty)).some(t => t.includes('/mentat'))).toBe(false)
    // Nothing else to show: the desktop keeps its line.
    expect((await textsOf(empty)).includes('Nothing waiting on you.')).toBe(surface === 'desktop')
    await empty.unmount()
  }
  await eng($).tool.call({ tool: OPEN, kind: 'alert', question: 'CI is red' })
  await eng($).tool.call({ tool: OPEN, question: 'Mock it?', accept: 'Yes' })
  for (const surface of SURFACES) {
    const pane = await mount($, PANE, surface, { bodyColumns: 60 })
    expect((await pane.findAll({ type: 'Button' })).map(b => b.key)).toEqual([
      'commands-toggle',
      'dismiss-d1',
      'accept-d2',
      'answer-open-d2',
      'dismiss-d2',
    ])
    expect(await textsOf(pane)).not.toContain('Nothing waiting on you.')
    await pane.unmount()
  }
})

test('pressing the toggle shows every command line, pressing again hides them, and the choice survives a remount', async ($, on) => {
  const { world } = boot(on)
  for (const surface of SURFACES) {
    const pane = await mount($, PANE, surface, { bodyColumns: 60 })
    await pane.press({ key: 'commands-toggle' })
    expect(await toggleLabel(pane)).toEqual(['▾ Commands'])
    expect(await commandLines(pane)).toEqual([TABLE])
    // No background tint on the card: nothing drawn behind the lines.
    const around = (await pane.findAll({ type: 'Box' })).filter(b => (b.text ?? '').includes('/mentat:retro') && !(b.text ?? '').includes('SESSION'))
    expect(around.length).toBeGreaterThan(0)
    expect(around.filter(b => b.props?.backgroundColor !== undefined)).toEqual([])
    // The toggle is the only Button, and pressing it ran no command.
    expect((await pane.findAll({ type: 'Button' })).map(b => b.key)).toEqual(['commands-toggle'])
    await pane.unmount()

    const again = await mount($, PANE, surface, { bodyColumns: 60 })
    expect(await toggleLabel(again)).toEqual(['▾ Commands'])
    expect(await commandLines(again)).toEqual([TABLE])
    await again.press({ key: 'commands-toggle' })
    expect(await toggleLabel(again)).toEqual(['▸ Commands'])
    expect(await commandLines(again)).toEqual([])
    await again.unmount()

    const last = await mount($, PANE, surface, { bodyColumns: 60 })
    expect(await toggleLabel(last)).toEqual(['▸ Commands'])
    await last.unmount()
  }
  expect(world.commands).toEqual([])
})

test('the card lists the commands the mod exports, and the pane never calls $.command.run', async ($, on) => {
  const { world } = boot(on)
  expect(COMMANDS.map(c => c.name)).toEqual(TABLE.split('\n').slice(2).map(r => r.split('`')[1]))
  for (const surface of SURFACES) {
    const pane = await mount($, PANE, surface, { bodyColumns: 60 })
    await pane.press({ key: 'commands-toggle' })
    for (const b of await pane.findAll({ type: 'Button' })) await pane.press({ key: String(b.key) })
    await pane.unmount()
  }
  expect(world.commands).toEqual([])
})

// ---- the Log card ---------------------------------------------------------------------------------

const GH = 'https://github.com/o/r'
// The log rows the pane draws (newest first), as time, icon and text, and the label of the toggle button, if any.
const logOf = async ($: never, surface: 'terminal' | 'desktop' = 'terminal') => {
  const pane = await mount($, PANE, surface, { bodyColumns: 60 })
  const t = await textsOf(pane)
  const toggle = (await pane.findAll({ type: 'Button' })).filter(b => b.key === 'log-toggle').map(b => String(b.props?.label))
  const hasSvg = (await pane.findAll({ type: 'Svg' })).length > 0
  await pane.unmount()
  const rows: { time: string; icon: string; text: string }[] = []
  for (let i = t.indexOf('LOG') + 1; i > 0 && i + 2 < t.length && /^\d+:\d\d [AP]M$/.test(t[i]!); i += 3) rows.push({ time: t[i]!, icon: t[i + 1]!, text: t[i + 2]! })

  return { rows, toggle, hasSvg }
}
const lines = async ($: never, surface: 'terminal' | 'desktop' = 'terminal') => (await logOf($, surface)).rows.map(r => `${r.icon} ${r.text}`)
// The agent adds a note.
const note = ($: never, text: string, kind?: string) => eng($).tool.call({ tool: NOTE, text, ...(kind === undefined ? {} : { kind }) })

test('the note tool is registered with a required text, the five kinds, and a description that says when to add one', async ($, on) => {
  const { world } = boot(on)
  await startSession($)
  const tool = world.tools.find(t => t.name === 'note')!
  expect(world.tools.map(t => t.name)).toEqual(['open_decision', 'close_decision', 'note'])
  expect(tool.inputSchema.required).toEqual(['text'])
  expect(Object.keys(tool.inputSchema.properties)).toEqual(['text', 'kind'])
  expect(tool.inputSchema.properties.kind.enum).toEqual(['decision', 'plan', 'surprise', 'waiting', 'done'])
  expect(tool.isDeferred).toBe(false)
  for (const phrase of ['notable moment', 'a decision the user made', 'a change of plan', 'something surprising', 'what you now wait on', 'a piece of work finished', 'A few notes an hour at most', 'never for routine steps']) {
    expect(tool.description).toContain(phrase)
  }
})

test('a note adds one entry with its time, kind icon and line; the kind defaults to plan; the tool acknowledges', async ($, on) => {
  boot(on)
  await startSession($)
  expect((await logOf($)).rows).toEqual([])
  const ack = await note($, 'Only the Log changes in this pull request')
  expect(ack).toEqual({ result: 'Noted.' })
  // 12:00 UTC is 8:00 AM in New York.
  expect((await logOf($)).rows).toEqual([{ time: '8:00 AM', icon: '▸', text: 'Only the Log changes in this pull request' }])
  await note($, 'Keep the band for #150', 'decision')
  await note($, 'The mod tests also read the old log', 'surprise')
  await note($, 'Waiting on your merge of #148', 'waiting')
  await note($, 'The Log card is built', 'done')
  await note($, 'Next: the rules', 'plan')
  expect(await lines($, 'desktop')).toEqual(['▸ Next: the rules', '✓ The Log card is built', '◌ Waiting on your merge of #148', '! The mod tests also read the old log', '◆ Keep the band for #150'])
})

test('each kind has its own icon and color on both surfaces', async ($, on) => {
  boot(on)
  await startSession($)
  const kinds = [['decision', '◆', 'suggestion'], ['plan', '▸', 'text'], ['surprise', '!', 'warning'], ['waiting', '◌', 'subtle'], ['done', '✓', 'success']] as const
  for (const [kind] of kinds) await note($, `A ${kind} note`, kind)
  for (const surface of SURFACES) {
    const pane = await mount($, PANE, surface, { bodyColumns: 60 })
    for (const [, icon, color] of kinds) {
      expect((await pane.findAll({ type: 'Text', text: icon })).map(t => t.props?.color)).toContain(color)
    }
    await pane.unmount()
  }
})

test('a note is one line of at most 80 characters, cut with an ellipsis', async ($, on) => {
  boot(on)
  await startSession($)
  await note($, `Moving the ${'very long '.repeat(20)}plan`)
  const [row] = (await logOf($)).rows
  expect([...row!.text]).toHaveLength(80)
  expect(row!.text.startsWith('Moving the very long very long')).toBe(true)
  expect(row!.text.endsWith('…')).toBe(true)
  // Exactly 80 characters is kept whole; runs of spaces and line breaks make one line.
  await note($, 'x'.repeat(80))
  expect([...(await logOf($)).rows[0]!.text]).toHaveLength(80)
  expect((await logOf($)).rows[0]!.text.endsWith('…')).toBe(false)
  await note($, 'two   words\nand a third line')
  expect((await lines($))[0]).toBe('▸ two words and a third line')
})

test('a note without text, or with a kind that is not one of the five, is refused and adds nothing', async ($, on) => {
  boot(on)
  await startSession($)
  expect((await eng($).tool.call({ tool: NOTE })).deny).toBe('note needs a line of text.')
  expect((await note($, '   \n ')).deny).toBe('note needs a line of text.')
  expect((await eng($).tool.call({ tool: NOTE, text: 42 })).deny).toBe('note needs a line of text.')
  expect((await note($, 'A line', 'question')).deny).toBe('note kind must be decision, plan, surprise, waiting, done.')
  expect(await lines($)).toEqual([])
})

test('the same note twice in a row is added once; the same line after another note, or with another kind, is added', async ($, on) => {
  boot(on)
  await startSession($)
  await note($, 'Waiting on you', 'waiting')
  await note($, 'Waiting on you', 'waiting')
  expect(await lines($)).toEqual(['◌ Waiting on you'])
  await note($, 'Waiting on you', 'plan')
  await note($, 'Waiting on you', 'waiting')
  expect(await lines($)).toEqual(['◌ Waiting on you', '▸ Waiting on you', '◌ Waiting on you'])
})

test('no mechanical event is logged: pull requests, issues, settled items, Codex commands, builders and a merge add nothing', async ($, on) => {
  const { world } = boot(on)
  await follow109($)
  await bash(world, $, 'gh pr create --title "feat(pane): add a log" --body x', `${GH}/pull/130\n`)
  await bash(world, $, 'gh pr ready 130', '', {}, '✓ Pull request o/r#130 is marked as "ready for review"\n')
  await bash(world, $, 'gh pr close 131', '', {}, '✓ Closed pull request o/r#131 (feat: try a thing)\n')
  await bash(world, $, 'gh issue create --title "Log the session" --body x', `${GH}/issues/129\n`)
  await bash(world, $, 'gh issue close 129', '', {}, '✓ Closed issue o/r#129 (Log the session)\n')
  const opened = await open(undefined, 'Merge the log card now?')($)
  await eng($).tool.call({ tool: CLOSE, id: /d\d+/.exec(String(opened.result))![0], outcome: 'Yes, merge' })
  await eng($).command.run({ command: 'mentat:codex-review-off', args: '' })
  await eng($).command.run({ command: 'mentat:codex-review-on', args: '' })
  world.agents = [{ id: 'b1', type: 'mentat:builder', description: 'Build the log', status: 'running' }]
  await eng($).agent.spawn(spawn('b1', 'Build the log', 'mentat:builder'))
  world.agents = [{ id: 'b1', type: 'mentat:builder', description: 'Build the log', status: 'completed' }]
  await eng($).turn.complete(turnDone('b1'))
  world.pr = ok(prJson({ state: 'MERGED' }))
  await bash(world, $, 'git push', '')
  const reads = prViews(world)
  await until(() => prViews(world) > reads, 'the read of the merged pull request')
  await new Promise(r => setTimeout(r, 30))
  expect(await lines($)).toEqual([])
  expect(await paneTexts($)).not.toContain('LOG')
  // The commands still ran as before.
  expect(world.commands).toEqual(['mentat:codex-review-off', 'mentat:codex-review-on'])
})

test('the log shows the newest five; Show all N shows the rest and Show fewer goes back, on both surfaces, and the choice is kept', async ($, on) => {
  boot(on)
  await startSession($)
  for (let i = 1; i <= 7; i++) await note($, `Note ${i}`)
  for (const surface of SURFACES) {
    const first = await logOf($, surface)
    expect(first.rows.map(r => r.text)).toEqual(['Note 7', 'Note 6', 'Note 5', 'Note 4', 'Note 3'])
    expect(first.toggle).toEqual(['Show all 7'])
  }
  for (const surface of SURFACES) {
    const pane = await mount($, PANE, surface, { bodyColumns: 60 })
    await pane.press({ key: 'log-toggle' })
    await pane.unmount()
    const all = await logOf($, surface)
    expect(all.rows).toHaveLength(7)
    expect(all.toggle).toEqual(['Show fewer'])
    // The choice survives a remount.
    const again = await mount($, PANE, surface, { bodyColumns: 60 })
    expect((await again.findAll({ type: 'Button' })).filter(b => b.key === 'log-toggle').map(b => String(b.props?.label))).toEqual(['Show fewer'])
    await again.press({ key: 'log-toggle' })
    await again.unmount()
    const fewer = await logOf($, surface)
    expect(fewer.rows).toHaveLength(5)
    expect(fewer.toggle).toEqual(['Show all 7'])
  }
})

test('with five entries or fewer there is no toggle; with none there is no Log card', async ($, on) => {
  boot(on)
  await startSession($)
  expect(await paneTexts($)).not.toContain('LOG')
  for (let i = 0; i < 5; i++) await note($, `Note ${i}`)
  const got = await logOf($)
  expect(got.rows).toHaveLength(5)
  expect(got.toggle).toEqual([])
})

test('the log keeps the last 200 entries', async ($, on) => {
  boot(on)
  await startSession($)
  for (let i = 0; i < 205; i++) await note($, `Note ${i}`)
  expect((await logOf($)).toggle).toEqual(['Show all 200'])
  const pane = await mount($, PANE, 'terminal', { bodyColumns: 60 })
  await pane.press({ key: 'log-toggle' })
  await pane.unmount()
  const rows = (await logOf($)).rows
  expect(rows).toHaveLength(200)
  expect(rows[0]!.text).toBe('Note 204')
  expect(rows[199]!.text).toBe('Note 5')
})

test('the time is the entry\'s clock time in the TZ zone, as h:mm AM or PM', async ($, on) => {
  const { clock } = boot(on, { zone: 'Asia/Kolkata' })
  await startSession($)
  await note($, 'First')
  await clock.advance(7 * 60_000)
  await note($, 'Second')
  // 12:00 UTC is 5:30 PM in Kolkata.
  expect((await logOf($)).rows.map(r => r.time)).toEqual(['5:37 PM', '5:30 PM'])
  // A two-digit evening hour and a one-digit morning hour: 5:37 PM + 4h35m is 10:12 PM, and 11 hours later 9:12 AM.
  // (The mock clock fires the pane's 1-second timer for every second, so it moves in steps.)
  const forward = async (minutes: number) => {
    for (let left = minutes; left > 0; left -= 20) await clock.advance(Math.min(left, 20) * 60_000)
  }
  await forward(4 * 60 + 35)
  await note($, 'Third')
  await forward(11 * 60)
  await note($, 'Fourth')
  expect((await logOf($)).rows.map(r => r.time)).toEqual(['9:12 AM', '10:12 PM', '5:37 PM', '5:30 PM'])
})

test('the log is plain text rows on both surfaces, with no Svg and no tint, and sits under the open items and above the agents', async ($, on) => {
  const { world } = boot(on)
  await startSession($)
  await eng($).tool.call({ tool: OPEN, question: 'Open one?' })
  await note($, 'A decision', 'decision')
  world.agents = [{ id: 'a1', type: 'Explore', description: 'Look around', status: 'running' }]
  await eng($).agent.spawn(spawn('a1', 'Look around', 'Explore'))
  for (const surface of SURFACES) {
    const pane = await mount($, PANE, surface, { bodyColumns: 60 })
    const t = await textsOf(pane)
    // On the terminal the Log rows sit between the question and the agent (the desktop draws those as Svg, which textsOf lists last).
    if (surface === 'terminal') {
      expect(t.indexOf('Open one?')).toBeLessThan(t.indexOf('LOG'))
      expect(t.indexOf('LOG')).toBeLessThan(t.indexOf('Look around'))
    }
    const rows = (await pane.findAll({ type: 'Box' })).filter(b => String(b.key).startsWith('log-'))
    expect(rows).toHaveLength(1)
    expect(rows.every(b => b.props?.backgroundColor === undefined)).toBe(true)
    await pane.unmount()
  }
  // On the desktop the log is not an Svg: the Svg elements are the question and the agents.
  const d = await mount($, PANE, 'desktop', { bodyColumns: 60 })
  expect((await svgsOf(d)).map(v => v.alt)).toEqual(['Question: Open one?', 'Running agents: 1'])
  await d.unmount()
})

test('on the terminal the log is under the pull request card; on the desktop there is no pull request card above it', async ($, on) => {
  const { world } = boot(on)
  await follow109($)
  await note($, 'A note')
  world.agents = [{ id: 'a1', type: 'Explore', description: 'Look around', status: 'running' }]
  await eng($).agent.spawn(spawn('a1', 'Look around', 'Explore'))
  const term = await paneTexts($, 'terminal')
  expect(term.indexOf('Label issues by kind')).toBeGreaterThan(-1)
  expect(term.indexOf('Label issues by kind')).toBeLessThan(term.indexOf('LOG'))
  expect(term.indexOf('LOG')).toBeLessThan(term.indexOf('Look around'))
  const desk = await paneTexts($, 'desktop')
  expect(desk).toContain('LOG')
  expect(desk).not.toContain('Label issues by kind')
  expect(desk).not.toContain('Nothing waiting on you.')
})

test('the desktop pane with only a note draws it and not the empty line', async ($, on) => {
  boot(on)
  await startSession($)
  expect(await paneTexts($, 'desktop')).toContain('Nothing waiting on you.')
  await note($, 'A first note')
  const t = await paneTexts($, 'desktop')
  expect(t).not.toContain('Nothing waiting on you.')
  expect(t).toContain('A first note')
})

test('a new conversation empties the log; a reload and a compaction keep it', async ($, on) => {
  boot(on)
  const classic = ($ as never as { classic: { SessionStart: (a: { source: string }) => Promise<unknown> } }).classic
  await startSession($)
  await note($, 'Before')
  await startSession($)
  await classic.SessionStart({ source: 'startup' })
  await classic.SessionStart({ source: 'compact' })
  expect(await lines($)).toEqual(['▸ Before'])
  for (const source of ['clear', 'resume', 'fork']) {
    await note($, `Second ${source}`)
    expect(await lines($)).toHaveLength(2)
    await classic.SessionStart({ source })
    expect(await lines($)).toEqual([])
    await note($, `After ${source}`)
    expect(await lines($)).toEqual([`▸ After ${source}`])
  }
})

test('the pane never calls $.command.run, whatever its buttons do', async ($, on) => {
  const { world } = boot(on)
  await startSession($)
  await note($, 'A note')
  await eng($).command.run({ command: 'mentat', args: 'pr 5' })
  await eng($).command.run({ command: 'mentat:come-again', args: '' })
  expect(await lines($)).toEqual(['▸ A note'])
  for (const surface of SURFACES) {
    const pane = await mount($, PANE, surface, { bodyColumns: 60 })
    for (const b of await pane.findAll({ type: 'Button' })) await pane.press({ key: String(b.key) })
    await pane.unmount()
  }
  expect(world.commands).toEqual(['mentat:come-again'])
})

test('no terminal Box has a backgroundColor: a terminal draws an 8-digit hex tint as opaque grey; the desktop keeps the answer field tint', async ($, on) => {
  const { world } = boot(on, { zone: 'America/New_York' })
  world.usage = { context: 41, limits: [{ kind: 'five_hour', percentUsed: 85, resetsAt: new Date(T0 + 3600_000).toISOString() }] }
  await follow109($)
  await eng($).tool.call({ tool: OPEN, question: 'Open one?' })
  await eng($).tool.call({ tool: OPEN, kind: 'action', question: 'Merge it' })
  await eng($).tool.call({ tool: OPEN, kind: 'alert', question: 'CI is red' })
  await note($, 'A note')
  world.agents = [{ id: 'a1', type: 'Explore', description: 'Look around', status: 'running' }]
  await eng($).agent.spawn(spawn('a1', 'Look around', 'Explore'))
  const opener = await mount($, PANE, 'terminal')
  await opener.press({ key: 'answer-open-d1' })
  await opener.unmount()
  for (const [spec, props] of [[PANE, { bodyColumns: 60 }], [BAND, {}]] as const) {
    const term = await mount($, spec, 'terminal', props)
    const boxes = await term.findAll({ type: 'Box' })
    expect(boxes.length).toBeGreaterThan(0)
    expect(boxes.filter(b => b.props?.backgroundColor !== undefined)).toEqual([])
    await term.unmount()
  }
  expect(await paneTexts($, 'terminal')).not.toContain('SESSION')
})

// ---- the check at session start -----------------------------------------------------

const GIT_YES = ok('true\n')
const nothingYet = async ($: never) => {
  // Waits for the startup run (if any) to have had its chance: a footer read after a few turns of the event loop.
  await new Promise(r => setTimeout(r, 50))
  return (await footerOf($, 'terminal'))[0]
}
const untilFooter = async ($: never, surface: 'terminal' | 'desktop', text: string, color: string | undefined) => {
  let last: unknown
  for (let i = 0; i < 300; i++) {
    last = (await footerOf($, surface))[0]
    const f = last as { text: string; color?: string }
    if (f.text === text && f.color === color) return
    await new Promise(r => setTimeout(r, 5))
  }
  throw new Error(`the footer never read ${text} (${color}); it read ${JSON.stringify(last)}`)
}

const failedExit = (stdout: string): Run => ({ exitCode: 1, stdout, stderr: '' })

test('a session start runs mentat check in the session directory, and a pass turns the label green with no card', async ($, on) => {
  const { world } = boot(on)
  world.git = GIT_YES
  world.check = ok(CLEAN_RUN)
  await startSession($)
  await until(() => world.cwds['mentat'] !== undefined, 'the startup check')
  expect(world.cwds['mentat']).toBe('/work/r')
  expect(world.cwds['git']).toBe('/work/r')
  await untilFooter($, 'terminal', '● Mentat', 'success')
  expect(await alertsOf($)).toEqual([])
  expect(await checkItemsOf($)).toEqual([])
})

test('a session start with warnings pins the warning card and turns the label amber', async ($, on) => {
  const { world } = boot(on)
  world.git = GIT_YES
  world.check = ok(WARN_RUN)
  await startSession($)
  await untilFooter($, 'terminal', '● Mentat · 2 warnings', 'warning')
  const cards = await checkItemsOf($)
  expect(cards.length).toBe(1)
  expect(cards[0]!.drawn).toContain('gh is old')
  expect(cards[0]!.drawn).toContain('codex is old')
})

test('a session start with a failing check (exit 1) pins the alert and turns the label red', async ($, on) => {
  const { world } = boot(on)
  world.git = GIT_YES
  world.check = failedExit('PROBLEM: gh is not logged in\nCheck failed: 1 problem(s)\n')
  await startSession($)
  await untilFooter($, 'terminal', '● Mentat check failed', 'error')
  const cards = await alertsOf($)
  expect(cards.length).toBe(1)
  expect(cards[0]!.alt).toBe('Alert: Check failed: 1 problem(s)')
  expect(cards[0]!.drawn).toContain('gh is not logged in')
})

test('outside a git work tree a session start runs no check', async ($, on) => {
  const { world } = boot(on)
  world.check = ok(CLEAN_RUN)
  // not a repository: git exits 128
  await startSession($)
  await until(() => world.calls.some(a => isCall(a, 'git', 'rev-parse')), 'the git probe')
  expect(await nothingYet($)).toEqual({ text: '● Mentat', color: undefined, dim: true })
  expect(world.calls.some(a => isCall(a, 'mentat', 'check'))).toBe(false)
  // inside a git directory that is not a work tree: git prints false
  world.git = ok('false\n')
  await startSession($)
  expect(await nothingYet($)).toEqual({ text: '● Mentat', color: undefined, dim: true })
  expect(world.calls.some(a => isCall(a, 'mentat', 'check'))).toBe(false)
})

test('a missing mentat leaves the label dim', async ($, on) => {
  const { world } = boot(on)
  world.git = GIT_YES
  await startSession($)
  await until(() => world.calls.some(a => isCall(a, 'mentat', 'check')), 'the startup check')
  expect(await nothingYet($)).toEqual({ text: '● Mentat', color: undefined, dim: true })
  expect(await alertsOf($)).toEqual([])
  // Output without a final line (a usage error) records nothing either.
  world.check = failedExit('usage: mentat check\n')
  await startSession($)
  expect(await nothingYet($)).toEqual({ text: '● Mentat', color: undefined, dim: true })
})

test('an agent run that lands while the startup run is in flight wins', async ($, on) => {
  const { world } = boot(on)
  world.git = GIT_YES
  let release: () => void = () => {}
  const gate = new Promise<void>(r => (release = r))
  world.check = async () => {
    await gate
    return failedExit('PROBLEM: stale\nCheck failed: 1 problem(s)\n')
  }
  await startSession($)
  await until(() => world.calls.some(a => isCall(a, 'mentat', 'check')), 'the startup check')
  await bash(world, $, 'mentat check', CLEAN_RUN)
  await untilFooter($, 'terminal', '● Mentat', 'success')
  release()
  expect(await nothingYet($)).toEqual({ text: '● Mentat', color: 'success', dim: false })
  expect(await alertsOf($)).toEqual([])
})

test('a startup run that lands first is replaced by a later agent run', async ($, on) => {
  const { world } = boot(on)
  world.git = GIT_YES
  world.check = failedExit('PROBLEM: gh is not logged in\nCheck failed: 1 problem(s)\n')
  await startSession($)
  await untilFooter($, 'terminal', '● Mentat check failed', 'error')
  await bash(world, $, 'mentat check', CLEAN_RUN)
  await untilFooter($, 'terminal', '● Mentat', 'success')
  expect(await alertsOf($)).toEqual([])
})

test('after /clear the label goes dim, then the new conversation is checked; a run of the old one writes nothing', async ($, on) => {
  const { world } = boot(on)
  world.git = GIT_YES
  const gates: (() => void)[] = []
  const results = [failedExit('PROBLEM: old\nCheck failed: 1 problem(s)\n'), ok(CLEAN_RUN)]
  let n = 0
  world.check = async () => {
    const mine = n++
    await new Promise<void>(r => gates.push(r))
    return results[mine]!
  }
  await startSession($)
  await until(() => gates.length === 1, 'the startup check')
  const classic = ($ as never as { classic: { SessionStart: (a: { source: string }) => Promise<unknown> } }).classic
  await classic.SessionStart({ source: 'clear' })
  await until(() => gates.length === 2, 'the check after /clear')
  expect(world.cwds['mentat']).toBe('/work/r')
  // the old conversation's run ends first and writes nothing
  gates[0]!()
  expect(await nothingYet($)).toEqual({ text: '● Mentat', color: undefined, dim: true })
  expect(await alertsOf($)).toEqual([])
  gates[1]!()
  await untilFooter($, 'terminal', '● Mentat', 'success')
  // /compact keeps the conversation: no new run
  await classic.SessionStart({ source: 'compact' })
  expect(await nothingYet($)).toEqual({ text: '● Mentat', color: 'success', dim: false })
  expect(world.calls.filter(a => isCall(a, 'mentat', 'check')).length).toBe(2)
})
