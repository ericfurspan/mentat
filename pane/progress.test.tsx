import { expect, mock, test } from 'claude-code/testing'

import { AGENT_HEAD_H, AGENT_ROW_H, isNote, resetAt, withoutSettled } from './progress'

// Tests for pane/progress.tsx. The test's hooks stand for the engine: `git` and `mentat check` are
// canned answers (nothing talks to GitHub), `$.agent.list` and `$.session.usage` are tables too, and the
// clock moves only when a test moves it.

const OPEN = 'mcp__mentat__open_decision'
const CLOSE = 'mcp__mentat__close_decision'
const NOTE = 'mcp__mentat__note'
const BAND = { plugin: 'mentat', component: 'AbovePrompt', props: { hasSurvey: false } }
const PANE = { plugin: 'mentat', component: 'Pane', requestId: 'mentat' }
// The terminal pane at a width that draws frames.
const TERM = { ...PANE, props: { bodyColumns: 80 } }
const SURFACES = ['terminal', 'desktop'] as const

const T0 = Date.parse('2026-10-09T12:00:00Z')
// The time zone reset times are shown in: the mod reads TZ, and every test sets it, so a weekly
// reset prints the same wherever the tests run.
const ZONE = 'America/New_York'

// ---- fixtures: what the commands print ---------------------------------------

type Run = { exitCode: number; stdout: string; stderr?: string }
type Answer = Run | (() => Run | Promise<Run>)
const ok = (stdout: string): Run => ({ exitCode: 0, stdout })

// ---- the world beneath the plugin -------------------------------------------

type Usage = { context?: number; limits?: { kind: string; percentUsed: number; resetsAt?: string }[] }
type World = {
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
  // How many times the plugin asked for a redraw ($.ui.invalidate).
  invalidations: number
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
    invalidations: 0,
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
  onFn('ui.invalidate', () => {
    world.invalidations += 1
    return { value: undefined }
  })
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
      }
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
// The keys of a drawing's buttons.
const cardKeys = async (d: Drawing) => (await d.findAll({ type: 'Button' })).map(b => b.key)
// The keys of the answer buttons and Dismiss buttons of a drawing (the desktop band's, or the terminal pane's).
const bandKeys = async (d: Drawing) => (await d.findAll({ type: 'Button' })).map(b => b.key).filter(k => /^(accept|dismiss)-/.test(String(k)))
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
// The band's own texts. On the terminal Mentat draws no band, so this is only what the engine draws there.
const bandTexts = async ($: never, surface: 'terminal' | 'desktop' = 'desktop') => {
  const d = await mount($, BAND, surface)
  const t = await textsOf(d)
  await d.unmount()

  return t
}
// Where each surface shows what waits on the maintainer, with its buttons: the desktop in its band, the
// terminal in the Waiting on you section of its pane.
const WAITS = { terminal: TERM, desktop: BAND } as const
// Where each surface shows a budget warning: the desktop in its band, the terminal at the top of its pane.
const budgetTexts = ($: never, surface: 'terminal' | 'desktop') => (surface === 'terminal' ? paneTexts($, 'terminal', 60) : bandTexts($, 'desktop'))
const mountWaits = ($: never, surface: 'terminal' | 'desktop') => mount($, WAITS[surface], surface)
const waitTexts = async ($: never, surface: 'terminal' | 'desktop') => {
  const d = await mountWaits($, surface)
  const t = await textsOf(d)
  await d.unmount()

  return t
}
const until = async (cond: () => boolean, what: string) => {
  for (let i = 0; i < 300; i++) {
    if (cond()) return
    await new Promise(r => setTimeout(r, 5))
  }
  throw new Error(`timed out waiting for ${what}`)
}

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

test('an opened question shows in the desktop band and in the terminal pane\'s Waiting on you, and closing it leaves the quiet line', async ($, on) => {
  boot(on)
  const opened = await eng($).tool.call({ tool: OPEN, question: 'Open the issue?', recommendation: 'yes' })
  expect(String(opened.result)).toContain('d1')

  // The terminal has no band of Mentat's.
  expect(await bandTexts($, 'terminal')).toEqual([])
  for (const surface of SURFACES) {
    const t = await waitTexts($, surface)
    expect(t).toContain('Open the issue?')
    expect(t.some(x => x.includes('more'))).toBe(false)
  }
  // The desktop pane has no card of its own for it; its Log holds only its `Asked you:` line.
  expect((await paneTexts($, 'desktop')).some(x => x === 'Open the issue?' || x.includes('→ yes'))).toBe(false)

  await eng($).tool.call({ tool: CLOSE, id: 'd1', outcome: 'opened' })
  expect(await bandTexts($, 'desktop')).toContain('Mentat')
  expect(await bandTexts($, 'desktop')).not.toContain('Open the issue?')
  const term = await paneTexts($, 'terminal')
  expect(term).not.toContain('Open the issue?')
  expect(term).not.toContain('WAITING ON YOU')
})

test('the terminal draws no band of Mentat\'s, whatever is open, near a limit or noted; what is beneath stays', async ($, on) => {
  const { world } = boot(on, { band: false })
  on('ui.render', ($, e) => {
    const { Text } = $.ui.resolve(e)
    return <Text>another plugin's band</Text>
  })
  world.usage = { context: 5, limits: [{ kind: 'five_hour', percentUsed: 95, resetsAt: new Date(T0 + 3600_000).toISOString() }] }
  await eng($).tool.call({ tool: NOTE, text: 'A note' })
  await eng($).tool.call({ tool: OPEN, question: 'Keep both?', accept: 'Yes' })
  const d = await mount($, BAND, 'terminal')
  expect(await textsOf(d)).toEqual(["another plugin's band"])
  expect((await d.findAll({ type: 'Button' })).length).toBe(0)
  await d.unmount()
  // The desktop band is there beside it.
  expect(await bandTexts($, 'desktop')).toContain('Keep both?')
  expect(await bandTexts($, 'desktop')).toContain("another plugin's band")
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
  expect(await waitTexts($, 'terminal')).toContain('Open before the load')
  expect(await bandTexts($)).toContain('Open before the load')
})

test('with only questions raising it, the band shows the newest question on the left, and the terminal pane lists all of them, newest first', async ($, on) => {
  boot(on)
  await eng($).tool.call({ tool: OPEN, question: 'First one?' })
  await eng($).tool.call({ tool: OPEN, question: 'Newest one?' })
  const t = await bandTexts($, 'desktop')
  expect(t).toContain('Newest one?')
  expect(t).not.toContain('First one?')
  expect(t).toContain('+1 more')
  const d = await mount($, BAND, 'desktop')
  expect((await d.findAll({ type: 'Button' })).map(b => b.key)).toContain('open')
  await d.unmount()

  const pane = await waitTexts($, 'terminal')
  expect(pane.indexOf('Newest one?')).toBeGreaterThan(-1)
  expect(pane.indexOf('Newest one?')).toBeLessThan(pane.indexOf('First one?'))
  expect(pane.some(x => x.includes('more'))).toBe(false)
})

test('on the desktop the band and the agents card are drawn Svgs, found by alt text; the terminal draws text', async ($, on) => {
  const { world } = boot(on)
  world.usage = { context: 41, limits: [{ kind: 'five_hour', percentUsed: 85, resetsAt: new Date(T0 + 3600_000).toISOString() }] }
  // Desktop band with nothing waiting: the budget warning is drawn, with a native Details button.
  const budgetBand = await mount($, BAND, 'desktop')
  const budgetSvg = await svgsOf(budgetBand)
  expect(budgetSvg.map(v => v.alt)).toEqual(['5-hour limit 85% · resets in 1h 0m'])
  expect((await budgetBand.findAll({ type: 'Button' })).map(b => b.key)).toEqual(['open'])
  await budgetBand.unmount()
  await eng($).tool.call({ tool: OPEN, question: 'Open it?', recommendation: 'Yes', accept: 'Yes' })
  const id = await callAgent(world, $, 'high')
  world.agents = [{ id, type: 'general-purpose', description: 'Check the docs', status: 'running' }]
  await eng($).agent.spawn(spawn(id))

  // Desktop band with the question open: it is the question that is drawn, with its answer button, Dismiss and Details.
  const band = await mount($, BAND, 'desktop')
  const bandSvg = await svgsOf(band)
  expect(bandSvg.map(v => v.alt)).toEqual(['Question: Open it?'])
  expect(bandSvg[0]!.drawn).toEqual(['?', 'Open it?'])
  expect((await band.findAll({ type: 'Button' })).map(b => b.key)).toEqual(['accept-d1', 'dismiss-d1', 'open'])
  await band.unmount()

  // Desktop pane: the agents card only; no question card, no PR card (the app has its own chip) and no usage tiles (its own popover shows those).
  const pane = await mount($, PANE, 'desktop', { bodyColumns: 60 })
  const svgs = await svgsOf(pane)
  const alt = (prefix: string) => svgs.find(v => v.alt.startsWith(prefix))
  expect(svgs.map(v => v.alt)).toEqual(['Running agents: 1 (general-purpose: Check the docs)'])
  expect(svgs.flatMap(v => v.drawn).some(x => /context|5-hour|%/i.test(x))).toBe(false)
  expect(alt('Running agents')!.drawn).toEqual(expect.arrayContaining(['Running · 1', 'Check the docs', 'Opus 4.8 · high']))
  expect(await cardKeys(pane)).toEqual([])
  await pane.unmount()

  // The terminal draws no Svg at all, only text, and no band: the question and the agent are in its pane.
  const tBand = await mount($, BAND, 'terminal')
  expect(await textsOf(tBand)).toEqual([])
  await tBand.unmount()
  const tPane = await mount($, TERM, 'terminal')
  expect((await tPane.findAll({ type: 'Svg' })).length).toBe(0)
  const t = await textsOf(tPane)
  expect(t).toContain('Check the docs')
  expect(t).toContain('Open it?')
  expect(t.some(x => /[█░]|Context/.test(x))).toBe(false)
  await tPane.unmount()
})

test('the desktop band says +N more only when more than one item waits', async ($, on) => {
  boot(on)
  await eng($).tool.call({ tool: OPEN, question: 'Only one?' })
  let band = await mount($, BAND, 'desktop')
  let drawn = (await svgsOf(band)).flatMap(v => v.drawn)
  expect(drawn).toContain('Only one?')
  expect(drawn.some(x => x.includes('more'))).toBe(false)
  await band.unmount()

  await eng($).tool.call({ tool: OPEN, question: 'And another?' })
  band = await mount($, BAND, 'desktop')
  drawn = (await svgsOf(band)).flatMap(v => v.drawn)
  expect(drawn).toContain('And another?')
  expect(drawn).toContain('+1 more')
  await band.unmount()
})

test('a new conversation (clear, resume, branch) drops the open questions too; a reload and a compaction keep them', async ($, on) => {
  boot(on)
  const classic = ($ as never as { classic: { SessionStart: (a: { source: string }) => Promise<unknown> } }).classic
  for (const source of ['clear', 'resume', 'fork']) {
    await eng($).tool.call({ tool: OPEN, question: `Asked before ${source}?` })
    await classic.SessionStart({ source })
    expect((await bandTexts($)).some(t => t.includes('Asked before'))).toBe(false)
    expect(await bandTexts($)).toContain('Mentat')
  }
  await eng($).tool.call({ tool: OPEN, question: 'Kept?' })
  await startSession($)
  await classic.SessionStart({ source: 'startup' })
  await classic.SessionStart({ source: 'compact' })
  expect(await bandTexts($)).toContain('Kept?')
})

