import { expect, mock, test } from 'claude-code/testing'

import { withoutSettled } from '../hooks/progress'

// Tests for hooks/progress.tsx. The test's hooks stand for the engine: `gh` is a
// table of canned answers (nothing talks to GitHub), `$.agent.list` and
// `$.session.usage` are tables too, and the clock moves only when a test moves it.

const OPEN = 'mcp__mentat__open_decision'
const CLOSE = 'mcp__mentat__close_decision'
const BAND = { plugin: 'mentat', component: 'AbovePrompt', props: { hasSurvey: false } }
const PANE = { plugin: 'mentat', component: 'Pane', requestId: 'mentat' }
const SURFACES = ['terminal', 'desktop'] as const

const T0 = Date.parse('2026-10-09T12:00:00Z')
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
  bash: string
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
  toasts: string[]
  // When set, $.session.usage() throws.
  usageFails: boolean
}

const isCall = (argv: string[], ...words: string[]) => words.every((w, i) => argv[i] === w)

// `band: false` leaves what the band draws beneath the plugin to the test.
const boot = (on: never, opts: { band?: boolean } = {}) => {
  const onFn = on as (event: string, ...rest: unknown[]) => void
  const clock = mock.clock(on, { now: T0 })
  const world: World = {
    repo: ok(`${REPO}\n`),
    pr: ok(prJson()),
    prList: ok('[]'),
    me: ok(`${ME}\n`),
    issueComments: ok(pages([])),
    pullComments: ok(pages([])),
    reviews: ok(pages([])),
    bash: '',
    agents: [],
    usage: { context: 12, limits: [] },
    calls: [],
    peak: 0,
    opened: [],
    sent: [],
    agentCallId: '',
    dropPrompts: false,
    toasts: [],
    usageFails: false,
  }
  let active = 0
  onFn('command.register', () => ({ value: { command: 'mentat' } }))
  onFn('tool.register', () => ({ value: { tool: 'x' } }))
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
    return { result: { stdout: world.bash, stderr: '' } }
  })
  onFn('classic.SessionStart', (_$: unknown, e: unknown) => e)
  onFn('tool.call', { tool: 'Agent' }, (_$: unknown, e: { tool_use_id: string }) => {
    world.agentCallId = e.tool_use_id
    return { result: {} }
  })
  onFn('prompt.submit', (_$: unknown, e: { text: string }) => {
    if (world.dropPrompts) return { drop: 'a turn is running' }
    world.sent.push(e.text)
    return { text: e.text }
  })
  onFn('ui.toast', (_$: unknown, e: { text?: string }) => {
    world.toasts.push(JSON.stringify(e))
    return { value: undefined }
  })
  onFn('process.run', async (_$: unknown, e: { argv: string[] }) => {
    const argv = [...e.argv]
    world.calls.push(argv)
    active += 1
    world.peak = Math.max(world.peak, active)
    try {
      let answer: Answer = { exitCode: 127, stdout: '', stderr: `unexpected: ${argv.join(' ')}` }
      if (isCall(argv, 'gh', 'repo', 'view')) answer = world.repo
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
    turn: { complete: (a: unknown) => Promise<unknown> }
  }
const startSession = ($: never) => eng($).session.start({ cwd: '/work/r', surface: 'terminal', isInteractive: true })
const bash = (w: World, $: never, command: string, stdout = '', extra: object = {}) => {
  w.bash = stdout

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

test('with a final-checked pull request the band keeps the pull request on the left, not a question', async ($, on) => {
  const { world } = boot(on)
  world.issueComments = ok(pages([finalCheck(H1)]))
  await follow109($)
  await eng($).tool.call({ tool: OPEN, question: 'A question too?' })
  const t = await bandTexts($)
  expect(t).toContain('· Final check posted')
  expect(t).toContain('1 question')
  expect(t).not.toContain('A question too?')
})

test('on the desktop the band and each card are one drawn Svg, found by alt text; the terminal draws text', async ($, on) => {
  const { world } = boot(on)
  world.issueComments = ok(pages([summary(H1), finalCheck(H1)]))
  world.pullComments = ok(pages([inline(1, H1)]))
  world.prList = ok(JSON.stringify([{ number: 109 }, { number: 7 }]))
  world.usage = { context: 41, limits: [{ kind: 'five_hour', percentUsed: 85, resetsAt: new Date(T0 + 3600_000).toISOString() }] }
  await follow109($)
  await eng($).tool.call({ tool: OPEN, question: 'Open it?', recommendation: 'Yes', accept: 'Yes' })
  const id = await callAgent(world, $, 'high')
  world.agents = [{ id, type: 'general-purpose', description: 'Check the docs', status: 'running' }]
  await eng($).agent.spawn(spawn(id))

  // Desktop band: the drawn row (the PR with its final check) and a native Details button.
  const band = await mount($, BAND, 'desktop')
  const bandSvg = await svgsOf(band)
  expect(bandSvg.map(v => v.alt)).toEqual(['#109 final check posted'])
  expect(bandSvg[0]!.drawn).toEqual(expect.arrayContaining(['#109', 'Label issues by kind', 'Final check posted', '1 question']))
  expect((await band.findAll({ type: 'Button' })).map(b => b.key)).toEqual(['open'])
  await band.unmount()

  // Desktop pane: session tiles, the question card, the PR card, the agents card.
  const pane = await mount($, PANE, 'desktop', { bodyColumns: 60 })
  const svgs = await svgsOf(pane)
  const alt = (prefix: string) => svgs.find(v => v.alt.startsWith(prefix))
  expect(svgs.map(v => v.alt)).toEqual([
    'Context 41%, 5-hour 85%',
    'Question: Open it?',
    '#109 Approval required',
    '1 agents',
  ])
  expect(alt('Context')!.drawn).toEqual(expect.arrayContaining(['CONTEXT', '41', '5-HOUR', '85', '1h 0m']))
  expect(alt('Question')!.drawn).toEqual(expect.arrayContaining(['Open it?', '→ Yes']))
  expect(alt('#109')!.drawn).toEqual(expect.arrayContaining(['#109', 'Label issues by kind', 'Approval required', 'CI passed', 'Codex · 1 finding · 0 replied · 415e6d9', '1 other open PR in this repository']))
  expect(alt('1 agents')!.drawn).toEqual(expect.arrayContaining(['Check the docs', 'general-purpose']))
  // The buttons stay native, under the question card.
  expect((await pane.findAll({ type: 'Button' })).map(b => b.key)).toEqual(['accept-d1', 'answer-open-d1', 'dismiss-d1'])
  await pane.unmount()

  // The terminal draws no Svg at all, only text.
  const tBand = await mount($, BAND, 'terminal')
  expect((await tBand.findAll({ type: 'Svg' })).length).toBe(0)
  expect(await textsOf(tBand)).toContain('· Final check posted')
  await tBand.unmount()
  const tPane = await mount($, PANE, 'terminal', { bodyColumns: 60 })
  expect((await tPane.findAll({ type: 'Svg' })).length).toBe(0)
  const t = await textsOf(tPane)
  for (const x of ['Open it?', 'Approval required', '✓', 'Check the docs', 'Context', '41%']) expect(t).toContain(x)
  expect(t.some(x => /[█░]/.test(x))).toBe(true)
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
  await eng($).tool.call({ tool: OPEN, question: 'Mock it?', recommendation: 'Yes', accept: 'Yes' })
  for (const surface of SURFACES) {
    world.sent.length = 0
    world.toasts.length = 0
    world.dropPrompts = true
    const pane = await mount($, PANE, surface)
    await pane.press({ key: 'accept-d1' })
    expect(world.sent).toEqual([])
    expect(world.toasts.length).toBe(1)
    expect(world.toasts[0]).toContain('Answer not sent')
    expect(world.toasts[0]).toContain('Press again')

    // A typed answer that was not taken keeps its field open.
    await pane.press({ key: 'answer-open-d1' })
    await pane.input({ key: 'answer-d1', text: 'maybe' })
    expect(world.toasts.length).toBe(2)
    expect((await pane.findAll({ type: 'Input' })).map(i => i.key)).toEqual(['answer-d1'])

    world.dropPrompts = false
    await pane.press({ key: 'accept-d1' })
    expect(world.sent).toEqual(['Answer to decision d1 ("Mock it?"): Yes'])
    expect(world.toasts.length).toBe(2)
    await pane.input({ key: 'answer-d1', text: 'maybe' })
    expect((await pane.findAll({ type: 'Input' })).length).toBe(0)
    await pane.unmount()
  }
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

  for (const surface of SURFACES) {
    const pane = await mount($, PANE, surface)
    await pane.press({ key: 'answer-open-d1' })
    await pane.input({ key: 'answer-d1', text: 'yes, for now' })
    await pane.unmount()
  }
  expect(world.sent).toEqual([
    'Answer to decision d1 ("Keep it?"): yes, for now',
    'Answer to decision d1 ("Keep it?"): yes, for now',
  ])
})

test('the accept button sends its label as the answer, the same path as typing', async ($, on) => {
  const { world } = boot(on)
  await eng($).tool.call({ tool: OPEN, question: 'Mock it?', recommendation: 'Yes', accept: 'Yes' })
  await eng($).tool.call({ tool: OPEN, question: 'No one-press answer?' })

  for (const surface of SURFACES) {
    const pane = await mount($, PANE, surface)
    const buttons = (await pane.findAll({ type: 'Button' })).map(b => b.key)
    expect(buttons).toContain('accept-d1')
    expect(buttons).not.toContain('accept-d2')
    await pane.press({ key: 'accept-d1' })
    await pane.unmount()
  }
  expect(world.sent).toEqual(['Answer to decision d1 ("Mock it?"): Yes', 'Answer to decision d1 ("Mock it?"): Yes'])
  // Sending an answer does not settle the question: the model closes it.
  expect((await bandTexts($)).includes('2 questions')).toBe(true)
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

test('the band shows both the final check and the question count', async ($, on) => {
  const { world } = boot(on)
  world.issueComments = ok(pages([finalCheck(H1)]))
  await follow109($)
  await eng($).tool.call({ tool: OPEN, question: 'One?' })
  await eng($).tool.call({ tool: OPEN, question: 'Two?' })
  const t = await bandTexts($)
  expect(t).toContain('2 questions')
  expect(t).toContain('· Final check posted')
})

test('a failed read of the pull request takes the final check off the band; a later good read puts it back', async ($, on) => {
  const { world, clock } = boot(on)
  world.issueComments = ok(pages([finalCheck(H1)]))
  await follow109($)
  await eng($).tool.call({ tool: OPEN, question: 'Still asked?' })
  expect(await bandTexts($)).toContain('· Final check posted')

  // The branch may have moved; the read that would show it failed. Questions still raise the band.
  world.pr = failed
  await clock.advance(60_000)
  await untilPane($, 'PR read failed (last ok 1m ago)')
  let t = await bandTexts($)
  expect(t.some(x => x.includes('Final check'))).toBe(false)
  expect(t).toContain('1 question')
  expect(await paneTexts($)).toContain('Approval required')

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

const rowFor = (t: string[], description: string) => {
  const i = t.indexOf(description)

  return i === -1 ? undefined : t[i + 1]
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

// ---- the session card and width --------------------------------------------------------------------------------

test('the session card shows context and the rate limits with percent and reset time', async ($, on) => {
  const { world } = boot(on)
  world.usage = {
    context: 41.6,
    limits: [
      { kind: 'five_hour', percentUsed: 12.2, resetsAt: new Date(T0 + 2 * 3600_000 + 10 * 60_000).toISOString() },
      { kind: 'seven_day', percentUsed: 88, resetsAt: new Date(T0 + 3 * 86400_000).toISOString() },
    ],
  }
  const t = await paneTexts($, 'terminal', 60)
  for (const x of ['Context', '5-hour', 'Week', '42%', '12%', '88%', 'resets in 2h 10m', 'resets in 3d']) expect(t).toContain(x)
})

test('below 48 columns reset times and secondary agent facts drop', async ($, on) => {
  const { world } = boot(on)
  world.usage = { context: 10, limits: [{ kind: 'five_hour', percentUsed: 12, resetsAt: new Date(T0 + 3600_000).toISOString() }] }
  await startSession($)
  const id = await callAgent(world, $, 'high')
  world.agents = [{ id, type: 'general-purpose', description: 'Narrow one', status: 'running' }]
  await eng($).agent.spawn(spawn(id, 'Narrow one'))
  await eng($).turn.complete(turnDone(id, { input_tokens: 1000, cache_creation_input_tokens: 0, output_tokens: 0, cache_read_input_tokens: 0, model: 'm' }))
  const wide = await paneTexts($, 'terminal', 60)
  expect(wide.some(x => x.startsWith('resets in'))).toBe(true)
  expect(rowFor(wide, 'Narrow one')).toContain('reported')
  const narrow = await paneTexts($, 'terminal', 40)
  expect(narrow.some(x => x.startsWith('resets in'))).toBe(false)
  expect(narrow).toContain('12%')
  const facts = rowFor(narrow, 'Narrow one') ?? ''
  expect(facts).not.toContain('reported')
  expect(facts).not.toContain('high')
  expect(facts).toContain('running')
})

test('meters are drawn as Svg on the desktop and as text elsewhere', async ($, on) => {
  boot(on)
  const desktop = await mount($, PANE, 'desktop', { bodyColumns: 60 })
  expect((await desktop.findAll({ type: 'Svg' })).length).toBeGreaterThan(0)
  await desktop.unmount()
  const terminal = await mount($, PANE, 'terminal', { bodyColumns: 60 })
  expect((await terminal.findAll({ type: 'Svg' })).length).toBe(0)
  expect((await textsOf(terminal)).some(t => /[█░]/.test(t))).toBe(true)
  await terminal.unmount()
})

test('no card is drawn for what there is not: no pull request, no agents, no questions', async ($, on) => {
  boot(on)
  const t = await paneTexts($)
  expect(t.some(x => x.toUpperCase().startsWith('AGENTS'))).toBe(false)
  expect(t).not.toContain('GitHub')
  expect(t.some(x => x.toLowerCase().includes('no ') && x.toLowerCase().includes('yet'))).toBe(false)
  expect(t).toContain('Context')
})

const RESET_5H = () => new Date(T0 + 3600_000 + 29 * 60_000).toISOString()
const RESET_WEEK = () => new Date(T0 + 6 * 86400_000).toISOString()
const limit = (kind: string, percentUsed: number, resetsAt?: string) => ({ kind, percentUsed, resetsAt })

test('/mentat opens the pane at once when there is something to show', async ($, on) => {
  const { world } = boot(on)
  await startSession($)
  await eng($).tool.call({ tool: OPEN, question: 'Anything?' })
  const ran = await eng($).command.run({ command: 'mentat', args: '' })
  expect(world.opened).toContain('mentat')
  expect(ran.text ?? '').not.toBe('')
})

test('/mentat with nothing but budget answers in one line and opens no pane', async ($, on) => {
  const { world } = boot(on)
  world.usage = { context: 10, limits: [limit('five_hour', 12, RESET_5H()), limit('seven_day', 8, RESET_WEEK())] }
  await startSession($)
  const ran = await eng($).command.run({ command: 'mentat', args: '' })
  expect(ran.text).toBe('Context 10% · 5-hour 12% (1h 29m) · Week 8% (6d)')
  expect(world.opened).toEqual([])
})

test('/mentat with nothing to show and no usage says so, and opens no pane', async ($, on) => {
  const { world } = boot(on)
  world.usage = { limits: [] }
  await startSession($)
  const ran = await eng($).command.run({ command: 'mentat', args: '' })
  expect(ran.text).toBe('Nothing waiting on you; session budget unavailable.')
  expect(world.opened).toEqual([])

  // The same when the engine cannot answer.
  world.usageFails = true
  const failed = await eng($).command.run({ command: 'mentat', args: '' })
  expect(failed.text).toBe('Nothing waiting on you; session budget unavailable.')
  expect(world.opened).toEqual([])
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
    expect(t).toContain('5-hour limit 80% · resets 1h 29m')
    // The row keeps its Details button.
    const d = await mount($, BAND, surface)
    expect((await d.findAll({ type: 'Button' })).length).toBe(1)
    await d.unmount()
  }

  world.usage = { context: 5, limits: [limit('five_hour', 40), limit('seven_day', 91, RESET_WEEK())] }
  expect(await bandTexts($)).toContain('Week limit 91% · resets 6d')

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

test('the answer field starts focused and sits in a full-width box tinted like the question card', async ($, on) => {
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
    expect(boxes[0]!.props?.backgroundColor).toBe('#d2992224')
    await pane.unmount()
  }
})

test('a long pull request title is wrapped whole on the desktop card, which grows to hold it', async ($, on) => {
  const { world } = boot(on)
  const title = 'feat: ' + 'make the pull request title long enough to need several lines of the card '.repeat(2).trim() + ' finale'
  expect(title.length).toBeGreaterThan(140)
  await follow109($)
  const heightOf = async () => {
    const pane = await mount($, PANE, 'desktop', { bodyColumns: 60 })
    const svg = (await pane.findAll({ type: 'Svg' })).find(x => String(x.props?.alt ?? '').startsWith('#109'))!
    const drawn = (await svgsOf(pane)).find(v => v.alt.startsWith('#109'))!.drawn
    await pane.unmount()

    return { height: Number(svg.props?.height), drawn }
  }
  const short = await heightOf()

  world.pr = ok(prJson({ title }))
  await bash(world, $, 'gh pr ready 109', '')
  for (let i = 0; i < 200 && !(await paneTexts($, 'desktop')).includes('Finale'); i++) await new Promise(r => setTimeout(r, 5))
  const long = await heightOf()
  const shown = long.drawn.filter(t => !/^(#109|CI|Codex|Approval|Merge|Draft)/.test(t) && !t.includes('open PR')).join(' ')
  expect(shown).toBe(title.replace(/^feat: /, '').replace(/^\w/, c => c.toUpperCase()))
  expect(shown).toContain('finale')
  expect(shown).not.toContain('…')
  expect(long.height).toBeGreaterThan(short.height)
})