test('an answer the conversation did not take raises a toast and can be sent again', async ($, on) => {
  const { world } = boot(on)
  for (const [i, surface] of SURFACES.entries()) {
    const id = `d${i + 1}`
    await eng($).tool.call({ tool: OPEN, question: 'Mock it?', recommendation: 'Yes', accept: 'Yes' })
    world.sent.length = 0
    world.toasts.length = 0
    world.dropPrompts = true
    const band = await mountWaits($, surface)
    await band.press({ key: `accept-${id}` })
    expect(world.sent).toEqual([])
    expect(world.toasts.length).toBe(1)
    expect(world.toasts[0]).toContain('Answer not sent')
    expect(world.toasts[0]).toContain('Press again')
    expect(await bandKeys(band)).toEqual([`accept-${id}`, `dismiss-${id}`])

    world.dropPrompts = false
    await band.press({ key: `accept-${id}` })
    expect(world.sent).toEqual([`Answer to decision ${id} ("Mock it?"): Yes`])
    expect(world.toasts.length).toBe(1)
    // Taken: the question shows it is sent, with no answer button.
    expect(await bandKeys(band)).toEqual([`dismiss-${id}`])
    expect(await textsOf(band)).toContain(DELIVERED_LINE)
    await band.unmount()
    await eng($).tool.call({ tool: CLOSE, id })
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
const SENT_LINE = 'Sent: Yes · queued'
const DELIVERED_LINE = 'Sent: Yes'

test('pressing the accept button again while the turn runs submits nothing more', async ($, on) => {
  const { world } = boot(on)
  const turn = held()
  world.promptGate = turn.gate
  await eng($).tool.call({ tool: OPEN, question: 'Mock it?', recommendation: 'Yes', accept: 'Yes' })
  const band = await mount($, TERM, 'terminal')
  // A press waits for its handler, which waits for the turn: press three times meanwhile,
  // the last two before the drawing could have changed.
  const presses = [band.press({ key: 'accept-d1' }), band.press({ key: 'accept-d1' }), band.press({ key: 'accept-d1' })]
  await new Promise(r => setTimeout(r, 20))
  turn.release()
  await Promise.all(presses)
  expect(world.sent).toEqual(['Answer to decision d1 ("Mock it?"): Yes'])
  await band.unmount()
})

test('after a press the question shows it is sent, with only Dismiss left, and the line changes once the answer is in', async ($, on) => {
  const { world } = boot(on)
  for (const [i, surface] of SURFACES.entries()) {
    const id = `d${i + 1}`
    const turn = held()
    world.promptGate = turn.gate
    await eng($).tool.call({ tool: OPEN, question: `Mock it ${id}?`, recommendation: 'Yes', accept: 'Yes' })
    const band = await mountWaits($, surface)
    expect((await textsOf(band)).some(t => t.startsWith('Sent:'))).toBe(false)
    const press = band.press({ key: `accept-${id}` })
    await new Promise(r => setTimeout(r, 20))
    // The press is still waiting for the turn.
    expect(world.sent).toEqual([])
    const shown = await textsOf(band)
    expect(shown).toContain(SENT_LINE)
    expect(shown.some(t => t.includes(`Mock it ${id}?`))).toBe(true)
    expect(await bandKeys(band)).toEqual([`dismiss-${id}`])
    turn.release()
    await press
    // The prompt entered the session: the line no longer says it waits.
    const after = await textsOf(band)
    expect(after).toContain(DELIVERED_LINE)
    expect(after).not.toContain(SENT_LINE)
    expect(await bandKeys(band)).toEqual([`dismiss-${id}`])
    await band.unmount()
    // The mark is in state, so a drawing made again shows it too.
    expect(await waitTexts($, surface)).toContain(DELIVERED_LINE)
    expect(world.sent).toEqual([`Answer to decision ${id} ("Mock it ${id}?"): Yes`])
    world.sent.length = 0
    await eng($).tool.call({ tool: CLOSE, id })
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
    const band = await mountWaits($, surface)
    const press = band.press({ key: `accept-${id}` })
    await new Promise(r => setTimeout(r, 20))
    expect(await textsOf(band)).toContain(SENT_LINE)
    expect(await sentIds($)).toEqual([id])
    turn.release()
    await press
    expect(await bandKeys(band)).toEqual([`accept-${id}`, `dismiss-${id}`])
    expect((await textsOf(band)).some(t => t.startsWith('Sent:'))).toBe(false)
    expect(world.toasts.at(-1)).toContain('Answer not sent')
    expect(await sentIds($)).toEqual([])
    await band.unmount()
    await eng($).tool.call({ tool: CLOSE, id })
  }
})

test('Dismiss on a sent question removes it and its sent entry, while the answer waits or after it is in', async ($, on) => {
  const { world } = boot(on)
  const sentIds = watchSent(on)
  for (const [i, surface] of SURFACES.entries()) {
    for (const [j, isPending] of [true, false].entries()) {
      const id = `d${i * 2 + j + 1}`
      const turn = held()
      world.promptGate = turn.gate
      await eng($).tool.call({ tool: OPEN, question: `Clear ${id}?`, accept: 'Yes' })
      const band = await mountWaits($, surface)
      const press = band.press({ key: `accept-${id}` })
      await new Promise(r => setTimeout(r, 20))
      if (!isPending) {
        turn.release()
        await press
      }
      expect(await sentIds($)).toEqual([id])
      await band.press({ key: `dismiss-${id}` })
      expect(await sentIds($)).toEqual([])
      // The item is gone (the Feed's `You dismissed:` line holds the text with a prefix).
      expect((await textsOf(band)).includes(`Clear ${id}?`)).toBe(false)
      if (isPending) {
        // The held submit ends later: it must not bring a mark back.
        turn.release()
        await press
        expect(await sentIds($)).toEqual([])
      }
      await band.unmount()
      expect(String((await eng($).tool.call({ tool: CLOSE, id })).result)).toContain(`Decision ${id} was already dismissed in the pane`)
    }
  }
})

test('a session start (restart or reload) forgets an answer still waiting for a turn and keeps a delivered one', async ($, on) => {
  const { world } = boot(on)
  const sentIds = watchSent(on)
  await eng($).tool.call({ tool: OPEN, question: 'Delivered?', accept: 'Yes' })
  const band = await mount($, TERM, 'terminal')
  await band.press({ key: 'accept-d1' })
  // The pane lists the newest question first; the delivered one is under it.
  await eng($).tool.call({ tool: OPEN, question: 'Waiting?', accept: 'Yes' })
  // The submit of d2 is lost with the old load: it ends in a rejection, after the restart.
  let lose: () => void = () => undefined
  world.promptGate = new Promise<void>((_, reject) => (lose = () => reject(new Error('the engine reloaded'))))
  const lost = band.press({ key: 'accept-d2' })
  await new Promise(r => setTimeout(r, 20))
  expect(await sentIds($)).toEqual(['d1', 'd2'])
  expect(await textsOf(band)).toContain(SENT_LINE)

  await startSession($)
  await new Promise(r => setTimeout(r, 20))
  expect(await sentIds($)).toEqual(['d1'])
  // The pane lists both: d2 (newest first) with its answer button again, d1 with only Dismiss.
  expect(await bandKeys(band)).toEqual(['accept-d2', 'dismiss-d2', 'dismiss-d1'])
  // The waiting one can be answered again.
  world.promptGate = undefined
  await band.press({ key: 'accept-d2' })
  expect(world.sent).toEqual(['Answer to decision d1 ("Delivered?"): Yes', 'Answer to decision d2 ("Waiting?"): Yes'])
  // The lost submit ends now; it neither throws nor takes back the new, delivered mark.
  lose()
  await lost
  expect(await sentIds($)).toEqual(['d1', 'd2'])
  // With d2 dismissed, the delivered d1 shows as sent.
  await band.press({ key: 'dismiss-d2' })
  expect(await textsOf(band)).toContain(DELIVERED_LINE)
  await band.unmount()
})

test('a submit the engine rejects is treated like a drop: a toast, and the buttons come back', async ($, on) => {
  const { world } = boot(on)
  const sentIds = watchSent(on)
  await eng($).tool.call({ tool: OPEN, question: 'Mock it?', accept: 'Yes' })
  const band = await mount($, TERM, 'terminal')
  world.rejectPrompts = true
  await band.press({ key: 'accept-d1' })
  expect(world.toasts.length).toBe(1)
  expect(world.toasts[0]).toContain('Answer not sent')
  expect(await sentIds($)).toEqual([])
  expect(await bandKeys(band)).toEqual(['accept-d1', 'dismiss-d1'])
  world.rejectPrompts = false
  await band.press({ key: 'accept-d1' })
  expect(world.sent).toEqual(['Answer to decision d1 ("Mock it?"): Yes'])
  await band.unmount()
})

test('closing a question, or a new conversation, forgets that it was sent', async ($, on) => {
  const { world } = boot(on)
  const sentIds = watchSent(on)
  // Each question is the newest when it is answered, so its button is the one the band shows.
  for (const [i, q] of ['One?', 'Two?', 'Three?'].entries()) {
    await eng($).tool.call({ tool: OPEN, question: q, accept: 'Yes' })
    const band = await mount($, TERM, 'terminal')
    await band.press({ key: `accept-d${i + 1}` })
    await band.unmount()
  }
  expect(world.sent.length).toBe(3)
  expect(await sentIds($)).toEqual(['d1', 'd2', 'd3'])
  await eng($).tool.call({ tool: CLOSE, id: 'd2' })
  expect(await sentIds($)).toEqual(['d1', 'd3'])
  // A new conversation drops the questions and their marks.
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
  expect(ran.deny).toBe('No open decision with id d99, and no record of it being dismissed or cleared.')
})

// ---- items that left without close_decision ----------------------------------------------------------

const newConversation = ($: never, source: string) =>
  ($ as never as { classic: { SessionStart: (a: { source: string }) => Promise<unknown> } }).classic.SessionStart({ source })

test('close_decision on an item dismissed in the band succeeds and names the time, on both surfaces', async ($, on) => {
  const { clock } = boot(on)
  for (const [i, surface] of SURFACES.entries()) {
    const id = `d${i + 1}`
    await eng($).tool.call({ tool: OPEN, question: `Drop ${id}?` })
    // The press is 5 minutes later than the time it was opened, so the time is the press's.
    await clock.advance(5 * 60_000)
    const band = await mountWaits($, surface)
    await band.press({ key: `dismiss-${id}` })
    await band.unmount()
    await clock.advance(60 * 60_000)
    const ran = await eng($).tool.call({ tool: CLOSE, id })
    expect(ran.deny).toBeUndefined()
    // T0 is 8:00 AM in the test's zone; the first press is at 8:05, the second at 9:10 plus 5 minutes.
    expect(ran.result).toBe(`Decision ${id} was already dismissed in the pane at ${i === 0 ? '8:05 AM' : '9:10 AM'}.`)
    // It stays answerable: the record is not used up.
    expect(String((await eng($).tool.call({ tool: CLOSE, id })).result)).toContain('already dismissed')
  }
})

test('Dismiss records an id that was open, once; close_decision of an id never opened still refuses', async ($, on) => {
  boot(on)
  await eng($).tool.call({ tool: OPEN, question: 'One?' })
  const band = await mount($, TERM, 'terminal')
  await band.press({ key: 'dismiss-d1' })
  await band.unmount()
  expect(String((await eng($).tool.call({ tool: CLOSE, id: 'd1' })).result)).toContain('already dismissed')
  expect((await eng($).tool.call({ tool: CLOSE, id: 'd2' })).deny).toContain('no record')
})

test('close_decision on items cleared by /clear, /resume or /branch succeeds and names how the conversation started', async ($, on) => {
  boot(on)
  const words = [['clear', '/clear'], ['resume', '/resume'], ['fork', '/branch']] as const
  for (const [i, [source, shown]] of words.entries()) {
    const id = `d${i + 1}`
    await eng($).tool.call({ tool: OPEN, question: `Asked before ${source}?` })
    await newConversation($, source)
    const ran = await eng($).tool.call({ tool: CLOSE, id })
    expect(ran.deny).toBeUndefined()
    expect(ran.result).toBe(`Decision ${id} was already cleared when a new conversation started (${shown}).`)
  }
  // Ids keep counting across the reset, and the older records stay.
  expect(String((await eng($).tool.call({ tool: OPEN, question: 'Next?' })).result)).toBe('Opened decision d4.')
  expect(String((await eng($).tool.call({ tool: CLOSE, id: 'd1' })).result)).toContain('(/clear)')
  expect(String((await eng($).tool.call({ tool: CLOSE, id: 'd4' })).result)).toBe('Closed decision d4.')
})

test('a startup or compaction keeps the open items and records nothing', async ($, on) => {
  boot(on)
  await eng($).tool.call({ tool: OPEN, question: 'Still here?' })
  await newConversation($, 'startup')
  await newConversation($, 'compact')
  expect(String((await eng($).tool.call({ tool: CLOSE, id: 'd1' })).result)).toBe('Closed decision d1.')
  expect((await eng($).tool.call({ tool: CLOSE, id: 'd1' })).deny).toContain('no record')
})

test('the record of items that left keeps the last 50, oldest dropped, and survives a reload of the pane', async ($, on) => {
  boot(on)
  for (let i = 1; i <= 52; i++) await eng($).tool.call({ tool: OPEN, question: `Question ${i}?` })
  // The band shows the newest item, so Dismiss takes d52, d51 ... d33 in turn; then /clear takes d1..d32.
  // That is 52 records in this order, so the first two (d52, d51) fall out of the 50 kept.
  const band = await mount($, TERM, 'terminal')
  for (let i = 52; i >= 33; i--) await band.press({ key: `dismiss-d${i}` })
  await band.unmount()
  await newConversation($, 'clear')
  await startSession($)
  const answer = async (id: string) => eng($).tool.call({ tool: CLOSE, id })
  expect((await answer('d52')).deny).toContain('no record')
  expect((await answer('d51')).deny).toContain('no record')
  expect(String((await answer('d50')).result)).toContain('already dismissed')
  expect(String((await answer('d33')).result)).toContain('already dismissed')
  expect(String((await answer('d32')).result)).toContain('already cleared')
  expect(String((await answer('d1')).result)).toContain('already cleared')
})

test('the record survives a reload of the pane (a session start) and is never drawn', async ($, on) => {
  boot(on)
  await eng($).tool.call({ tool: OPEN, question: 'Gone soon?' })
  const band = await mount($, TERM, 'terminal')
  await band.press({ key: 'dismiss-d1' })
  await band.unmount()
  await startSession($)
  await startSession($)
  expect(String((await eng($).tool.call({ tool: CLOSE, id: 'd1' })).result)).toBe('Decision d1 was already dismissed in the pane at 8:00 AM.')
  expect(await bandTexts($, 'desktop')).toEqual(['Mentat'])
  expect(await waitTexts($, 'terminal')).not.toContain('WAITING ON YOU')
  for (const surface of SURFACES) {
    // The record itself is never drawn; the Log's `You dismissed:` line is the only trace.
    expect((await paneTexts($, surface)).filter(t => t.includes('dismissed'))).toEqual(['You dismissed: Gone soon?'])
  }
})

test('a check alert replaced or removed by a later run is not recorded', async ($, on) => {
  const { world } = boot(on)
  await bash(world, $, 'mentat check', FAILED_RUN)
  await bash(world, $, 'mentat check', FAILED_RUN)
  await bash(world, $, 'mentat check', 'Check OK (0 warning(s))')
  expect((await eng($).tool.call({ tool: CLOSE, id: 'check' })).deny).toContain('no record')
})

test('the accept button sends its label as the answer, once; the desktop band offers it for the most urgent question', async ($, on) => {
  const { world } = boot(on)
  // d1 for the terminal pane and d2 for the desktop band; d3 has no one-press answer.
  await eng($).tool.call({ tool: OPEN, question: 'Mock it?', recommendation: 'Yes', accept: 'Yes' })
  const first = await mount($, TERM, 'terminal')
  expect(await bandKeys(first)).toEqual(['accept-d1', 'dismiss-d1'])
  await first.press({ key: 'accept-d1' })
  await first.unmount()
  await eng($).tool.call({ tool: OPEN, question: 'Mock it?', recommendation: 'Yes', accept: 'Yes' })
  const second = await mount($, BAND, 'desktop')
  expect(await bandKeys(second)).toEqual(['accept-d2', 'dismiss-d2'])
  await second.press({ key: 'accept-d2' })
  await second.unmount()
  expect(world.sent).toEqual(['Answer to decision d1 ("Mock it?"): Yes', 'Answer to decision d2 ("Mock it?"): Yes'])

  await eng($).tool.call({ tool: OPEN, question: 'No one-press answer?' })
  // The desktop band shows only the newest item, and counts the others.
  const band = await mount($, BAND, 'desktop')
  expect(await bandKeys(band)).toEqual(['dismiss-d3'])
  await band.unmount()
  // Sending an answer does not settle the question: the model closes it.
  expect(await bandTexts($, 'desktop')).toContain('+2 more')
  // The terminal pane lists all three; the two sent ones have only Dismiss.
  const pane = await mount($, TERM, 'terminal')
  expect(await bandKeys(pane)).toEqual(['dismiss-d3', 'dismiss-d2', 'dismiss-d1'])
  await pane.unmount()
})

test('every unsent question with an answer has its own answer button in the terminal pane, and no other kind has one', async ($, on) => {
  const { world } = boot(on)
  await eng($).tool.call({ tool: OPEN, question: 'First?', accept: 'Yes' })
  await eng($).tool.call({ tool: OPEN, question: 'Second?', accept: 'No' })
  await eng($).tool.call({ tool: OPEN, question: 'Third?' })
  await eng($).tool.call({ tool: OPEN, kind: 'action', question: 'An action', accept: 'Yes' })
  const pane = await mount($, TERM, 'terminal')
  // Most urgent first: the questions, newest first, then the action.
  expect(await bandKeys(pane)).toEqual(['dismiss-d3', 'accept-d2', 'dismiss-d2', 'accept-d1', 'dismiss-d1', 'dismiss-d4'])
  await pane.press({ key: 'accept-d1' })
  await pane.press({ key: 'accept-d2' })
  expect(world.sent).toEqual(['Answer to decision d1 ("First?"): Yes', 'Answer to decision d2 ("Second?"): No'])
  expect(await bandKeys(pane)).toEqual(['dismiss-d3', 'dismiss-d2', 'dismiss-d1', 'dismiss-d4'])
  await pane.unmount()
})

test('dismiss settles a question', async ($, on) => {
  boot(on)
  await eng($).tool.call({ tool: OPEN, question: 'Drop it?' })
  const band = await mount($, TERM, 'terminal')
  await band.press({ key: 'dismiss-d1' })
  await band.unmount()
  expect((await bandTexts($)).includes('Drop it?')).toBe(false)
  const again = await eng($).tool.call({ tool: CLOSE, id: 'd1' })
  expect(again.deny).toBeUndefined()
  expect(again.result).toBe('Decision d1 was already dismissed in the pane at 8:00 AM.')
})

test('two questions opened at once get different ids and both are kept', async ($, on) => {
  boot(on)
  const [a, b] = await Promise.all([
    eng($).tool.call({ tool: OPEN, question: 'First?' }),
    eng($).tool.call({ tool: OPEN, question: 'Second?' }),
  ])
  expect([a, b].map(r => String(r.result)).sort()).toEqual(['Opened decision d1.', 'Opened decision d2.'])
  expect(await bandTexts($)).toContain('+1 more')
})

test('an open question is kept however many come after it', async ($, on) => {
  boot(on)
  for (let i = 1; i <= 60; i++) {
    await eng($).tool.call({ tool: OPEN, question: `Question ${i}?` })
  }
  const closed = await eng($).tool.call({ tool: CLOSE, id: 'd1' })
  expect(String(closed.result)).toBe('Closed decision d1.')
})

test('the desktop band keeps what other plugins draw there, and stays out of a survey', async ($, on) => {
  boot(on, { band: false })
  on('ui.render', ($, e) => {
    const { Text } = $.ui.resolve(e)
    return <Text>another plugin's band</Text>
  })
  await eng($).tool.call({ tool: OPEN, question: 'Keep both?' })

  const shown = await bandTexts($, 'desktop')
  expect(shown).toContain('Keep both?')
  expect(shown).toContain("another plugin's band")
  const survey = await mount($, BAND, 'desktop', { hasSurvey: true })
  const surveyTexts = await textsOf(survey)
  expect(surveyTexts).not.toContain('Keep both?')
  expect(surveyTexts).toContain("another plugin's band")
  await survey.unmount()
  // On the terminal a survey draws only what is beneath too.
  const terminalSurvey = await mount($, BAND, 'terminal', { hasSurvey: true })
  expect(await textsOf(terminalSurvey)).toEqual(["another plugin's band"])
  await terminalSurvey.unmount()
})

test('with nothing to show the desktop band is a quiet Mentat line with Details; the terminal pane says nothing waits', async ($, on) => {
  boot(on)
  const d = await mount($, BAND, 'desktop')
  expect(await bandKeys(d)).toEqual([])
  expect((await d.findAll({ type: 'Button' })).map(b => b.key)).toEqual(['open'])
  expect(await textsOf(d)).toEqual(['Mentat'])
  expect((await svgsOf(d)).map(v => v.alt)).toEqual(['Mentat'])
  await d.unmount()
  const term = await mount($, TERM, 'terminal')
  expect(await textsOf(term)).toEqual(['Nothing waiting on you.'])
  expect((await term.findAll({ type: 'Button' })).length).toBe(0)
  await term.unmount()
})

test('Details in the desktop band opens the pane, in every state of the band; on the terminal the footer label does', async ($, on) => {
  const { world } = boot(on)
  const quiet = await mount($, BAND, 'desktop')
  await quiet.press({ key: 'open' })
  await quiet.unmount()
  expect(world.opened).toEqual(['mentat'])
  await eng($).tool.call({ tool: OPEN, question: 'Open it?' })
  world.opened.length = 0
  const band = await mount($, BAND, 'desktop')
  await band.press({ key: 'open' })
  await band.unmount()
  expect(world.opened).toContain('mentat')

  world.opened.length = 0
  const footer = await mount($, SESSION_MODE, 'terminal', { modes: [] })
  await footer.press({ key: 'mentat-open' })
  await footer.unmount()
  expect(world.opened).toEqual(['mentat'])
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

// The state text of an agent's line in the terminal Feed (`running · 1m 05s`): the Text after its description.
// undefined when the agent has no line there (an ended agent is not in the Feed).
const stateOf = (t: string[], description: string) => {
  const i = t.indexOf(description)

  return i === -1 ? undefined : t[i + 1]
}
const isEndedStatus = (status: string) => ['completed', 'failed', 'killed', 'unknown'].includes(status)

test('a live agent is pinned in the Feed with its state and elapsed time; when it ends it leaves the Feed, and the desktop freezes its time', async ($, on) => {
  const { world, clock } = boot(on)
  await startSession($)
  const id = await callAgent(world, $, 'high')
  world.agents = [{ id, type: 'general-purpose', description: 'Check the docs', status: 'running' }]
  await eng($).agent.spawn(spawn(id))
  await clock.advance(65_000)
  await new Promise(r => setTimeout(r, 30))
  expect(stateOf(await paneTexts($), 'Check the docs')).toBe('running · 1m 05s')
  await untilFacts($, 'desktop', 'Check the docs', 'Opus 4.8 · high')

  world.agents = [{ id, type: 'general-purpose', description: 'Check the docs', status: 'completed' }]
  await clock.advance(1_000)
  await new Promise(r => setTimeout(r, 30))
  // Ended: not in the Feed as an agent (its end is an event line), and the desktop shows the frozen time.
  const t = await paneTexts($)
  expect(stateOf(t, 'Check the docs')).toBeUndefined()
  expect(t).toContain('general-purpose finished: Check the docs · 1m 06s')
  await clock.advance(120_000)
  await new Promise(r => setTimeout(r, 30))
  expect(await untilFacts($, 'desktop', 'Check the docs', '1m 06s')).toContain('1m 06s')
})

test('a turn that completes is not the end of a waiting agent; the desktop shows the tokens last reported', async ($, on) => {
  const { world, clock } = boot(on)
  await startSession($)
  world.agents = [{ id: 'a1', type: 'Explore', description: 'Look around', status: 'waiting' }]
  await eng($).agent.spawn(spawn('a1', 'Look around', 'Explore'))
  await eng($).turn.complete(turnDone('a1', { input_tokens: 100, cache_creation_input_tokens: 400, output_tokens: 500, cache_read_input_tokens: 99999, model: 'm' }))
  await clock.advance(10_000)
  expect(stateOf(await paneTexts($), 'Look around')).toBe('waiting · 10s')
  expect(await untilFacts($, 'desktop', 'Look around', '1.0k tokens · 10s')).toContain('1.0k tokens · 10s')

  await eng($).turn.complete(turnDone('a1', { input_tokens: 1, cache_creation_input_tokens: 2, output_tokens: 12000, cache_read_input_tokens: 0, model: 'm' }))
  await clock.advance(114_000)
  expect(stateOf(await paneTexts($), 'Look around')).toBe('waiting · 2m 04s')
  expect(await untilFacts($, 'desktop', 'Look around', '12k tokens · 2m 04s')).toContain('12k tokens · 2m 04s')
})

test('every live agent status is shown as it is in the Feed, running and waiting first; ended agents are not there', async ($, on) => {
  const { world, clock } = boot(on)
  await startSession($)
  const statuses = ['completed', 'failed', 'killed', 'idle', 'pending', 'waiting', 'running']
  world.agents = statuses.map(s => ({ id: s, type: 'general-purpose', description: `Agent ${s}`, status: s }))
  for (const s of statuses) await eng($).agent.spawn(spawn(s, `Agent ${s}`))
  // The next check of the engine's list (once a second) brings the statuses in.
  await clock.advance(1_000)
  await new Promise(r => setTimeout(r, 30))
  const t = await paneTexts($)
  const order = t.filter(x => x.startsWith('Agent '))
  // Active ones first (the newest start first within them), then idle; ended ones are not listed.
  expect(order.slice(0, 3).sort()).toEqual(['Agent pending', 'Agent running', 'Agent waiting'])
  expect(order).toHaveLength(4)
  expect(order[3]).toBe('Agent idle')
  for (const s of ['running', 'waiting', 'idle', 'pending']) expect(stateOf(t, `Agent ${s}`)).toMatch(new RegExp(`^${s} · \\d+s$`))
  for (const s of ['completed', 'failed', 'killed']) expect(stateOf(t, `Agent ${s}`)).toBeUndefined()
})

test('after a reload the mod keeps what it knew, shows unknown agents without an elapsed time, and notices ends', async ($, on) => {
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
  // The known one ended (the Feed has its event line, with the time it took); the unseen one has no start, so no time.
  expect(stateOf(t, 'Known one')).toBeUndefined()
  expect(t).toContain('general-purpose finished: Known one · 30s')
  expect(stateOf(t, 'Unseen one')).toBe('running')
  const d = await untilFacts($, 'desktop', 'Known one', 'Opus 4.8')
  expect(d).toContain('Opus 4.8')
})

test('an agent that vanishes from the engine\'s list is ended, not finished: it leaves the Feed and the desktop says ended', async ($, on) => {
  const { world, clock } = boot(on)
  await startSession($)
  world.agents = [{ id: 'a1', type: 'general-purpose', description: 'Gone one', status: 'running' }]
  await eng($).agent.spawn(spawn('a1', 'Gone one'))
  await clock.advance(4_000)
  world.agents = []
  await clock.advance(1_000)
  await new Promise(r => setTimeout(r, 30))
  const t = await paneTexts($)
  expect(stateOf(t, 'Gone one')).toBeUndefined()
  // An unknown end writes no event line.
  expect(t.some(x => x.includes('finished: Gone one') || x.includes('stopped: Gone one'))).toBe(false)
  await untilRowsAre($, [{ description: 'Gone one', status: 'unknown' }])
})

// ---- the effort of each agent, and finished agents dimmed ---------------------------------------------------

test('a subagent\'s requests set the effort of its desktop row; the Agent call\'s effort shows until then; the terminal Feed does not show it', async ($, on) => {
  const { world } = boot(on)
  await startSession($)
  const id = await callAgent(world, $, 'low')
  world.agents = [{ id, type: 'general-purpose', description: 'Check the docs', status: 'running' }]
  await eng($).agent.spawn(spawn(id))
  expect(await untilFacts($, 'desktop', 'Check the docs', 'Opus 4.8 · low')).toContain('Opus 4.8 · low')

  await step($, id, 'high')
  await until(() => world.steps.length === 1, 'the step')
  expect(await untilFacts($, 'desktop', 'Check the docs', 'high')).toContain('Opus 4.8 · high')
  expect(stateOf(await paneTexts($, 'terminal'), 'Check the docs')).toBe('running · 0s')

  await step($, id, 'xhigh', 1)
  const t = await untilFacts($, 'desktop', 'Check the docs', 'xhigh')
  expect(t.join('|')).not.toMatch(/(^|[^x])high/)

  // A number is a budget.
  await step($, id, 8000, 2)
  expect(await untilFacts($, 'desktop', 'Check the docs', '8.0k budget')).toContain('Opus 4.8 · 8.0k budget')
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
  const t = await untilFacts($, 'desktop', 'Check the docs', 'high')
  expect(t).toContain('Opus 4.8 · high')
  expect(t.join('|')).not.toContain('max')
})

test('a request that comes before the agent\'s row is kept for the row', async ($, on) => {
  const { world } = boot(on)
  await startSession($)
  await step($, 'a1', 'xhigh')
  world.agents = [{ id: 'a1', type: 'general-purpose', description: 'Late row', status: 'running' }]
  await eng($).agent.spawn(spawn('a1', 'Late row'))
  expect(await untilFacts($, 'desktop', 'Late row', 'xhigh')).toContain('Opus 4.8 · xhigh')
})

test('an agent the mod never saw spawn takes the effort its requests used when the engine\'s list brings it in', async ($, on) => {
  const { world, clock } = boot(on)
  await startSession($)
  // z9 steps before it is listed, and a reload lists it.
  await step($, 'z9', 'xhigh')
  await until(() => world.steps.length === 1, 'the step')
  world.agents = [{ id: 'z9', type: 'Explore', description: 'Unseen one', status: 'running' }]
  await startSession($)
  expect(await untilFacts($, 'desktop', 'Unseen one', 'xhigh')).toContain('xhigh')
  // The terminal Feed lists it, without a model or effort.
  expect(stateOf(await paneTexts($, 'terminal'), 'Unseen one')).toBe('running')

  // y8 steps, and the engine's next check of its list (once a second, while an agent runs) brings it in.
  await step($, 'y8', 'low')
  await until(() => world.steps.length === 2, 'the step')
  world.agents = [...world.agents, { id: 'y8', type: 'Plan', description: 'Other one', status: 'running' }]
  await clock.advance(1_000)
  expect(await untilFacts($, 'desktop', 'Other one', 'low')).toContain('low')
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

test('finished agents are drawn dimmed on the desktop in the muted color; the terminal Feed lists only the running one, not dimmed', async ($, on) => {
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
  expect(agentsSvg.source).toMatch(/<text class="m"[^>]*font-size="12">Opus 4.8</)
  expect(agentsSvg.source).toMatch(/<text class="s"[^>]*font-size="12">Opus 4.8</)
  expect(agentsSvg.source).toMatch(/<text class="m"[^>]*text-anchor="end"/)
  expect(agentsSvg.source).toMatch(/<text class="s"[^>]*text-anchor="end"/)
  expect(agentsSvg.source).toContain('stroke="#')

  const terminal = await mount($, PANE, 'terminal', { bodyColumns: 60 })
  const texts = await terminal.findAll({ type: 'Text' })
  await terminal.unmount()
  const dim = (t: string) => texts.find(x => x.text === t)?.props?.dimColor
  expect(dim('Still going')).toBeFalsy()
  // Ended agents are not agent lines in the Feed: only their event lines (dim) say how they ended.
  expect(texts.some(x => x.text === 'Finished fine' || x.text === 'Finished badly')).toBe(false)
  expect(texts.find(x => x.text === 'general-purpose failed: Finished badly')?.props?.dimColor).toBe(true)
  // The state text is dim.
  expect(texts.find(x => /^running · /.test(x.text ?? ''))?.props?.dimColor).toBe(true)
})

// ---- the agents card: role icon, status on the right, running and finished groups ---------------------------

const HUES = { violet: '#8B5CF6', blue: '#3D7FE6', teal: '#1E9E9A', grey: '#8f8f8a', green: '#2F9461', red: '#D0453F' }
const agentSvgs = async (d: Drawing) => {
  const all = await svgsOf(d)

  return { live: all.find(v => v.alt.startsWith('Running agents')), done: all.find(v => v.alt.startsWith('Finished agents')) }
}
const toggleOf = async (d: Drawing) => (await d.findAll({ type: 'Button' })).find(b => b.key === 'finished-toggle')
// Waits for the desktop pane to list each agent in its group: Running (not ended) or Finished (ended).
const untilRowsAre = async ($: never, list: { description: string; status: string }[]) => {
  let alts: string[] = []
  for (let i = 0; i < 300; i++) {
    const d = await mount($, PANE, 'desktop', { bodyColumns: 60 })
    alts = (await svgsOf(d)).map(v => v.alt)
    await d.unmount()
    if (list.every(a => alts.some(x => x.startsWith(isEndedStatus(a.status) ? 'Finished agents' : 'Running agents') && x.includes(`: ${a.description}`)))) return
    await new Promise(r => setTimeout(r, 5))
  }
  throw new Error(`the rows never showed ${JSON.stringify(list)}; the desktop pane listed ${JSON.stringify(alts)}`)
}
// Puts agents in the world and waits for the engine's next check of its list to bring in their statuses.
const seedAgents = async (w: World, clock: { advance: (ms: number) => Promise<unknown> }, $: never, list: { id: string; type: string; description: string; status: string }[]) => {
  w.agents = list
  for (const a of list) await eng($).agent.spawn(spawn(a.id, a.description, a.type))
  await clock.advance(1_000)
  await untilRowsAre($, list)
}

test('each agent row has the icon of its role in the role color, no role name drawn, and the role in the alt text', async ($, on) => {
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
  // The glyph is drawn in the role's color.
  expect(count(new RegExp(`data-role="builder"[^>]*stroke="${HUES.violet}"`, 'g'))).toBe(2)
  expect(src).toMatch(new RegExp(`data-role="explore"[^>]*stroke="${HUES.blue}"`))
  expect(src).toMatch(new RegExp(`data-role="plan"[^>]*stroke="${HUES.teal}"`))
  expect(src).toMatch(new RegExp(`data-role="other"[^>]*stroke="${HUES.grey}"`))
  // The third row's icon is centered in its row: the header, then two rows above it.
  const cy = AGENT_HEAD_H + AGENT_ROW_H * 2 + AGENT_ROW_H / 2
  expect(src).toContain(`<g data-role="explore" transform="translate(${24 - 7.2} ${cy - 7.2}) scale(0.6)" fill="none" stroke="${HUES.blue}"`)
  // The role is not drawn as a word; the model and effort are, once per row, in the secondary color.
  expect(live!.drawn).not.toEqual(expect.arrayContaining(['builder']))
  expect(live!.drawn.filter(x => ['builder', 'explore', 'plan', 'general-purpose'].includes(x))).toEqual([])
  expect(live!.drawn.filter(x => x === 'Opus 4.8').length).toBe(5)
  // It stays in the alt text.
  expect(live!.alt).toBe('Running agents: 5 (builder: Build it; builder: Build more; explore: Look around; plan: Plan it; general-purpose: Do other things)')
})

test('an agent row is one line: icon, title, model and effort, then the stats and the status mark at the right', async ($, on) => {
  const { world, clock } = boot(on)
  await startSession($)
  const id = await callAgent(world, $, 'high')
  world.agents = [
    { id, type: 'builder', description: 'Check the docs', status: 'running' },
    { id: 'c1', type: 'Explore', description: 'Finished fine', status: 'completed' },
  ]
  await eng($).agent.spawn(spawn(id, 'Check the docs', 'builder'))
  await eng($).agent.spawn(spawn('c1', 'Finished fine', 'Explore'))
  await eng($).turn.complete(turnDone(id, { input_tokens: 1, cache_creation_input_tokens: 2, output_tokens: 12000, cache_read_input_tokens: 0, model: 'm' }))
  await clock.advance(65_000)
  await untilRowsAre($, [{ description: 'Finished fine', status: 'completed' }])
  const W = 60 * 8 - 24
  const d = await mount($, PANE, 'desktop', { bodyColumns: 60 })
  const { live, done } = await agentSvgs(d)
  await d.unmount()
  // The card is the header and one row high, not three lines.
  expect(AGENT_ROW_H).toBeLessThan(40)
  expect(Number(/height="(\d+)"/.exec(live!.source)![1])).toBeLessThan(AGENT_HEAD_H + AGENT_ROW_H + 10)
  const y = (re: RegExp) => Number(re.exec(live!.source)![1])
  const titleY = y(/<text class="t"[^>]* y="([\d.]+)"[^>]*>Check the docs</)
  const modelY = y(/<text class="s"[^>]* y="([\d.]+)"[^>]*>Opus 4.8 · high</)
  const statsY = y(/<text class="s"[^>]* y="([\d.]+)"[^>]*text-anchor="end"[^>]*>12k tokens · 1m 05s</)
  // All on one line: the baselines are within two pixels of each other.
  expect(Math.max(titleY, modelY, statsY) - Math.min(titleY, modelY, statsY)).toBeLessThanOrEqual(2)
  // Left to right: title, then the model and effort, then the stats, which end before the mark.
  const titleX = y(/<text class="t" x="([\d.]+)"[^>]*>Check the docs</)
  const modelX = y(/<text class="s" x="([\d.]+)"[^>]*>Opus 4.8 · high</)
  const statsX = y(/<text class="s" x="([\d.]+)"[^>]*text-anchor="end"[^>]*>12k/)
  expect(modelX).toBeGreaterThan(titleX)
  expect(modelX).toBeLessThan(statsX)
  expect(statsX).toBeLessThan(W - 26)
  expect(done!.source).toContain('>Finished fine</text>')
})

test('a long title is cut with an ellipsis on the desktop, keeping the model, the stats and the mark in the row', async ($, on) => {
  const { world, clock } = boot(on)
  await startSession($)
  const long = 'A very long agent description that goes on and on past the end of the row and then some more'
  await seedAgents(world, clock, $, [{ id: 'r1', type: 'builder', description: long, status: 'running' }])
  const W = 60 * 8 - 24
  const d = await mount($, PANE, 'desktop', { bodyColumns: 60 })
  const { live } = await agentSvgs(d)
  await d.unmount()
  const title = /<text class="t"[^>]*>([^<]*…)<\/text>/.exec(live!.source)![1]!
  expect(title.length).toBeLessThan(long.length)
  expect(long.startsWith(title.slice(0, -1))).toBe(true)
  const titleX = Number(/<text class="t" x="([\d.]+)"/.exec(live!.source)![1])
  const modelX = Number(/<text class="s" x="([\d.]+)"[^>]*>Opus 4.8</.exec(live!.source)![1])
  const statsX = Number(/<text class="s" x="([\d.]+)"[^>]*text-anchor="end"/.exec(live!.source)![1])
  // The cut title ends before the model, and the model before the stats.
  expect(modelX).toBeGreaterThan(titleX + 40)
  expect(modelX).toBeLessThan(statsX)
  expect(statsX).toBeLessThan(W - 26)
  // The alt text keeps the whole title.
  expect(live!.alt).toContain(long)
})

test('a terminal agent line is one line: role mark, bold truncating title, then its state and elapsed time dim; no background', async ($, on) => {
  const { world, clock } = boot(on)
  await startSession($)
  await seedAgents(world, clock, $, [
    { id: 'b1', type: 'builder', description: 'Build it', status: 'running' },
    { id: 'e1', type: 'Explore', description: 'Look around', status: 'waiting' },
    { id: 'c1', type: 'Explore', description: 'Finished fine', status: 'completed' },
  ])
  const t = await mount($, TERM, 'terminal')
  const texts = await t.findAll({ type: 'Text' })
  const boxes = await t.findAll({ type: 'Box' })
  await t.unmount()
  const build = texts.find(x => x.text === 'Build it')!
  expect(build.props?.wrap).toBe('truncate-end')
  expect(build.props?.bold).toBe(true)
  expect(boxes.some(b => b.props?.backgroundColor !== undefined)).toBe(false)
  // The line reads: role mark, title, state and elapsed time, between the side lines.
  const all = texts.map(x => x.text)
  const i = all.indexOf('Build it')
  expect(all.slice(i - 2, i + 3)).toEqual(['│ ', '◆', 'Build it', 'running · 1s', ' │'])
  const j = all.indexOf('Look around')
  expect(all.slice(j - 1, j + 2)).toEqual(['◎', 'Look around', 'waiting · 1s'])
  expect(texts.find(x => x.text === 'running · 1s')?.props?.dimColor).toBe(true)
  // The finished one has no line.
  expect(all).not.toContain('Finished fine')
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
  const iconX = Number(/<g data-role="other" transform="translate\(([\d.]+) /.exec(live!.source)![1])
  for (const x of [markX(live!.source, HUES.blue), markX(done!.source, HUES.green), markX(done!.source, HUES.red)]) {
    expect(x).toBeGreaterThan(titleX)
    expect(x).toBeGreaterThan(W - 40)
    expect(x).toBeLessThan(W)
  }
  // The unknown agent's ring is at the right too, and the icon is left of the title.
  expect(Number(/<circle cx="([\d.]+)"[^>]*class="m"/.exec(done!.source)![1])).toBeGreaterThan(W - 40)
  expect(iconX).toBeLessThan(titleX)
})

test('the desktop has a Running group and a Finished group, each headed with its count; the terminal Feed pins only the live agents', async ($, on) => {
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
  expect(texts).toEqual(expect.arrayContaining(['First running', 'Second running']))
  expect(texts).not.toContain('Finished fine')
  expect(texts.some(x => x.startsWith('Running') || x.startsWith('Finished'))).toBe(false)
  expect(await toggleOf(t)).toBeUndefined()
  await t.unmount()
})

test('the Finished button hides the finished rows and shows them again on the desktop; running rows stay; the terminal has no such button', async ($, on) => {
  const { world, clock } = boot(on)
  await startSession($)
  await seedAgents(world, clock, $, [
    { id: 'r1', type: 'Explore', description: 'Still going', status: 'running' },
    { id: 'c1', type: 'builder', description: 'Finished fine', status: 'completed' },
    { id: 'f1', type: 'builder', description: 'Finished badly', status: 'failed' },
  ])
  let d = await mount($, PANE, 'desktop', { bodyColumns: 60 })
  const shown = async () => await textsOf(d)
  expect(await shown()).toEqual(expect.arrayContaining(['Still going', 'Finished fine', 'Finished badly']))

  await d.press({ key: 'finished-toggle' })
  let t = await shown()
  expect(t).toContain('Still going')
  expect(t).not.toContain('Finished fine')
  expect(t).not.toContain('Finished badly')
  expect((await toggleOf(d))!.props?.label).toBe('▸ Finished · 2')
  expect((await agentSvgs(d)).done).toBeUndefined()

  // The choice is kept for the next drawing of the pane.
  await d.unmount()
  d = await mount($, PANE, 'desktop', { bodyColumns: 60 })
  expect(await shown()).not.toContain('Finished fine')

  await d.press({ key: 'finished-toggle' })
  t = await shown()
  expect(t).toEqual(expect.arrayContaining(['Still going', 'Finished fine', 'Finished badly']))
  expect((await toggleOf(d))!.props?.label).toBe('▾ Finished · 2')
  await d.unmount()

  const term = await mount($, PANE, 'terminal', { bodyColumns: 60 })
  expect(await toggleOf(term)).toBeUndefined()
  expect(await textsOf(term)).toContain('Still going')
  await term.unmount()
})

test('a group with no rows is not drawn: no Finished button when none finished, no Running header when none run', async ($, on) => {
  const { world, clock } = boot(on)
  await startSession($)
  await seedAgents(world, clock, $, [{ id: 'r1', type: 'Explore', description: 'Only running', status: 'running' }])
  const d = await mount($, PANE, 'desktop', { bodyColumns: 60 })
  expect(await toggleOf(d)).toBeUndefined()
  const t = await textsOf(d)
  expect(t).toContain('Only running')
  expect(t.some(x => x.startsWith('Finished'))).toBe(false)
  expect((await agentSvgs(d)).done).toBeUndefined()
  await d.unmount()

  world.agents = [{ id: 'r1', type: 'Explore', description: 'Only running', status: 'completed' }]
  await clock.advance(1_000)
  await untilRowsAre($, [{ description: 'Only running', status: 'completed' }])
  const e = await mount($, PANE, 'desktop', { bodyColumns: 60 })
  expect((await toggleOf(e))!.props?.label).toBe('▾ Finished · 1')
  const u = await textsOf(e)
  expect(u).toContain('Only running')
  expect(u.some(x => x.startsWith('Running'))).toBe(false)
  expect((await agentSvgs(e)).live).toBeUndefined()
  await e.unmount()
  // The terminal Feed has no agent line for it, only the event line of its end.
  const term = await paneTexts($, 'terminal')
  expect(term).not.toContain('Only running')
  expect(term.some(x => x.includes('finished: Only running'))).toBe(true)
})

test('the row has the tokens and the elapsed time at the right, and leaves out what is missing', async ($, on) => {
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
  // An agent with neither has no stats at all.
  expect(stats.length).toBe(2)
  expect(live!.source).toMatch(/text-anchor="end"/)
})

// ---- the session card and width --------------------------------------------------------------------------------

test('an agent line leaves out its elapsed time when the start is not known, and keeps the true state word', async ($, on) => {
  const { world, clock } = boot(on)
  await startSession($)
  world.agents = [
    { id: 'z1', type: 'Explore', description: 'Never spawned here', status: 'idle' },
    { id: 'z2', type: 'Plan', description: 'Pending one', status: 'pending' },
  ]
  // The engine lists them at a (re)load; this mod never saw them spawn, so it has no start time for them.
  await startSession($)
  await clock.advance(5_000)
  const t = await paneTexts($, 'terminal')
  expect(stateOf(t, 'Never spawned here')).toBe('idle')
  expect(stateOf(t, 'Pending one')).toBe('pending')
  expect(t[t.indexOf('Pending one') - 1]).toBe('◇')
  expect(t[t.indexOf('Never spawned here') - 1]).toBe('◎')
})

test('the pane shows no usage meters on either surface: no tiles, no bars; the terminal pane carries the budget warning line', async ($, on) => {
  const { world } = boot(on)
  world.usage = { context: 41, limits: [limit('five_hour', 85, RESET_5H()), limit('seven_day', 8, RESET_WEEK())] }
  const usage = /context|session|week|[█░]/i
  const desktop = await mount($, PANE, 'desktop', { bodyColumns: 60 })
  expect((await desktop.findAll({ type: 'Svg' })).length).toBe(0)
  expect((await textsOf(desktop)).some(t => usage.test(t) || /5-hour|resets|%/.test(t))).toBe(false)
  await desktop.unmount()
  // The terminal has no band, so its pane warns at 80%, in one line, and shows nothing else of usage.
  const empty = await mount($, PANE, 'terminal', { bodyColumns: 60 })
  expect((await empty.findAll({ type: 'Svg' })).length).toBe(0)
  const texts = await textsOf(empty)
  expect(texts).toContain('5-hour limit 85% · resets in 1h 29m')
  expect(texts.filter(t => /limit|resets|%/.test(t))).toEqual(['5-hour limit 85% · resets in 1h 29m'])
  expect(texts.some(t => usage.test(t))).toBe(false)
  const line = (await empty.findAll({ type: 'Text', text: '5-hour limit 85% · resets in 1h 29m' }))[0]!
  expect(line.props?.color).toBe('warning')
  await empty.unmount()
  // With something to show, still no meters; the desktop draws only its own cards.
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

test('no card is drawn for what there is not: no agents, no questions', async ($, on) => {
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

test('/mentat with nothing else to show opens the pane, so the Details button always has something to open', async ($, on) => {
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

test('/mentat opens the pane for an open question or an agent row', async ($, on) => {
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

// ---- the band for budget ------------------------------------------------------------

test('a rate limit at 80 shows in the desktop band and at the top of the terminal pane, and not at 79', async ($, on) => {
  const { world } = boot(on)
  world.usage = { context: 5, limits: [limit('five_hour', 79, RESET_5H()), limit('seven_day', 10)] }
  for (const surface of SURFACES) expect((await budgetTexts($, surface)).some(t => t.includes('limit'))).toBe(false)

  world.usage = { context: 5, limits: [limit('five_hour', 80, RESET_5H()), limit('seven_day', 10)] }
  for (const surface of SURFACES) expect(await budgetTexts($, surface)).toContain('5-hour limit 80% · resets in 1h 29m')
  // The desktop band keeps its Details button; the terminal pane has no button at all.
  const d = await mount($, BAND, 'desktop')
  expect((await d.findAll({ type: 'Button' })).map(b => b.key)).toEqual(['open'])
  await d.unmount()
  const t = await mount($, TERM, 'terminal')
  expect((await t.findAll({ type: 'Button' })).length).toBe(0)
  await t.unmount()

  world.usage = { context: 5, limits: [limit('five_hour', 40), limit('seven_day', 91, RESET_WEEK())] }
  for (const surface of SURFACES) expect(await budgetTexts($, surface)).toContain('Week limit 91% · resets Thu 7:00 PM')

  // Both over: the higher one.
  world.usage = { context: 5, limits: [limit('five_hour', 84), limit('seven_day', 91)] }
  for (const surface of SURFACES) {
    const both = await budgetTexts($, surface)
    expect(both).toContain('Week limit 91%')
    expect(both.some(x => x.includes('5-hour'))).toBe(false)
  }
})

test('the context meter alone does not raise a warning, and a failed usage read means none: the quiet line stays', async ($, on) => {
  const { world } = boot(on)
  world.usage = { context: 90, limits: [limit('five_hour', 12), limit('seven_day', 8)] }
  expect(await bandTexts($, 'desktop')).toEqual(['Mentat'])
  expect(await paneTexts($, 'terminal')).toEqual(['Nothing waiting on you.'])

  world.usageFails = true
  expect(await bandTexts($, 'desktop')).toEqual(['Mentat'])
  expect(await paneTexts($, 'terminal')).toEqual(['Nothing waiting on you.'])
})

test('a budget warning keeps its Details button on the desktop, and shows above the agents in the terminal pane', async ($, on) => {
  const { world } = boot(on)
  world.usage = { context: 5, limits: [limit('five_hour', 90, RESET_5H())] }
  const id = await callAgent(world, $, 'high')
  world.agents = [{ id, type: 'general-purpose', description: 'Working', status: 'running' }]
  await eng($).agent.spawn(spawn(id, 'Working'))
  const d = await mount($, BAND, 'desktop')
  expect((await d.findAll({ type: 'Button' })).map(b => b.key)).toEqual(['open'])
  await d.unmount()
  const t = await paneTexts($, 'terminal')
  expect(t.indexOf('5-hour limit 90% · resets in 1h 29m')).toBe(0)
  expect(t).toContain('Working')
})

test('the pane with nothing to show says so in one line, with no buttons, on both surfaces', async ($, on) => {
  boot(on)
  for (const surface of SURFACES) {
    const empty = await mount($, PANE, surface, { bodyColumns: 60 })
    expect(await textsOf(empty)).toEqual(['Nothing waiting on you.'])
    expect((await empty.findAll({ type: 'Svg' })).length).toBe(0)
    expect(await cardKeys(empty)).toEqual([])
    await empty.unmount()
  }

  // Something open: the line goes.
  await eng($).tool.call({ tool: OPEN, question: 'Anything?' })
  for (const surface of SURFACES) {
    const busy = await mount($, PANE, surface, { bodyColumns: 60 })
    expect(await textsOf(busy)).not.toContain('Nothing waiting on you.')
    await busy.unmount()
  }
})

test('the weekly reset prints as weekday and local time in the warning; the 5-hour one stays a countdown', async ($, on) => {
  const { world } = boot(on)
  world.usage = { context: 10, limits: [limit('five_hour', 12, RESET_5H()), limit('seven_day', 91, RESET_WEEK())] }
  for (const surface of SURFACES) expect(await budgetTexts($, surface)).toContain('Week limit 91% · resets Thu 7:00 PM')

  // The 5-hour limit alone keeps its countdown.
  world.usage = { context: 10, limits: [limit('five_hour', 90, RESET_5H()), limit('seven_day', 8, RESET_WEEK())] }
  for (const surface of SURFACES) expect(await budgetTexts($, surface)).toContain('5-hour limit 90% · resets in 1h 29m')
})

test('the weekly reset follows TZ', async ($, on) => {
  const { world } = boot(on, { zone: 'Asia/Kolkata' })
  world.usage = { context: 10, limits: [limit('seven_day', 91, RESET_WEEK())] }
  // 23:00Z is 4:30 AM the next day in India (UTC+5:30).
  for (const surface of SURFACES) expect(await budgetTexts($, surface)).toContain('Week limit 91% · resets Fri 4:30 AM')
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

test('an item that waits comes before the budget warning in the desktop band, and the budget returns when it is closed; the terminal pane shows both', async ($, on) => {
  const { world } = boot(on)
  world.usage = { context: 5, limits: [limit('five_hour', 95, RESET_5H())] }
  await startSession($)
  await eng($).tool.call({ tool: OPEN, question: 'Ask first?' })
  const band = await bandTexts($, 'desktop')
  expect(band.some(x => x.includes('limit'))).toBe(false)
  expect(band).toContain('Ask first?')
  // The terminal has no band to give way: its pane has the warning line above the section.
  const pane = await paneTexts($, 'terminal')
  expect(pane).toContain('Ask first?')
  expect(pane.indexOf('5-hour limit 95% · resets in 1h 29m')).toBe(0)
  await eng($).tool.call({ tool: CLOSE, id: 'd1' })
  expect((await bandTexts($, 'desktop')).some(x => x.includes('limit'))).toBe(true)
})

test('an idle session whose usage crosses 80% shows the budget line after a minute tick, with no other change', async ($, on) => {
  const { world, clock } = boot(on)
  world.usage = { context: 5, limits: [limit('five_hour', 50, RESET_5H())] }
  await startSession($)
  const pane = await mount($, TERM, 'terminal')
  expect((await textsOf(pane)).some(t => t.includes('limit'))).toBe(false)
  // The usage rises; nothing else happens in the session.
  world.usage = { context: 5, limits: [limit('five_hour', 85, RESET_5H())] }
  const before = world.invalidations
  await clock.advance(59_000)
  expect(world.invalidations).toBe(before)
  await clock.advance(1_000)
  expect(world.invalidations).toBeGreaterThan(before)
  // The redraw asked for reads the usage again.
  await pane.unmount()
  // A minute has gone by, so the reset reads a minute closer.
  expect(await paneTexts($, 'terminal')).toContain('5-hour limit 85% · resets in 1h 28m')
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

test('an alert is red, with Dismiss and no answer button: in the terminal pane\'s Waiting on you and in the desktop band; the desktop pane draws no alert card', async ($, on) => {
  boot(on)
  await open('alert', 'CI is red and I cannot fix it', { accept: 'Yes', recommendation: 'Look at the log' })($)
  const term = await mount($, TERM, 'terminal')
  const t = await textsOf(term)
  expect(t).toEqual(expect.arrayContaining(['!', 'CI is red and I cannot fix it', 'Recommended: Look at the log · 8:00 AM']))
  expect((await term.findAll({ type: 'Text', text: '!' }))[0]!.props?.color).toBe('error')
  expect((await term.findAll({ type: 'Box' })).some(b => b.props?.backgroundColor !== undefined)).toBe(false)
  expect(await bandKeys(term)).toEqual(['dismiss-d1'])
  await term.unmount()

  const desk = await mount($, BAND, 'desktop')
  const [card] = await svgsOf(desk)
  expect(card!.alt).toBe('Alert: CI is red and I cannot fix it')
  expect(card!.drawn).toEqual(['!', 'CI is red and I cannot fix it'])
  expect(card!.source).toContain(RED)
  expect(card!.source).not.toContain(AMBER)
  expect(await bandKeys(desk)).toEqual(['dismiss-d1'])
  await desk.unmount()

  const pane = await paneTexts($, 'desktop')
  expect(pane.some(x => x === 'CI is red and I cannot fix it' || x.toUpperCase() === 'ALERT')).toBe(false)
})

test('an action is blue, with Dismiss and no answer button: in the terminal pane\'s Waiting on you and in the desktop band; the desktop pane draws no action card', async ($, on) => {
  boot(on)
  await open('action', 'Merge #112 when ready', { accept: 'Yes' })($)
  const term = await mount($, TERM, 'terminal')
  expect(await textsOf(term)).toEqual(expect.arrayContaining(['→', 'Merge #112 when ready']))
  expect((await term.findAll({ type: 'Text', text: '→' }))[0]!.props?.color).toBe('suggestion')
  expect((await term.findAll({ type: 'Box' })).some(b => b.props?.backgroundColor !== undefined)).toBe(false)
  expect(await bandKeys(term)).toEqual(['dismiss-d1'])
  await term.unmount()

  const desk = await mount($, BAND, 'desktop')
  const [card] = await svgsOf(desk)
  expect(card!.alt).toBe('Waiting on you: Merge #112 when ready')
  expect(card!.drawn).toEqual(['→', 'Merge #112 when ready'])
  expect(card!.source).toContain(BLUE)
  expect(await bandKeys(desk)).toEqual(['dismiss-d1'])
  await desk.unmount()

  const pane = await paneTexts($, 'desktop')
  expect(pane.some(x => x === 'Merge #112 when ready' || x.toUpperCase() === 'WAITING ON YOU')).toBe(false)
})

test('a question with kind question and one without a kind are the same amber question with an answer button', async ($, on) => {
  boot(on)
  await open(undefined, 'Plain?', { accept: 'Yes' })($)
  for (const surface of SURFACES) {
    const d = await mountWaits($, surface)
    expect(await bandKeys(d)).toEqual(['accept-d1', 'dismiss-d1'])
    expect(await textsOf(d)).toEqual(expect.arrayContaining(['?', 'Plain?']))
    await d.unmount()
  }
  const plain = (await svgsOf(await mount($, BAND, 'desktop')))[0]!
  await eng($).tool.call({ tool: CLOSE, id: 'd1' })
  await open('question', 'Explicit?', { accept: 'Yes' })($)
  for (const surface of SURFACES) {
    const d = await mountWaits($, surface)
    expect(await bandKeys(d)).toEqual(['accept-d2', 'dismiss-d2'])
    expect(await textsOf(d)).toEqual(expect.arrayContaining(['?', 'Explicit?']))
    if (surface === 'desktop') {
      const [explicit] = await svgsOf(d)
      expect(explicit!.alt).toBe('Question: Explicit?')
      expect(explicit!.source).toContain(AMBER)
      // The same drawing for both: only the text differs.
      expect(plain.source.replace('Plain?', 'Explicit?')).toBe(explicit!.source)
    }
    await d.unmount()
  }
})

test('an unknown kind is refused with a message and records nothing', async ($, on) => {
  boot(on)
  const refused = await eng($).tool.call({ tool: OPEN, kind: 'urgent', question: 'Now?' })
  expect(refused.deny).toBe('open_decision kind must be question, action or alert.')
  expect(await bandTexts($, 'desktop')).toEqual(['Mentat'])
  expect(await paneTexts($, 'terminal')).toEqual(['Nothing waiting on you.'])
})

test('the desktop pane draws no waiting card of any kind and no answer field; the terminal pane lists every item, most urgent first, with the WARN lines of the check', async ($, on) => {
  const { world } = boot(on)
  await open('action', 'Action one', { link: 'https://github.com/o/r/pull/1' })($)
  await open(undefined, 'Question one', { accept: 'Yes' })($)
  await open('alert', 'Alert one')($)
  await bash(world, $, 'mentat check', WARN_RUN)
  const d = await mount($, PANE, 'desktop', { bodyColumns: 60 })
  const t = await textsOf(d)
  for (const x of ['Action one', 'Question one', 'Alert one', 'Check passed with 2 warnings', 'gh is old']) expect(t.includes(x)).toBe(false)
  for (const x of ['ALERT', 'QUESTION FOR YOU', 'WAITING ON YOU', 'CHECK WARNINGS']) expect(t.map(y => y.toUpperCase())).not.toContain(x)
  expect(await cardKeys(d)).toEqual([])
  expect((await d.findAll({ type: 'Input' })).length).toBe(0)
  expect((await d.findAll({ type: 'Link' })).length).toBe(0)
  expect((await svgsOf(d)).length).toBe(0)
  // Something waits, and the band says so: the pane does not claim that nothing does.
  expect(t).not.toContain('Nothing waiting on you.')
  await d.unmount()

  const term = await mount($, TERM, 'terminal')
  const texts = await textsOf(term)
  const at = (x: string) => texts.indexOf(x)
  // Alert, question, check warning, action.
  expect([at('Alert one'), at('Question one'), at('Check passed with 2 warnings'), at('Action one')].every((n, i, all) => n > -1 && (i === 0 || n > all[i - 1]!))).toBe(true)
  // The check item's WARN lines come from the check result, one line each, under its time.
  expect(texts).toEqual(expect.arrayContaining(['WARN: gh is old', 'WARN: codex is old']))
  expect(at('Check passed with 2 warnings')).toBeLessThan(at('WARN: gh is old'))
  expect(at('WARN: gh is old')).toBeLessThan(at('WARN: codex is old'))
  expect(at('WARN: codex is old')).toBeLessThan(at('Action one'))
  expect((await term.findAll({ type: 'Input' })).length).toBe(0)
  expect((await term.findAll({ type: 'Svg' })).length).toBe(0)
  expect(texts).not.toContain('Nothing waiting on you.')
  expect(await bandKeys(term)).toEqual(['dismiss-d3', 'accept-d2', 'dismiss-d2', 'dismiss-check', 'dismiss-d1'])
  await term.unmount()
})

test('an action or alert shows its link as a Link element beside Dismiss, only when it is an https URL', async ($, on) => {
  boot(on)
  const url = 'https://github.com/o/r/issues/112'
  const bandOf = async (surface: 'terminal' | 'desktop') => {
    const d = await mountWaits($, surface)
    const out = { hrefs: await hrefsOf(d), links: await d.findAll({ type: 'Link' }), keys: await bandKeys(d) }
    await d.unmount()
    return out
  }
  await open('action', 'With a link', { link: url })($)
  for (const surface of SURFACES) {
    const b = await bandOf(surface)
    expect(b.hrefs).toEqual([url])
    expect(b.links.every(l => l.props?.label === 'github.com/o/r/issues/112')).toBe(true)
    // Dismiss is drawn beside the link.
    expect(b.keys).toEqual(['dismiss-d1'])
  }
  await open('alert', 'Alert link', { link: `  ${url}  ` })($)
  // The desktop band shows the urgent item's link; the terminal pane every item's.
  expect((await bandOf('desktop')).hrefs).toEqual([url])
  expect((await bandOf('terminal')).hrefs).toEqual([url, url])
  await eng($).tool.call({ tool: CLOSE, id: 'd1' })
  await eng($).tool.call({ tool: CLOSE, id: 'd2' })
  for (const [i, bad] of ['http://github.com/o/r', 'javascript:alert(1)', 'ftp://x/y', 'github.com/o/r', 'https://', 'https:// spaced', 'file:///etc/passwd', ''].entries()) {
    await open('action', `Bad ${bad}`, { link: bad })($)
    for (const surface of SURFACES) {
      const b = await bandOf(surface)
      expect(b.hrefs).toEqual([])
      // Dismiss is drawn for every item, link or not.
      expect(b.keys.filter(k => String(k).startsWith('dismiss-')).length).toBe(1)
    }
    await eng($).tool.call({ tool: CLOSE, id: `d${i + 3}` })
  }
})

test('a question draws no link, and a call without kind or link behaves as before', async ($, on) => {
  boot(on)
  await open(undefined, 'No link?', { link: 'https://github.com/o/r/issues/1' })($)
  for (const surface of SURFACES) {
    const d = await mountWaits($, surface)
    expect(await textsOf(d)).toContain('No link?')
    expect(await hrefsOf(d)).toEqual([])
    await d.unmount()
  }
})

// Band priority. A rate limit over 80%, a note and the items open together.
const bandWith = async ($: never, surface: 'terminal' | 'desktop') => {
  const d = await mount($, BAND, surface)
  const out = { texts: await textsOf(d), alts: await altsOf(d) }
  await d.unmount()
  return out
}
const moreFor = (t: string[]) => t.find(x => /^\+\d+ more$/.test(x))

test('the band shows the newest alert over everything else, then a question, a check warning and an action, then the budget, a note and the quiet line', async ($, on) => {
  const { world } = boot(on)
  world.usage = { context: 5, limits: [limit('five_hour', 95, RESET_5H())] }
  await note($, 'A note too', 'done')
  await open('action', 'Do the thing')($)
  await open(undefined, 'Ask first?')($)
  await open('alert', 'Old alert')($)
  await open('alert', 'New alert')($)
  const ids = { action: 'd1', question: 'd2', old: 'd3', fresh: 'd4' }
  const none = (texts: string[], ...words: string[]) => expect(texts.some(x => words.some(w => x.includes(w)))).toBe(false)

  // Everything is open: the alert wins and the other three are counted.
  {
    const surface = 'desktop' as const
    const { texts, alts } = await bandWith($, surface)
    expect(texts).toContain('New alert')
    expect(texts).not.toContain('Old alert')
    none(texts, 'limit', 'Ask first?', 'Do the thing', 'A note too')
    expect(moreFor(texts)).toBe('+3 more')
    if (surface === 'desktop') {
      expect(alts).toEqual(['Alert: New alert (+3 more)'])
      expect(texts).toContain('!')
    }
  }
  const term = await mount($, TERM, 'terminal')
  expect((await term.findAll({ type: 'Text', text: '!' }))[0]!.props?.color).toBe('error')
  expect((await term.findAll({ type: 'Box' })).some(b => b.props?.backgroundColor !== undefined)).toBe(false)
  await term.unmount()
  const desk = await mount($, BAND, 'desktop')
  expect((await svgsOf(desk))[0]!.source).toContain(RED)
  await desk.unmount()

  // The alerts closed: the question, with the action counted.
  await eng($).tool.call({ tool: CLOSE, id: ids.fresh })
  await eng($).tool.call({ tool: CLOSE, id: ids.old })
  {
    const surface = 'desktop' as const
    const { texts, alts } = await bandWith($, surface)
    expect(texts).toContain('Ask first?')
    none(texts, 'limit', 'Do the thing', 'A note too')
    expect(moreFor(texts)).toBe('+1 more')
    if (surface === 'desktop') expect(alts).toEqual(['Question: Ask first? (+1 more)'])
  }

  // The question closed: the action, over the budget and the note, with no count.
  await eng($).tool.call({ tool: CLOSE, id: ids.question })
  {
    const surface = 'desktop' as const
    const { texts, alts } = await bandWith($, surface)
    expect(texts).toContain('Do the thing')
    none(texts, 'limit', 'A note too')
    expect(moreFor(texts)).toBeUndefined()
    if (surface === 'desktop') expect(alts).toEqual(['Waiting on you: Do the thing'])
  }

  // The action closed: the budget warning, over the note.
  await eng($).tool.call({ tool: CLOSE, id: ids.action })
  {
    const surface = 'desktop' as const
    const { texts } = await bandWith($, surface)
    expect(texts).toContain('5-hour limit 95% · resets in 1h 29m')
    none(texts, 'A note too')
  }

  // Under the limit: the newest note.
  world.usage = { context: 5, limits: [limit('five_hour', 79, RESET_5H())] }
  {
    const surface = 'desktop' as const
    const { texts } = await bandWith($, surface)
    expect(texts).toContain('A note too')
    none(texts, 'limit')
  }
})

test('a check warning comes before an action, and a question before the warning; an action alone shows over the budget', async ($, on) => {
  const { world } = boot(on)
  world.usage = { context: 5, limits: [limit('five_hour', 95, RESET_5H())] }
  await open('action', 'Do the thing')($)
  // An action waits on the maintainer, so it outranks a budget warning; nothing else is counted.
  {
    const surface = 'desktop' as const
    const { texts } = await bandWith($, surface)
    expect(texts).toContain('Do the thing')
    expect(texts.some(x => x.includes('limit'))).toBe(false)
    expect(moreFor(texts)).toBeUndefined()
  }
  await bash(world, $, 'mentat check', WARN_RUN)
  {
    const surface = 'desktop' as const
    const { texts } = await bandWith($, surface)
    expect(texts).toContain('Check passed with 2 warnings')
    expect(moreFor(texts)).toBe('+1 more')
  }
  await open(undefined, 'Ask first?')($)
  {
    const surface = 'desktop' as const
    const { texts } = await bandWith($, surface)
    expect(texts).toContain('Ask first?')
    expect(texts.some(x => x.includes('limit') || x.includes('Check passed') || x.includes('Do the thing'))).toBe(false)
    expect(moreFor(texts)).toBe('+2 more')
  }
})

test('with no item the band shows the budget warning, else the newest note with its icon, else the quiet line', async ($, on) => {
  const { world } = boot(on)
  await startSession($)
  expect((await bandWith($, 'desktop')).texts).toEqual(['Mentat'])

  await note($, 'Keep the band for #150', 'decision')
  await note($, 'The tests read the old log', 'surprise')
  {
    const surface = 'desktop' as const
    const { texts, alts } = await bandWith($, surface)
    // The newest note only, with its kind's icon.
    expect(texts).toEqual(['!', 'The tests read the old log'])
    if (surface === 'desktop') expect(alts).toEqual(['Note: The tests read the old log'])
    expect(moreFor(texts)).toBeUndefined()
  }
  const term = await mount($, TERM, 'terminal')
  expect((await term.findAll({ type: 'Text', text: '!' }))[0]!.props?.color).toBe('warning')
  await term.unmount()
  const desk = await mount($, BAND, 'desktop')
  expect((await svgsOf(desk))[0]!.source).toContain(AMBER)
  expect(await bandKeys(desk)).toEqual([])
  await desk.unmount()

  await note($, 'Merged', 'done')
  expect((await bandWith($, 'desktop')).texts).toEqual(['✓', 'Merged'])

  // A budget warning outranks the note; with the limit gone the note is back.
  world.usage = { context: 5, limits: [limit('seven_day', 91, RESET_WEEK())] }
  expect((await bandWith($, 'desktop')).texts).toContain('Week limit 91% · resets Thu 7:00 PM')
  world.usage = { context: 5, limits: [limit('seven_day', 10)] }
  expect((await bandWith($, 'desktop')).texts).toEqual(['✓', 'Merged'])

  // A new conversation empties the log, and the band is quiet again.
  const classic = ($ as never as { classic: { SessionStart: (a: { source: string }) => Promise<unknown> } }).classic
  await classic.SessionStart({ source: 'clear' })
  expect((await bandWith($, 'desktop')).texts).toEqual(['Mentat'])
})

test('a lone action raises the desktop band, with its text on the left, its link and Dismiss, and no count; the terminal pane lists it', async ($, on) => {
  boot(on)
  await open('action', 'Run the plugin update', { link: 'https://github.com/o/r/pull/9' })($)
  const term = await waitTexts($, 'terminal')
  expect(term).toEqual(expect.arrayContaining(['→', 'Run the plugin update']))
  expect(moreFor(term)).toBeUndefined()
  const desk = await bandWith($, 'desktop')
  expect(desk.alts).toEqual(['Waiting on you: Run the plugin update'])
  expect(desk.texts).toContain('Run the plugin update')
  expect(moreFor(desk.texts)).toBeUndefined()
  // A second item brings the count back to the desktop band, and its Details button stays; the pane lists both.
  await open('action', 'Another')($)
  expect(moreFor((await bandWith($, 'desktop')).texts)).toBe('+1 more')
  const d = await mount($, BAND, 'desktop')
  expect(await keysOf(d)).toEqual(['dismiss-d2', 'open'])
  await d.unmount()
  const pane = await mount($, TERM, 'terminal')
  expect(await keysOf(pane)).toEqual(['dismiss-d2', 'dismiss-d1'])
  await pane.unmount()
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
  for (const surface of SURFACES) {
    expect(await waitTexts($, surface)).not.toContain('Down')
    expect(await waitTexts($, surface)).toContain('Do it')
  }
  await classic.SessionStart({ source: 'clear' })
  expect(await bandTexts($, 'desktop')).toEqual(['Mentat'])
  expect(await paneTexts($, 'terminal')).toEqual(['Nothing waiting on you.'])
})

// ---- the `mentat check` signal ----------------------------------------------------------------

const FAILED_RUN = 'OK: gh is installed\nPROBLEM: codex is not installed\nPROBLEM: gh is not logged in\nCheck failed: 2 problem(s)\n'
// The desktop band's drawing when it shows an alert.
const alertsOf = async ($: never) => {
  const d = await mount($, BAND, 'desktop')
  const cards = (await svgsOf(d)).filter(v => v.alt.startsWith('Alert'))
  await d.unmount()
  return cards
}
const HUE_AMBER = '#C98A0E'
const toastTexts = (w: World) => w.toasts.map(t => (JSON.parse(t) as { text: string }).text)

test('a failed mentat check pins one alert, with Dismiss, in the desktop band and the terminal pane; the desktop pane draws nothing of it', async ($, on) => {
  const { world } = boot(on)
  await bash(world, $, 'cd "a b" && mentat check 2>&1', FAILED_RUN)
  const [card, ...more] = await alertsOf($)
  expect(more).toEqual([])
  expect(card!.alt).toBe('Alert: Check failed: 2 problem(s)')
  expect(card!.drawn).toEqual(['!', 'Check failed: 2 problem(s)'])
  for (const surface of SURFACES) expect((await waitTexts($, surface)).includes('Check failed: 2 problem(s)')).toBe(true)
  const pane = await paneTexts($, 'desktop')
  expect(pane.some(x => x.includes('Check failed') || x.includes('codex is not installed') || x.toUpperCase() === 'ALERT')).toBe(false)
  // The PROBLEM lines are not drawn on the terminal either.
  expect((await waitTexts($, 'terminal')).some(x => x.includes('codex is not installed'))).toBe(false)
  // Only Dismiss: no answer button, no toast for a failure.
  const d = await mount($, TERM, 'terminal')
  expect(await bandKeys(d)).toEqual(['dismiss-check'])
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
  // The alert outranks the agent's question, which is counted beside it.
  expect(cards[0]!.alt).toBe('Alert: Check failed: 1 problem(s) (+1 more)')
  expect(cards[0]!.drawn).toEqual(['!', 'Check failed: 1 problem(s)', '+1 more'])
  await eng($).tool.call({ tool: CLOSE, id: 'd1' })
  expect(await bandTexts($)).toEqual(['!', 'Check failed: 1 problem(s)'])
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
// The desktop band's drawing when it shows a check warning.
const checkItemsOf = async ($: never) => {
  const d = await mount($, BAND, 'desktop')
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
  expect(await bandTexts($)).toEqual(['Mentat'])
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

  // A pass with warnings pins the warning item, which waits on the maintainer and is counted.
  await bash(world, $, 'mentat check', WARN_RUN)
  for (const surface of SURFACES) {
    expect(await footerOf($, surface, ['focus'])).toEqual([
      { text: '● Mentat · 2 warnings', color: 'warning', dim: false },
      { text: ' · ', color: undefined, dim: true },
      { text: '1 waiting', color: 'warning', dim: false },
      { text: 'focus', color: undefined, dim: true },
    ])
  }
  await bash(world, $, 'mentat check', 'WARN: gh is old\nCheck OK (1 warning(s))\n')
  expect((await footerOf($, 'terminal')).slice(0, 3)).toEqual([
    { text: '● Mentat · 1 warning', color: 'warning', dim: false },
    { text: ' · ', color: undefined, dim: true },
    { text: '1 waiting', color: 'warning', dim: false },
  ])

  await bash(world, $, 'mentat check', FAILED_RUN)
  for (const surface of SURFACES) {
    expect(await footerOf($, surface, ['focus'])).toEqual([
      { text: '● Mentat check failed', color: 'error', dim: false },
      { text: ' · ', color: undefined, dim: true },
      { text: '1 waiting', color: 'warning', dim: false },
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
  // Dismissing the item leaves the label as today: red, with nothing waiting.
  const pane = await mount($, TERM, 'terminal')
  await pane.press({ key: 'dismiss-check' })
  await pane.unmount()
  expect(await footerOf($, 'terminal')).toEqual([{ text: '● Mentat check failed', color: 'error', dim: false }])
})

test('the footer label counts every open item and, on the terminal only, is a Button that opens the pane', async ($, on) => {
  const { world } = boot(on)
  const buttonsOf = async (surface: 'terminal' | 'desktop') => {
    const d = await mount($, SESSION_MODE, surface, { modes: [] })
    const found = (await d.findAll({ type: 'Button' })).map(b => ({ key: b.key, label: b.props?.label, plain: b.props?.plain }))
    const texts = (await d.findAll({ type: 'Text' })).map(t => ({ text: t.text, color: t.props?.color }))
    await d.unmount()
    return { found, texts }
  }
  // Nothing waits: the label is as it was, and still opens the pane on the terminal.
  expect((await buttonsOf('terminal')).found).toEqual([{ key: 'mentat-open', label: '● Mentat', plain: true }])
  expect((await buttonsOf('desktop')).found).toEqual([])

  await eng($).tool.call({ tool: OPEN, question: 'One?' })
  await eng($).tool.call({ tool: OPEN, kind: 'action', question: 'Two' })
  await bash(world, $, 'mentat check', WARN_RUN)
  // Every open item counts, the check's warning item included.
  const terminal = await buttonsOf('terminal')
  expect(terminal.found).toEqual([{ key: 'mentat-open', label: '● Mentat · 2 warnings · 3 waiting', plain: true }])
  expect(terminal.texts.find(t => t.text === '3 waiting')?.color).toBe('warning')
  const desktop = await buttonsOf('desktop')
  expect(desktop.found).toEqual([])
  expect(desktop.texts.find(t => t.text === '3 waiting')?.color).toBe('warning')

  const footer = await mount($, SESSION_MODE, 'terminal', { modes: [] })
  await footer.press({ key: 'mentat-open' })
  await footer.unmount()
  expect(world.opened).toEqual(['mentat'])
  // /mentat with no arguments opens it too.
  world.opened.length = 0
  await eng($).command.run({ command: 'mentat', args: '' })
  expect(world.opened).toEqual(['mentat'])
})

test('the footer label leaves other surfaces (mobile) to the engine', async ($, on) => {
  boot(on)
  const d = await mount($, SESSION_MODE, 'mobile' as never, { modes: ['focus'] })
  expect((await d.findAll({ type: 'Text' })).map(t => t.text)).not.toContain('● Mentat')
  expect((await d.findAll({ type: 'Box' })).map(b => b.key)).toEqual(['engine-own'])
  await d.unmount()
})

test('a pass with warnings pins one warning item, a clean pass removes it, a fail makes it the red alert', async ($, on) => {
  const { world } = boot(on)
  await open('action', 'An action stays?')($)
  await bash(world, $, 'cd "a b" && mentat check 2>&1', WARN_RUN)

  // The warning outranks the agent's action, which is counted beside it.
  const [card, ...more] = await checkItemsOf($)
  expect(more).toEqual([])
  expect(card!.alt).toBe('Check warnings: Check passed with 2 warnings (+1 more)')
  expect(card!.drawn).toEqual(['!', 'Check passed with 2 warnings', '+1 more'])
  expect(card!.source).toContain(HUE_AMBER)
  const term = await mount($, TERM, 'terminal')
  // The terminal pane lists the warning first, then the action, with the WARN lines under the warning.
  const texts = await textsOf(term)
  expect(texts).toEqual(expect.arrayContaining(['!', 'Check passed with 2 warnings', 'WARN: gh is old', 'WARN: codex is old', 'An action stays?']))
  expect(texts.some(x => x.includes('more'))).toBe(false)
  expect((await term.findAll({ type: 'Text', text: '!' }))[0]!.props?.color).toBe('warning')
  expect((await term.findAll({ type: 'Box' })).some(b => b.props?.backgroundColor !== undefined)).toBe(false)
  // Only Dismiss: no answer button and no link.
  expect(await bandKeys(term)).toEqual(['dismiss-check', 'dismiss-d1'])
  expect(await hrefsOf(term)).toEqual([])
  await term.unmount()
  // The desktop pane draws neither the warning nor its WARN lines.
  const pane = await paneTexts($, 'desktop')
  expect(pane.some(x => x.includes('Check passed') || x.includes('gh is old') || x.toUpperCase() === 'CHECK WARNINGS')).toBe(false)
  // The next warned run replaces it, so there is still one.
  await bash(world, $, 'mentat check', 'WARN: only one\nCheck OK (1 warning(s))\n')
  const again = await checkItemsOf($)
  expect(again.length).toBe(1)
  expect(again[0]!.alt).toBe('Check warnings: Check passed with 1 warning (+1 more)')

  // A fail turns it into the red alert; there is one item with the id check.
  await bash(world, $, 'mentat check', FAILED_RUN)
  expect(await checkItemsOf($)).toEqual([])
  expect((await alertsOf($)).length).toBe(1)

  // A warned run after a failed one removes the alert; the agent's action is untouched.
  await bash(world, $, 'mentat check', WARN_RUN)
  expect((await alertsOf($)).length).toBe(0)
  expect((await checkItemsOf($)).length).toBe(1)
  await bash(world, $, 'mentat check', CLEAN_RUN)
  expect(await checkItemsOf($)).toEqual([])
  expect(await bandTexts($)).toEqual(expect.arrayContaining(['→', 'An action stays?']))
  expect(toastTexts(world)).toEqual([])
})

test('a warning count the output does not show is still counted in the footer label', async ($, on) => {
  const { world } = boot(on)
  await bash(world, $, 'mentat check', 'WARN: seen\nCheck OK (2 warning(s))\n')
  expect((await footerOf($, 'terminal'))[0]!.text).toBe('● Mentat · 2 warnings')
  const [card] = await checkItemsOf($)
  expect(card!.alt).toBe('Check warnings: Check passed with 2 warnings')
  // The terminal pane lists the line it saw and one for the warning whose text it did not.
  const seen = (await waitTexts($, 'terminal')).filter(t => t.startsWith('WARN: '))
  expect(seen).toEqual(['WARN: seen', 'WARN: A warning whose text was not in the output'])

  const warns = Array.from({ length: 8 }, (_, i) => `warning number ${i + 1}`)
  await bash(world, $, 'mentat check', `${warns.map(w => `WARN: ${w}`).join('\n')}\nCheck OK (8 warning(s))`)
  expect((await footerOf($, 'terminal'))[0]!.text).toBe('● Mentat · 8 warnings')
  const [many] = await checkItemsOf($)
  expect(many!.alt).toBe('Check warnings: Check passed with 8 warnings')
  expect((await waitTexts($, 'terminal')).filter(t => t.startsWith('WARN: '))).toEqual(warns.map(w => `WARN: ${w}`))
})

test('the band shows the alert, then the question, then the check warning, then the action, as each is closed in turn', async ($, on) => {
  const { world } = boot(on)
  await open('action', 'Do the thing')($)
  await bash(world, $, 'mentat check', WARN_RUN)
  await open(undefined, 'Ask first?')($)
  await open('alert', 'Down')($)
  const shown = async () => (await bandWith($, 'desktop')).alts[0]
  expect(await shown()).toBe('Alert: Down (+3 more)')
  await eng($).tool.call({ tool: CLOSE, id: 'd3' })
  expect(await shown()).toBe('Question: Ask first? (+2 more)')
  await eng($).tool.call({ tool: CLOSE, id: 'd2' })
  expect(await shown()).toBe('Check warnings: Check passed with 2 warnings (+1 more)')
  await bash(world, $, 'mentat check', CLEAN_RUN)
  expect(await shown()).toBe('Waiting on you: Do the thing')
})

test('the agent cannot open a warning: open_decision refuses the kind and records nothing', async ($, on) => {
  boot(on)
  const refused = await eng($).tool.call({ tool: OPEN, kind: 'warning', question: 'Careful?' })
  expect(refused.deny).toBe('open_decision kind must be question, action or alert.')
  expect(await bandTexts($, 'desktop')).toEqual(['Mentat'])
  expect(await paneTexts($, 'terminal')).toEqual(['Nothing waiting on you.'])
})

test('the check warning comes after an alert and a question and before an action and the budget', async ($, on) => {
  const { world } = boot(on)
  world.usage = { context: 5, limits: [limit('five_hour', 95, RESET_5H())] }
  await open('action', 'Do the thing')($)
  await bash(world, $, 'mentat check', WARN_RUN)
  const none = (texts: string[], ...words: string[]) => expect(texts.some(x => words.some(w => x.includes(w)))).toBe(false)

  // The warning outranks the action and the budget.
  {
    const surface = 'desktop' as const
    const { texts, alts } = await bandWith($, surface)
    expect(texts).toContain('Check passed with 2 warnings')
    none(texts, 'limit', 'Do the thing')
    expect(moreFor(texts)).toBe('+1 more')
    if (surface === 'desktop') {
      expect(alts).toEqual(['Check warnings: Check passed with 2 warnings (+1 more)'])
      expect(texts).toContain('!')
    }
  }
  const term = await mount($, TERM, 'terminal')
  expect((await term.findAll({ type: 'Text', text: '!' }))[0]!.props?.color).toBe('warning')
  expect((await term.findAll({ type: 'Box' })).some(b => b.props?.backgroundColor !== undefined)).toBe(false)
  await term.unmount()
  const desk = await mount($, BAND, 'desktop')
  expect((await svgsOf(desk))[0]!.source).toContain(HUE_AMBER)
  await desk.unmount()

  // A question outranks the warning.
  await open(undefined, 'Ask first?')($)
  {
    const surface = 'desktop' as const
    const { texts } = await bandWith($, surface)
    expect(texts).toContain('Ask first?')
    none(texts, 'Check passed')
    expect(moreFor(texts)).toBe('+2 more')
  }
  // An alert (the failed check replaces the warning) outranks the question.
  await bash(world, $, 'mentat check', FAILED_RUN)
  expect((await bandWith($, 'desktop')).texts).toContain('Check failed: 2 problem(s)')

  // Back to the warning, then a clean pass: the question is gone too, so the action shows, not the pull request.
  await bash(world, $, 'mentat check', WARN_RUN)
  await eng($).tool.call({ tool: CLOSE, id: 'd2' })
  await bash(world, $, 'mentat check', CLEAN_RUN)
  {
    const surface = 'desktop' as const
    const { texts } = await bandWith($, surface)
    expect(texts).toContain('Do the thing')
    none(texts, 'Check passed', 'limit')
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
  const d = await mount($, BAND, 'desktop')
  await d.press({ key: 'dismiss-check' })
  await d.unmount()
  expect(await alertsOf($)).toEqual([])
  expect(await bandTexts($)).toEqual(['Mentat'])

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

test('the check alert shows only its final line, however many problems there are', async ($, on) => {
  const { world } = boot(on)
  const problems = Array.from({ length: 9 }, (_, i) => `problem number ${i + 1}`)
  await bash(world, $, 'mentat check', `${problems.map(p => `PROBLEM: ${p}`).join('\n')}\nCheck failed: 9 problem(s)`)
  const [card] = await alertsOf($)
  expect(card!.drawn).toEqual(['!', 'Check failed: 9 problem(s)'])
  for (const surface of SURFACES) {
    expect((await paneTexts($, surface)).some(x => x.includes('problem number'))).toBe(false)
    expect((await bandTexts($, surface)).some(x => x.includes('problem number'))).toBe(false)
  }
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
  if (surface === 'desktop') {
    for (let i = t.indexOf('LOG') + 1; i > 0 && i + 2 < t.length && /^\d+:\d\d [AP]M$/.test(t[i]!); i += 3) rows.push({ time: t[i]!, icon: t[i + 1]!, text: t[i + 2]! })
  } else {
    // The terminal's Feed: the pinned agents, then a row of side line, time, icon and text per entry.
    for (let i = t.indexOf('FEED') + 1; i > 0 && i + 2 < t.length; i++) {
      if (!/^\d+:\d\d [AP]M$/.test(t[i]!)) continue
      rows.push({ time: t[i]!, icon: t[i + 1]!, text: t[i + 2]! })
      i += 2
    }
  }

  return { rows, toggle, hasSvg }
}
// The Feed rows of a terminal pane that is already mounted (only one can be at a time), newest first, as icon and text.
const feedLines = async (d: Drawing) => {
  const t = await textsOf(d)
  const out: string[] = []
  for (let i = t.indexOf('FEED') + 1; i > 0 && i + 2 < t.length; i++) {
    if (!/^\d+:\d\d [AP]M$/.test(t[i]!)) continue
    out.push(`${t[i + 1]} ${t[i + 2]}`)
    i += 2
  }

  return out
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

test('only the pane\'s own events are logged: a ready, a close, an issue, a Codex command and a merge add nothing', async ($, on) => {
  const { world } = boot(on)
  await startSession($)
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
  await bash(world, $, 'git push', '')
  await new Promise(r => setTimeout(r, 30))
  // Only the pane's own events: the PR opened, the item asked and closed, the builder done.
  expect(await lines($)).toEqual(['✓ Builder finished: Build the log · 0s', '✓ Closed: Merge the log card now? · Yes, merge', '? Asked you: Merge the log card now?', '↗ Opened PR #130'])
  // The commands still ran as before.
  expect(world.commands).toEqual(['mentat:codex-review-off', 'mentat:codex-review-on'])
})

// How many entries each surface shows before `Show all`: the desktop's Log card five, the terminal's Feed ten.
const SHOWN = { terminal: 10, desktop: 5 } as const

test('the log shows the newest five on the desktop and the newest ten in the terminal Feed; Show all N shows the rest, Show fewer goes back, and the choice is kept', async ($, on) => {
  boot(on)
  await startSession($)
  for (let i = 1; i <= 12; i++) await note($, `Note ${i}`)
  for (const surface of SURFACES) {
    const first = await logOf($, surface)
    expect(first.rows.map(r => r.text)).toEqual(Array.from({ length: SHOWN[surface] }, (_, k) => `Note ${12 - k}`))
    expect(first.toggle).toEqual(['Show all 12'])
  }
  for (const surface of SURFACES) {
    const pane = await mount($, PANE, surface, { bodyColumns: 60 })
    await pane.press({ key: 'log-toggle' })
    await pane.unmount()
    const all = await logOf($, surface)
    expect(all.rows).toHaveLength(12)
    expect(all.toggle).toEqual(['Show fewer'])
    // The choice survives a remount.
    const again = await mount($, PANE, surface, { bodyColumns: 60 })
    expect((await again.findAll({ type: 'Button' })).filter(b => b.key === 'log-toggle').map(b => String(b.props?.label))).toEqual(['Show fewer'])
    await again.press({ key: 'log-toggle' })
    await again.unmount()
    const fewer = await logOf($, surface)
    expect(fewer.rows).toHaveLength(SHOWN[surface])
    expect(fewer.toggle).toEqual(['Show all 12'])
  }
})

test('with no more entries than a surface shows there is no toggle; with none there is no Log or Feed section', async ($, on) => {
  boot(on)
  await startSession($)
  expect(await paneTexts($)).not.toContain('FEED')
  expect(await paneTexts($, 'desktop')).not.toContain('LOG')
  for (let i = 0; i < 10; i++) await note($, `Note ${i}`)
  const got = await logOf($)
  expect(got.rows).toHaveLength(10)
  expect(got.toggle).toEqual([])
  // The desktop shows five, so it has the toggle already.
  expect((await logOf($, 'desktop')).toggle).toEqual(['Show all 10'])
  await note($, 'Note 10')
  expect((await logOf($)).toggle).toEqual(['Show all 11'])
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

test('the log is plain text rows on both surfaces, with no Svg and no tint; in the terminal Feed the live agents are pinned above the rows', async ($, on) => {
  const { world } = boot(on)
  await startSession($)
  await eng($).tool.call({ tool: OPEN, question: 'Open one?' })
  await note($, 'A decision', 'decision')
  world.agents = [{ id: 'a1', type: 'Explore', description: 'Look around', status: 'running' }]
  await eng($).agent.spawn(spawn('a1', 'Look around', 'Explore'))
  for (const surface of SURFACES) {
    const pane = await mount($, PANE, surface, { bodyColumns: 60 })
    const t = await textsOf(pane)
    // On the terminal the pinned agent sits above the Log rows (the desktop draws the agents as Svg, which textsOf lists last).
    if (surface === 'terminal') {
      expect(t.indexOf('Look around')).toBeGreaterThan(t.indexOf('FEED'))
      expect(t.indexOf('Look around')).toBeLessThan(t.indexOf('A decision'))
      expect(t).toContain('Open one?')
    } else expect(t.includes('Open one?')).toBe(false)
    const rows = (await pane.findAll({ type: 'Box' })).filter(b => String(b.key).startsWith('log-'))
    // The note, and the line for the question the pane saw opened.
    expect(rows).toHaveLength(2)
    expect(rows.every(b => b.props?.backgroundColor === undefined)).toBe(true)
    await pane.unmount()
  }
  // On the desktop the log is not an Svg: the only Svg element is the agents.
  const d = await mount($, PANE, 'desktop', { bodyColumns: 60 })
  expect((await svgsOf(d)).map(v => v.alt)).toEqual(['Running agents: 1 (explore: Look around)'])
  await d.unmount()
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

test('/mentat takes no argument: with one it only says so, and opens nothing', async ($, on) => {
  const { world } = boot(on)
  expect((await eng($).command.run({ command: 'mentat', args: 'pr 5' })).text).toBe('Usage: /mentat')
  expect(world.opened).toEqual([])
  expect(world.calls).toEqual([])
})

test('the pane never calls $.command.run, whatever its buttons do', async ($, on) => {
  const { world } = boot(on)
  await startSession($)
  await note($, 'A note')
  await eng($).tool.call({ tool: OPEN, question: 'Ship it?', accept: 'Yes' })
  await eng($).command.run({ command: 'mentat', args: 'pr 5' })
  await eng($).command.run({ command: 'mentat:come-again', args: '' })
  expect((await lines($)).slice(-1)).toEqual(['▸ A note'])
  for (const surface of SURFACES) {
    const pane = await mount($, PANE, surface, { bodyColumns: 60 })
    for (const b of await pane.findAll({ type: 'Button' })) await pane.press({ key: String(b.key) })
    await pane.unmount()
  }
  expect(world.commands).toEqual(['mentat:come-again'])
})

test('no terminal Box has a backgroundColor: a terminal draws an 8-digit hex tint as opaque grey', async ($, on) => {
  const { world } = boot(on, { zone: 'America/New_York' })
  world.usage = { context: 41, limits: [{ kind: 'five_hour', percentUsed: 85, resetsAt: new Date(T0 + 3600_000).toISOString() }] }
  await startSession($)
  await eng($).tool.call({ tool: OPEN, question: 'Open one?' })
  await eng($).tool.call({ tool: OPEN, kind: 'action', question: 'Merge it' })
  await eng($).tool.call({ tool: OPEN, kind: 'alert', question: 'CI is red' })
  await note($, 'A note')
  world.agents = [{ id: 'a1', type: 'Explore', description: 'Look around', status: 'running' }]
  await eng($).agent.spawn(spawn('a1', 'Look around', 'Explore'))
  for (const [spec, props] of [[PANE, { bodyColumns: 60 }], [BAND, {}]] as const) {
    const term = await mount($, spec, 'terminal', props)
    const boxes = await term.findAll({ type: 'Box' })
    expect(boxes.length).toBeGreaterThan(0)
    expect(boxes.filter(b => b.props?.backgroundColor !== undefined).length).toBe(0)
    await term.unmount()
  }
  expect(await paneTexts($, 'terminal')).not.toContain('SESSION')
})

// ---- the terminal pane's width classes ----------------------------------------------------

// Opens what the layout tests draw: two items (one with a recommendation, the check's warning item), an agent and some log.
const layoutWorld = async ($: never, w: World) => {
  await startSession($)
  await eng($).tool.call({ tool: OPEN, question: 'Ship the change now?', recommendation: 'Yes, it passed', accept: 'Yes' })
  await bash(w, $, 'mentat check', WARN_RUN)
  await note($, 'A note for the Feed', 'decision')
  w.agents = [{ id: 'a1', type: 'builder', description: 'Build the pane', status: 'running' }]
  await eng($).agent.spawn(spawn('a1', 'Build the pane', 'builder'))
}
// The pieces of the edge that starts at `start` (the title's section), joined.
const edgeAt = (t: string[], start: string, parts: number) => t.slice(t.indexOf(start), t.indexOf(start) + parts).join('')

test('from 60 columns each section is a frame: edges exactly as wide as the body, the title bold in the top edge, side lines on every row', async ($, on) => {
  const { world } = boot(on)
  await layoutWorld($, world)
  for (const cols of [60, 72, 100]) {
    const d = await mount($, PANE, 'terminal', { bodyColumns: cols })
    const t = await textsOf(d)
    const texts = await d.findAll({ type: 'Text' })
    const top = (title: string) => {
      const i = t.indexOf(title)
      return t.slice(i - 1, i + 3).join('')
    }
    // `╭─ WAITING ON YOU 2 ───…╮` and `╭─ FEED 4 ───…╮`.
    const waiting = top('WAITING ON YOU')
    expect(waiting.startsWith('╭─ WAITING ON YOU 2 ─')).toBe(true)
    expect(waiting.endsWith('─╮')).toBe(true)
    expect([...waiting]).toHaveLength(cols)
    const feed = top('FEED')
    expect(feed.startsWith('╭─ FEED 4 ─')).toBe(true)
    expect([...feed]).toHaveLength(cols)
    // The bottom edges.
    const bottoms = t.filter(x => x.startsWith('╰'))
    expect(bottoms).toEqual([`╰${'─'.repeat(cols - 2)}╯`, `╰${'─'.repeat(cols - 2)}╯`])
    // The title is bold and its count dim, the lines dim.
    expect(texts.find(x => x.text === 'WAITING ON YOU')?.props?.bold).toBe(true)
    expect(texts.find(x => x.text === ' 2')?.props?.dimColor).toBe(true)
    expect(texts.find(x => x.text === '│ ')?.props?.dimColor).toBe(true)
    // Every body row has both side lines: Waiting on you has 2 items (with details and WARN lines), the Feed 4 rows.
    expect(t.filter(x => x === '│ ').length).toBe(t.filter(x => x === ' │').length)
    expect(t.filter(x => x === '│ ').length).toBeGreaterThanOrEqual(8)
    // The middle of a row grows and shrinks, and its text is cut with an ellipsis rather than wrapped.
    expect(texts.find(x => x.text === 'Ship the change now?')?.props?.wrap).toBe('truncate-end')
    await d.unmount()
  }
})

test('from 40 to 59 columns each section is headed by a rule to the full width, with no side lines or bottom edge', async ($, on) => {
  const { world } = boot(on)
  await layoutWorld($, world)
  for (const cols of [40, 52, 59]) {
    const d = await mount($, PANE, 'terminal', { bodyColumns: cols })
    const t = await textsOf(d)
    const rule = (title: string) => {
      const i = t.indexOf(title)
      return t.slice(i - 1, i + 3).join('')
    }
    const waiting = rule('WAITING ON YOU')
    expect(waiting.startsWith('── WAITING ON YOU 2 ─')).toBe(true)
    expect([...waiting]).toHaveLength(cols)
    expect([...rule('FEED')]).toHaveLength(cols)
    expect(rule('FEED').startsWith('── FEED 4 ─')).toBe(true)
    expect(t.some(x => x === '│ ' || x === ' │' || x.startsWith('╰') || x.startsWith('╭'))).toBe(false)
    // The times, the recommendation and the WARN lines are still there.
    expect(t).toContain('Recommended: Yes, it passed · 8:00 AM')
    expect(t).toContain('WARN: gh is old')
    expect(t).toContain('8:00 AM')
    await d.unmount()
  }
})

test('under 40 columns the heading rules stay, and the times, Recommended lines and WARN lines drop', async ($, on) => {
  const { world } = boot(on)
  await layoutWorld($, world)
  const d = await mount($, PANE, 'terminal', { bodyColumns: 36 })
  const t = await textsOf(d)
  const i = t.indexOf('WAITING ON YOU')
  expect([...t.slice(i - 1, i + 3).join('')]).toHaveLength(36)
  expect(t.slice(i - 1, i + 3).join('').startsWith('── WAITING ON YOU 2 ─')).toBe(true)
  expect(t.some(x => /^\d+:\d\d [AP]M$/.test(x) || x.includes(' · 8:00 AM'))).toBe(false)
  expect(t.some(x => x.startsWith('Recommended:') || x.startsWith('WARN:'))).toBe(false)
  // What stays: the items and their buttons, the agent with its state, the log lines.
  expect(t).toEqual(expect.arrayContaining(['Ship the change now?', 'Yes', 'Dismiss', 'Check passed with 2 warnings', 'Build the pane', 'running · 0s', 'A note for the Feed']))
  expect(await bandKeys(d)).toEqual(['accept-d1', 'dismiss-d1', 'dismiss-check'])
  await d.unmount()
})

test('the empty line is said only with no item, no live agent and no log entry', async ($, on) => {
  const { world } = boot(on)
  expect(await paneTexts($, 'terminal')).toEqual(['Nothing waiting on you.'])
  const d = await mount($, PANE, 'terminal', { bodyColumns: 60 })
  expect((await d.findAll({ type: 'Text', text: 'Nothing waiting on you.' }))[0]!.props?.dimColor).toBe(true)
  await d.unmount()
  // A live agent alone fills the Feed.
  world.agents = [{ id: 'a1', type: 'Explore', description: 'Look around', status: 'running' }]
  await eng($).agent.spawn(spawn('a1', 'Look around', 'Explore'))
  const t = await paneTexts($, 'terminal')
  expect(t).not.toContain('Nothing waiting on you.')
  expect(t).not.toContain('WAITING ON YOU')
  expect(t).toContain('FEED')
  // No blank row between the agents and the log when there is no log.
  expect(t.filter(x => x === ' ')).toEqual([])
})

test('live agents are pinned above the log with a blank row between; ended agents are not in the Feed', async ($, on) => {
  const { world, clock } = boot(on)
  await startSession($)
  await note($, 'A note', 'done')
  world.agents = [
    { id: 'r1', type: 'builder', description: 'Running one', status: 'running' },
    { id: 'c1', type: 'Explore', description: 'Ended one', status: 'running' },
  ]
  await eng($).agent.spawn(spawn('r1', 'Running one', 'builder'))
  await eng($).agent.spawn(spawn('c1', 'Ended one', 'Explore'))
  world.agents = [world.agents[0]!, { ...world.agents[1]!, status: 'completed' }]
  await clock.advance(2_000)
  await new Promise(r => setTimeout(r, 30))
  const t = await paneTexts($, 'terminal')
  const at = (x: string) => t.indexOf(x)
  expect(at('FEED')).toBeLessThan(at('Running one'))
  expect(at('Running one')).toBeLessThan(at(' '))
  expect(at(' ')).toBeLessThan(at('A note'))
  expect(stateOf(t, 'Running one')).toBe('running · 2s')
  expect(t).not.toContain('Ended one')
  // Its end is an event line, in the log below (the engine's next check of its list found it ended).
  expect(t).toContain('Explore finished: Ended one · 1s')
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

test('a session start with warnings pins the warning item and turns the label amber', async ($, on) => {
  const { world } = boot(on)
  world.git = GIT_YES
  world.check = ok(WARN_RUN)
  await startSession($)
  await untilFooter($, 'terminal', '● Mentat · 2 warnings', 'warning')
  const cards = await checkItemsOf($)
  expect(cards.length).toBe(1)
  expect(cards[0]!.alt).toBe('Check warnings: Check passed with 2 warnings')
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

// ---- the band is one row; an open question survives what happens around it ----------------------------------

test('the desktop band is one row: the text, then one Box that holds the answer button, Dismiss, the link and Details', async ($, on) => {
  boot(on)
  await open('question', 'Ship it?', { accept: 'Yes' })($)
  const d = await mount($, BAND, 'desktop')
  // The buttons are in one Box that does not shrink or wrap; there is no second row of controls.
  const controls = (await d.findAll({ type: 'Box' })).filter(b => b.props?.flexShrink === 0)
  expect(controls).toHaveLength(1)
  expect(controls[0]!.props?.flexDirection).toBe('row')
  expect(await bandKeys(d)).toEqual(['accept-d1', 'dismiss-d1'])
  expect((await d.findAll({ type: 'Button' })).map(b => b.key)).toEqual(['accept-d1', 'dismiss-d1', 'open'])
  await d.unmount()
  await eng($).tool.call({ tool: CLOSE, id: 'd1' })
  // The same in every state: a quiet band has just Details in that Box.
  const quiet = await mount($, BAND, 'desktop')
  expect((await quiet.findAll({ type: 'Box' })).filter(b => b.props?.flexShrink === 0)).toHaveLength(1)
  expect((await quiet.findAll({ type: 'Button' })).map(b => b.key)).toEqual(['open'])
  await quiet.unmount()
})

test('a terminal pane row ends in its buttons without width arithmetic: side lines, a growing middle and one controls Box that does not shrink', async ($, on) => {
  boot(on)
  await open('question', 'Ship it?', { accept: 'Yes' })($)
  const d = await mount($, TERM, 'terminal')
  const boxes = await d.findAll({ type: 'Box' })
  const row = boxes.find(b => b.key === 'item-d1')!
  expect(row.props?.flexDirection).toBe('row')
  // The middle grows and shrinks; the controls keep their size.
  expect(boxes.filter(b => b.props?.flexGrow === 1 && b.props?.flexShrink === 1 && b.props?.flexDirection === 'row')).not.toHaveLength(0)
  const controls = boxes.filter(b => b.key === 'controls')
  expect(controls).toHaveLength(1)
  expect(controls[0]!.props?.flexDirection).toBe('row')
  expect(controls[0]!.props?.flexShrink).toBe(0)
  const texts = await textsOf(d)
  expect(texts.slice(texts.indexOf('│ '), texts.indexOf(' │') + 1)).toEqual(['│ ', '?', 'Ship it?', 'Yes', 'Dismiss', ' │'])
  expect(await bandKeys(d)).toEqual(['accept-d1', 'dismiss-d1'])
  expect((await d.findAll({ type: 'Button' })).map(b => b.key)).toEqual(['accept-d1', 'dismiss-d1'])
  await d.unmount()
})

test('with the pane open, a question opened by the agent is still open after the user types a message, and close_decision settles it', async ($, on) => {
  const { world } = boot(on)
  await startSession($)
  const pane = await mount($, TERM, 'terminal')
  const opened = await eng($).tool.call({ tool: OPEN, question: 'Ship it?', recommendation: 'Yes', accept: 'Yes' })
  expect(String(opened.result)).toContain('d1')
  // What can happen in the session meanwhile: the user's message (the agent's turn goes on), a model
  // request, a timer-driven read, a reload and a compaction. None of them touches the open question.
  const classic = ($ as never as { classic: { SessionStart: (a: { source: string }) => Promise<unknown> } }).classic
  await eng($).turn.complete({ answer: 'ok', durationMs: 1, isAborted: false, turnId: 'turn-main', reason: 'end_turn' })
  await step($, undefined)
  await startSession($)
  await classic.SessionStart({ source: 'startup' })
  await classic.SessionStart({ source: 'compact' })
  expect(await bandTexts($)).toContain('Ship it?')
  expect(await textsOf(pane)).toContain('Ship it?')
  const closed = await eng($).tool.call({ tool: CLOSE, id: 'd1', outcome: 'No, do not ship' })
  expect(closed.deny).toBeUndefined()
  expect(String(closed.result)).toBe('Closed decision d1.')
  expect(await bandTexts($)).toEqual(['Mentat'])
  expect(await textsOf(pane)).not.toContain('Ship it?')
  expect(world.sent).toEqual([])
  await pane.unmount()
})

// ---- the Feed: event lines the pane writes itself ----------------------------------------------

// Every Log line in the order they were written (oldest first), as icon and text: the pane shows the newest
// five until `Show all`, so this presses it when it is there.
const written = async ($: never, surface: 'terminal' | 'desktop' = 'terminal') => {
  const pane = await mount($, PANE, surface, { bodyColumns: 60 })
  if ((await pane.findAll({ type: 'Button' })).some(b => b.key === 'log-toggle' && String(b.props?.label).startsWith('Show all'))) await pane.press({ key: 'log-toggle' })
  await pane.unmount()

  return (await lines($, surface)).reverse()
}
// How a Log row is drawn: the colors of the Text elements with that mark, and whether the Text with that line is dim.
const drawnRow = async ($: never, surface: 'terminal' | 'desktop', icon: string, text: string) => {
  const pane = await mount($, PANE, surface, { bodyColumns: 60 })
  const marks = await pane.findAll({ type: 'Text', text: icon })
  const texts = (await pane.findAll({ type: 'Text' })).filter(t => t.text === text)
  await pane.unmount()

  return { colors: marks.map(m => m.props?.color), dim: texts.map(t => t.props?.dimColor === true) }
}
const classicOf = ($: never) => ($ as never as { classic: { SessionStart: (a: { source: string }) => Promise<unknown> } }).classic

test('an agent that ends writes one line: finished with the time it took, failed, or stopped; an unknown end writes none', async ($, on) => {
  const { world, clock } = boot(on)
  const row = (id: string, type: string, description: string, status = 'running') => ({ id, type, description, status })
  // z1 is listed by the engine before the pane ever sees it spawn: it has no start time.
  world.agents = [row('z1', 'Explore', 'Never spawned here')]
  await startSession($)
  const all = [
    ['b1', 'mentat:builder', 'Build it'],
    ['e1', 'Explore', 'Look'],
    ['p1', 'Plan', 'Map it'],
    ['x1', 'general-purpose', 'Other thing'],
    ['f1', 'builder', 'Broke'],
    ['k1', 'Plan', 'Halted'],
    ['u1', 'Explore', 'Vanished'],
  ] as const
  world.agents = [row('z1', 'Explore', 'Never spawned here'), ...all.map(([id, type, description]) => row(id, type, description))]
  for (const [id, type, description] of all) await eng($).agent.spawn(spawn(id, description, type))
  expect(await lines($)).toEqual([])
  await clock.advance(83_000)
  // u1 leaves the engine's list, which ends it as unknown; the rest end.
  world.agents = [
    row('z1', 'Explore', 'Never spawned here', 'completed'),
    row('b1', 'mentat:builder', 'Build it', 'completed'),
    row('e1', 'Explore', 'Look', 'completed'),
    row('p1', 'Plan', 'Map it', 'completed'),
    row('x1', 'general-purpose', 'Other thing', 'completed'),
    row('f1', 'builder', 'Broke', 'failed'),
    row('k1', 'Plan', 'Halted', 'killed'),
  ]
  await eng($).turn.complete(turnDone('b1'))
  // A further sync finds them all ended: no line again.
  await eng($).turn.complete(turnDone('b1'))
  await clock.advance(5_000)
  expect(await written($)).toEqual([
    '✓ Explore finished: Never spawned here',
    '✓ Builder finished: Build it · 1m 23s',
    '✓ Explore finished: Look · 1m 23s',
    '✓ Plan finished: Map it · 1m 23s',
    '✓ general-purpose finished: Other thing · 1m 23s',
    '✕ Builder failed: Broke',
    '✕ Plan stopped: Halted',
  ])
})

test('an agent first listed already ended writes no line, and two agents with the same description each get one', async ($, on) => {
  const { world } = boot(on)
  await startSession($)
  world.agents = [{ id: 'old', type: 'Explore', description: 'Already over', status: 'completed' }]
  await eng($).turn.complete(turnDone('old'))
  expect(await lines($)).toEqual([])
  world.agents = [
    { id: 'a1', type: 'Explore', description: 'Check the docs', status: 'running' },
    { id: 'a2', type: 'Explore', description: 'Check the docs', status: 'running' },
  ]
  await eng($).agent.spawn(spawn('a1', 'Check the docs', 'Explore'))
  await eng($).agent.spawn(spawn('a2', 'Check the docs', 'Explore'))
  world.agents = world.agents.map(a => ({ ...a, status: 'completed' }))
  await eng($).turn.complete(turnDone('a1'))
  expect(await written($)).toEqual(['✓ Explore finished: Check the docs · 0s', '✓ Explore finished: Check the docs · 0s'])
})

test('open_decision writes an Asked line marked by the kind of item; two questions with the same text each get one', async ($, on) => {
  boot(on)
  await open(undefined, 'Ship it?')($)
  await open('question', 'Ship it?')($)
  await open('action', 'Merge #5 when ready')($)
  await open('alert', 'CI is red')($)
  expect(await written($)).toEqual(['? Asked you: Ship it?', '? Asked you: Ship it?', '→ Asked you: Merge #5 when ready', '! Asked you: CI is red'])
  // A refused call writes nothing.
  expect((await open('warning', 'Not allowed')($)).deny).toBeDefined()
  expect((await open(undefined, '  ')($)).deny).toBeDefined()
  expect(await lines($)).toHaveLength(4)
  for (const surface of SURFACES) {
    expect((await drawnRow($, surface, '?', 'Asked you: Ship it?')).colors).toContain('warning')
    expect((await drawnRow($, surface, '→', 'Asked you: Merge #5 when ready')).colors).toContain('suggestion')
    expect((await drawnRow($, surface, '!', 'Asked you: CI is red')).colors).toContain('error')
  }
})

test('the mod\'s own check items are not asked: a check writes its result line and no Asked line', async ($, on) => {
  const { world } = boot(on)
  await bash(world, $, 'mentat check', FAILED_RUN)
  await bash(world, $, 'mentat check', WARN_RUN)
  await bash(world, $, 'mentat check', CLEAN_RUN)
  expect(await written($)).toEqual(['✕ mentat check failed: 2 problems', '! mentat check passed with 2 warnings', '✓ mentat check passed'])
  await bash(world, $, 'mentat check', 'Check OK (1 warning(s))\nWARN: one\n')
  await bash(world, $, 'mentat check', 'Check failed: 1 problem(s)\n')
  expect((await lines($)).slice(0, 2)).toEqual(['✕ mentat check failed: 1 problem', '! mentat check passed with 1 warning'])
  // A run with neither final line records nothing, and neither does a subagent's.
  await bash(world, $, 'mentat check', 'usage: mentat check\n')
  await bash(world, $, 'mentat check', CLEAN_RUN, { agentId: 'a1' })
  expect(await lines($)).toHaveLength(5)
  for (const surface of SURFACES) {
    expect((await drawnRow($, surface, '✕', 'mentat check failed: 1 problem')).colors).toContain('error')
    expect((await drawnRow($, surface, '!', 'mentat check passed with 1 warning')).colors).toContain('warning')
    expect((await drawnRow($, surface, '✓', 'mentat check passed')).colors).toContain('success')
  }
})

test('the pane\'s own check at session start writes its result line', async ($, on) => {
  const { world } = boot(on)
  world.git = ok('true\n')
  world.check = ok(CLEAN_RUN)
  await startSession($)
  await until(() => world.calls.some(a => isCall(a, 'mentat', 'check')), 'the startup check')
  await new Promise(r => setTimeout(r, 30))
  expect(await lines($)).toEqual(['✓ mentat check passed'])
})

test('the check line is written only when the result changes: a repeat writes none, pass then warn writes two', async ($, on) => {
  const { world } = boot(on)
  await bash(world, $, 'mentat check', CLEAN_RUN)
  await bash(world, $, 'mentat check', CLEAN_RUN)
  expect(await written($)).toEqual(['✓ mentat check passed'])
  await bash(world, $, 'mentat check', WARN_RUN)
  expect(await written($)).toEqual(['✓ mentat check passed', '! mentat check passed with 2 warnings'])
  await bash(world, $, 'mentat check', WARN_RUN)
  expect(await lines($)).toHaveLength(2)
  // A different warning count is a different result.
  await bash(world, $, 'mentat check', 'Check OK (1 warning(s))\nWARN: one\n')
  expect((await lines($))[0]).toBe('! mentat check passed with 1 warning')
  await bash(world, $, 'mentat check', FAILED_RUN)
  await bash(world, $, 'mentat check', FAILED_RUN)
  expect(await lines($)).toHaveLength(4)
})

test('a reload with an unchanged check result writes no line; after /clear the next run writes one', async ($, on) => {
  const { world } = boot(on)
  world.git = ok('true\n')
  world.check = ok(CLEAN_RUN)
  await startSession($)
  await until(() => world.calls.some(a => isCall(a, 'mentat', 'check')), 'the startup check')
  await new Promise(r => setTimeout(r, 30))
  expect(await lines($)).toEqual(['✓ mentat check passed'])
  const runs = () => world.calls.filter(a => isCall(a, 'mentat', 'check')).length
  const before = runs()
  await startSession($)
  await until(() => runs() > before, 'the check after the reload')
  await new Promise(r => setTimeout(r, 30))
  expect(await lines($)).toEqual(['✓ mentat check passed'])
  // A new conversation has no result yet: its first run is a change.
  await classicOf($).SessionStart({ source: 'clear' })
  await until(() => runs() > before + 1, 'the check after /clear')
  await new Promise(r => setTimeout(r, 30))
  expect(await lines($)).toEqual(['✓ mentat check passed'])
})

test('pressing the answer button writes one You answered line once the prompt is taken, not before', async ($, on) => {
  const { world } = boot(on)
  const turn = held()
  world.promptGate = turn.gate
  await eng($).tool.call({ tool: OPEN, question: 'Mock it?', accept: 'Yes' })
  const band = await mount($, TERM, 'terminal')
  // Three presses, the last two before the drawing could have changed.
  const presses = [band.press({ key: 'accept-d1' }), band.press({ key: 'accept-d1' }), band.press({ key: 'accept-d1' })]
  await new Promise(r => setTimeout(r, 20))
  expect((await feedLines(band)).reverse()).toEqual(['? Asked you: Mock it?'])
  turn.release()
  await Promise.all(presses)
  expect(world.sent).toHaveLength(1)
  expect((await feedLines(band)).reverse()).toEqual(['? Asked you: Mock it?', '✓ You answered "Yes": Mock it?'])
  // Pressing again after the delivery does nothing more (the answered item has no answer button).
  expect(await bandKeys(band)).toEqual(['dismiss-d1'])
  expect(await feedLines(band)).toHaveLength(2)
  await band.unmount()
  for (const surface of SURFACES) expect((await drawnRow($, surface, '✓', 'You answered "Yes": Mock it?')).colors).toContain('success')
})

test('a submit that is dropped or rejected writes no answered line; the press that follows writes one', async ($, on) => {
  const { world } = boot(on)
  await eng($).tool.call({ tool: OPEN, question: 'Mock it?', accept: 'Yes' })
  const band = await mount($, TERM, 'terminal')
  world.dropPrompts = true
  await band.press({ key: 'accept-d1' })
  world.dropPrompts = false
  world.rejectPrompts = true
  await band.press({ key: 'accept-d1' })
  expect(world.sent).toEqual([])
  expect((await feedLines(band)).reverse()).toEqual(['? Asked you: Mock it?'])
  world.rejectPrompts = false
  await band.press({ key: 'accept-d1' })
  expect((await feedLines(band)).reverse()).toEqual(['? Asked you: Mock it?', '✓ You answered "Yes": Mock it?'])
  await band.unmount()
})

test('an answer whose delivery lands after a /clear, /resume or /branch writes nothing into the new log', async ($, on) => {
  const { world } = boot(on)
  await startSession($)
  for (const [n, source] of ['clear', 'resume', 'fork'].entries()) {
    const turn = held()
    world.promptGate = turn.gate
    await eng($).tool.call({ tool: OPEN, question: `Mock it ${source}?`, accept: 'Yes' })
    const band = await mount($, TERM, 'terminal')
    const press = band.press({ key: `accept-d${n + 1}` })
    await new Promise(r => setTimeout(r, 20))
    await classicOf($).SessionStart({ source })
    expect(await feedLines(band)).toEqual([])
    turn.release()
    await press
    // The prompt did enter the session, but the new conversation's log does not mention it.
    expect(world.sent).toHaveLength(n + 1)
    expect(await feedLines(band)).toEqual([])
    await band.unmount()
  }
  // A reload is the same conversation: the line is written.
  world.promptGate = undefined
  await eng($).tool.call({ tool: OPEN, question: 'After the reload?', accept: 'Yes' })
  const band = await mount($, TERM, 'terminal')
  await startSession($)
  await band.press({ key: 'accept-d4' })
  expect((await feedLines(band)).reverse()).toEqual(['? Asked you: After the reload?', '✓ You answered "Yes": After the reload?'])
  await band.unmount()
})

test('dismissing a question while its answer waits writes the dismissal now and the answer when it is taken', async ($, on) => {
  const { world } = boot(on)
  const turn = held()
  world.promptGate = turn.gate
  await eng($).tool.call({ tool: OPEN, question: 'Mock it?', accept: 'Yes' })
  const band = await mount($, TERM, 'terminal')
  const press = band.press({ key: 'accept-d1' })
  await new Promise(r => setTimeout(r, 20))
  await band.press({ key: 'dismiss-d1' })
  expect((await feedLines(band)).reverse()).toEqual(['? Asked you: Mock it?', '· You dismissed: Mock it?'])
  turn.release()
  await press
  expect((await feedLines(band)).reverse()).toEqual(['? Asked you: Mock it?', '· You dismissed: Mock it?', '✓ You answered "Yes": Mock it?'])
  await band.unmount()
})

test('Dismiss writes a dim You dismissed line, once; the dismissal of a check item counts too', async ($, on) => {
  const { world } = boot(on)
  await eng($).tool.call({ tool: OPEN, question: 'Gone soon?' })
  const band = await mount($, TERM, 'terminal')
  await band.press({ key: 'dismiss-d1' })
  await band.press({ key: 'dismiss-d1' }).catch(() => undefined)
  await band.unmount()
  expect(await written($)).toEqual(['? Asked you: Gone soon?', '· You dismissed: Gone soon?'])
  await bash(world, $, 'mentat check', FAILED_RUN)
  const alert = await mount($, TERM, 'terminal')
  await alert.press({ key: 'dismiss-check' })
  await alert.unmount()
  expect((await lines($))[0]).toBe('· You dismissed: Check failed: 2 problem(s)')
  for (const surface of SURFACES) {
    const drawn = await drawnRow($, surface, '·', 'You dismissed: Gone soon?')
    expect(drawn.colors).toContain('subtle')
    expect(drawn.dim).toEqual([true])
  }
})

test('close_decision on an open item writes a Closed line with its outcome when it has one; on one already dismissed or cleared, or unknown, it writes none', async ($, on) => {
  boot(on)
  await eng($).tool.call({ tool: OPEN, question: 'Merge it?' })
  await eng($).tool.call({ tool: OPEN, question: 'Merge it?' })
  await eng($).tool.call({ tool: OPEN, question: 'Closed third?' })
  await eng($).tool.call({ tool: OPEN, question: 'Cleared one?' })
  expect(String((await eng($).tool.call({ tool: CLOSE, id: 'd1', outcome: '  Yes, merge ' })).result)).toBe('Closed decision d1.')
  expect(String((await eng($).tool.call({ tool: CLOSE, id: 'd2' })).result)).toBe('Closed decision d2.')
  expect(String((await eng($).tool.call({ tool: CLOSE, id: 'd3', outcome: '   ' })).result)).toBe('Closed decision d3.')
  expect((await lines($)).slice(0, 3)).toEqual(['✓ Closed: Closed third?', '✓ Closed: Merge it?', '✓ Closed: Merge it? · Yes, merge'])

  // Already dismissed in the band, cleared by a new conversation, or closed twice: no line.
  const band = await mount($, TERM, 'terminal')
  await eng($).tool.call({ tool: OPEN, question: 'To dismiss?' })
  await band.press({ key: 'dismiss-d5' })
  await band.unmount()
  await eng($).tool.call({ tool: OPEN, question: 'To clear?' })
  await classicOf($).SessionStart({ source: 'clear' })
  expect(await lines($)).toEqual([])
  expect(String((await eng($).tool.call({ tool: CLOSE, id: 'd5', outcome: 'late' })).result)).toContain('already dismissed')
  expect(String((await eng($).tool.call({ tool: CLOSE, id: 'd6', outcome: 'late' })).result)).toContain('already cleared')
  expect((await eng($).tool.call({ tool: CLOSE, id: 'd1' })).deny).toBeDefined()
  expect((await eng($).tool.call({ tool: CLOSE, id: 'd99' })).deny).toBeDefined()
  expect(await lines($)).toEqual([])
})

test('gh pr create that prints a pull request URL writes Opened PR #N, from the URL itself; other commands write none', async ($, on) => {
  const { world } = boot(on)
  await startSession($)
  // The line comes from the URL the command printed; the pane reads nothing from GitHub.
  await bash(world, $, 'gh pr create --title "feat: x" --body y', `Creating pull request\n${GH}/pull/130\n`)
  expect(await written($)).toEqual(['↗ Opened PR #130'])
  await bash(world, $, 'gh pr create --title "feat: y"', 'something went wrong\n')
  await bash(world, $, 'gh pr ready 130', `${GH}/pull/130\n`)
  await bash(world, $, 'gh pr view 130', `${GH}/pull/130\n`)
  await bash(world, $, 'gh pr create --title "feat: z" --body y', `${GH}/pull/131\n`, { agentId: 'a1' })
  await new Promise(r => setTimeout(r, 30))
  expect(await written($)).toEqual(['↗ Opened PR #130'])
  for (const surface of SURFACES) expect((await drawnRow($, surface, '↗', 'Opened PR #130')).colors).toContain('suggestion')
})

test('events draw their text dim with their own mark and notes draw as before, on both surfaces', async ($, on) => {
  const { world } = boot(on)
  await startSession($)
  world.agents = [{ id: 'b1', type: 'builder', description: 'Build it', status: 'running' }, { id: 'b2', type: 'builder', description: 'Break it', status: 'running' }]
  await eng($).agent.spawn(spawn('b1', 'Build it', 'builder'))
  await eng($).agent.spawn(spawn('b2', 'Break it', 'builder'))
  world.agents = [{ id: 'b1', type: 'builder', description: 'Build it', status: 'completed' }, { id: 'b2', type: 'builder', description: 'Break it', status: 'failed' }]
  await eng($).turn.complete(turnDone('b1'))
  await note($, 'A plain note', 'done')
  await note($, 'Another note')
  for (const surface of SURFACES) {
    const done = await drawnRow($, surface, '✓', 'Builder finished: Build it · 0s')
    expect(done.colors).toContain('success')
    expect(done.dim).toEqual([true])
    const failedRow = await drawnRow($, surface, '✕', 'Builder failed: Break it')
    expect(failedRow.colors).toContain('error')
    expect(failedRow.dim).toEqual([true])
    expect((await drawnRow($, surface, '✓', 'A plain note')).dim).toEqual([false])
    expect((await drawnRow($, surface, '▸', 'Another note')).dim).toEqual([false])
  }
  // A note's text carries no dimColor at all.
  const pane = await mount($, PANE, 'terminal', { bodyColumns: 60 })
  expect((await pane.findAll({ type: 'Text', text: 'A plain note' }))[0]!.props?.dimColor).toBeUndefined()
  await pane.unmount()
})

test('the desktop band\'s line is the newest note, never an event; with only events it is the quiet Mentat line', async ($, on) => {
  boot(on)
  await startSession($)
  await eng($).tool.call({ tool: OPEN, question: 'Merge it?' })
  await eng($).tool.call({ tool: CLOSE, id: 'd1', outcome: 'yes' })
  expect((await lines($)).length).toBe(2)
  expect((await bandWith($, 'desktop')).texts).toEqual(['Mentat'])
  await note($, 'Keep this one', 'decision')
  await eng($).tool.call({ tool: OPEN, question: 'Another?' })
  await eng($).tool.call({ tool: CLOSE, id: 'd2' })
  expect((await lines($))[0]).toBe('✓ Closed: Another?')
  const { texts, alts } = await bandWith($, 'desktop')
  expect(texts).toEqual(['◆', 'Keep this one'])
  expect(alts).toEqual(['Note: Keep this one'])
  // The terminal has no band, so no line of Mentat's there.
  expect(await bandTexts($, 'terminal')).toEqual([])
})

test('an entry stored without a source is a note; a note written now has none, and an event says so', async ($, on) => {
  boot(on)
  expect(isNote({ at: 1, kind: 'plan', text: 'Stored before the Feed' })).toBe(true)
  expect(isNote({ at: 1, kind: 'plan', text: 'A note', source: 'note' })).toBe(true)
  expect(isNote({ at: 1, kind: 'asked', text: 'Asked you: x', source: 'event' })).toBe(false)
  // The state a note and an event are written as.
  let stored: unknown[] = []
  ;(on as (e: string, ...r: unknown[]) => void)('state.set', async (_$: never, e: { plugin: string; key: string; value: unknown[] }, next: (e: unknown) => unknown) => {
    if (e.plugin === 'mentat' && e.key === 'log') stored = e.value

    return next(e)
  })
  await note($, 'Plain')
  await eng($).tool.call({ tool: OPEN, question: 'Asked?', kind: 'alert' })
  expect(stored).toEqual([
    { at: T0, kind: 'plan', text: 'Plain' },
    { at: T0, kind: 'asked', text: 'Asked you: Asked?', source: 'event', mark: 'alert' },
  ])
})

test('an equal note straight after another is added once; an event between two equal notes, or two equal events, are all kept', async ($, on) => {
  boot(on)
  await note($, 'Same', 'waiting')
  await note($, 'Same', 'waiting')
  expect(await written($)).toEqual(['◌ Same'])
  await eng($).tool.call({ tool: OPEN, question: 'Q?' })
  await note($, 'Same', 'waiting')
  expect(await written($)).toEqual(['◌ Same', '? Asked you: Q?', '◌ Same'])
})

test('an event line is one line of at most 80 characters, and events count toward the 200-line cap', async ($, on) => {
  boot(on)
  await eng($).tool.call({ tool: OPEN, question: `Should we ${'really '.repeat(30)}go?` })
  const [row] = (await logOf($)).rows
  expect([...row!.text]).toHaveLength(80)
  expect(row!.text.startsWith('Asked you: Should we really')).toBe(true)
  expect(row!.text.endsWith('…')).toBe(true)
  for (let i = 0; i < 204; i++) await eng($).tool.call({ tool: OPEN, question: `Q${i}?` })
  expect((await logOf($)).toggle).toEqual(['Show all 200'])
})

test('note still refuses every event kind', async ($, on) => {
  boot(on)
  await startSession($)
  for (const kind of ['agentDone', 'agentFailed', 'asked', 'answered', 'dismissed', 'check', 'prOpened', 'event']) {
    expect((await note($, 'A line', kind)).deny).toBe('note kind must be decision, plan, surprise, waiting, done.')
  }
  expect(await lines($)).toEqual([])
})
