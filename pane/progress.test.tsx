import { expect, mock, test } from 'claude-code/testing'

import { CARD_TINT, isNote, resetAt, withoutSettled } from './progress'

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
// The desktop band's mark Svg(s) with the text beside it, in the shape a one-Svg band had: the alt reads
// `<mark>: <text> (+N more)` and the drawn texts are the glyph, the text and the pill.
const bandSvgs = async (d: Drawing) => {
  const texts = await d.findAll({ type: 'Text' })
  const text = texts[0]?.text ?? ''
  const more = (await d.findAll({ type: 'Box' })).some(b => b.key === 'more') ? texts[1]?.text : undefined

  return (await svgsOf(d)).map(m => ({
    ...m,
    alt: `${m.alt}: ${text}${more === undefined ? '' : ` (${more})`}`,
    drawn: [...m.drawn, text, ...(more === undefined ? [] : [more])],
  }))
}
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
  // The desktop pane lists it in its Waiting on you card, with the recommendation under it, as the terminal's does.
  const desk = await paneTexts($, 'desktop')
  expect(desk).toContain('Open the issue?')
  expect(desk.some(x => x.startsWith('Recommended: yes · '))).toBe(true)

  await eng($).tool.call({ tool: CLOSE, id: 'd1', outcome: 'opened' })
  expect(await bandTexts($, 'desktop')).toContain('Mentat')
  expect(await bandTexts($, 'desktop')).not.toContain('Open the issue?')
  const term = await paneTexts($, 'terminal')
  expect(term).not.toContain('Open the issue?')
  expect(term).not.toContain('WAITING ON YOU')
  expect(await paneTexts($, 'desktop')).not.toContain('WAITING ON YOU')
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

test('on the desktop the band and the pane are native rows with small Svg marks found by alt text; the terminal draws text', async ($, on) => {
  const { world } = boot(on)
  world.usage = { context: 41, limits: [{ kind: 'five_hour', percentUsed: 85, resetsAt: new Date(T0 + 3600_000).toISOString() }] }
  // Desktop band with nothing waiting: the budget warning is drawn, with a native Details button.
  const budgetBand = await mount($, BAND, 'desktop')
  const budgetSvg = await bandSvgs(budgetBand)
  expect(budgetSvg.map(v => v.alt)).toEqual(['Rate limit: 5-hour limit 85% · resets in 1h 0m'])
  expect((await budgetBand.findAll({ type: 'Button' })).map(b => b.key)).toEqual(['open'])
  await budgetBand.unmount()
  await eng($).tool.call({ tool: OPEN, question: 'Open it?', recommendation: 'Yes', accept: 'Yes' })
  world.agents = [{ id: 'a1', type: 'general-purpose', description: 'Check the docs', status: 'running' }]
  await eng($).agent.spawn(spawn('a1'))

  // Desktop band with the question open: it is the question that is drawn, with its answer button, Dismiss and Details.
  const band = await mount($, BAND, 'desktop')
  const bandSvg = await bandSvgs(band)
  expect(bandSvg.map(v => v.alt)).toEqual(['Question: Open it?'])
  expect(bandSvg[0]!.drawn).toEqual(['?', 'Open it?'])
  expect((await band.findAll({ type: 'Button' })).map(b => b.key)).toEqual(['accept-d1', 'dismiss-d1', 'open'])
  await band.unmount()

  // Desktop pane: native rows. The only Svg is the item's small mark; the agent is text. No usage tiles (the app's own popover shows those).
  const pane = await mount($, PANE, 'desktop', { bodyColumns: 60 })
  expect((await svgsOf(pane)).map(v => v.alt)).toEqual(['Question'])
  const t = await textsOf(pane)
  expect(t).toEqual(expect.arrayContaining(['WAITING ON YOU', 'Open it?', 'FEED', 'Check the docs']))
  // The budget is one warning line at the top, as in the terminal; no meters or tiles.
  expect(t.filter(x => /context|%/i.test(x))).toEqual(['5-hour limit 85% · resets in 1h 0m'])
  await pane.unmount()

  // The terminal draws no Svg at all, only text, and no band: the question and the agent are in its pane.
  const tBand = await mount($, BAND, 'terminal')
  expect(await textsOf(tBand)).toEqual([])
  await tBand.unmount()
  const tPane = await mount($, TERM, 'terminal')
  expect((await tPane.findAll({ type: 'Svg' })).length).toBe(0)
  const tt = await textsOf(tPane)
  expect(tt).toContain('Check the docs')
  expect(tt).toContain('Open it?')
  expect(tt.some(x => /[█░]|Context/.test(x))).toBe(false)
  await tPane.unmount()
})

test('the desktop band says +N more only when more than one item waits', async ($, on) => {
  boot(on)
  await eng($).tool.call({ tool: OPEN, question: 'Only one?' })
  let band = await mount($, BAND, 'desktop')
  let drawn = (await bandSvgs(band)).flatMap(v => v.drawn)
  expect(drawn).toContain('Only one?')
  expect(drawn.some(x => x.includes('more'))).toBe(false)
  await band.unmount()

  await eng($).tool.call({ tool: OPEN, question: 'And another?' })
  band = await mount($, BAND, 'desktop')
  drawn = (await bandSvgs(band)).flatMap(v => v.drawn)
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
  // No mark on the quiet line, and its text is muted.
  expect((await d.findAll({ type: 'Svg' })).length).toBe(0)
  expect((await d.findAll({ type: 'Text', text: 'Mentat' }))[0]!.props?.dimColor).toBe(true)
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
  world.agents = [{ id: 'a1', type: 'general-purpose', description: 'Check the docs', status: 'running' }]
  await eng($).agent.spawn(spawn('a1'))
  await clock.advance(65_000)
  await new Promise(r => setTimeout(r, 30))
  expect(stateOf(await paneTexts($), 'Check the docs')).toBe('running · 1m 05s')
  expect(deskLine(await paneTexts($, 'desktop'), 'Check the docs')).toEqual({ state: 'running', elapsed: '1m 05s' })

  world.agents = [{ id: 'a1', type: 'general-purpose', description: 'Check the docs', status: 'completed' }]
  await clock.advance(1_000)
  await new Promise(r => setTimeout(r, 30))
  // Ended: not in the Feed as an agent on either surface (its end is an event line, with the time it took).
  const t = await paneTexts($)
  expect(stateOf(t, 'Check the docs')).toBeUndefined()
  expect(t).toContain('general-purpose finished: Check the docs · 1m 06s')
  const desk = await paneTexts($, 'desktop')
  expect(deskLine(desk, 'Check the docs')).toBeUndefined()
  expect(desk).toContain('general-purpose finished: Check the docs · 1m 06s')
})

test('a turn that completes is not the end of a waiting agent', async ($, on) => {
  const { world, clock } = boot(on)
  await startSession($)
  world.agents = [{ id: 'a1', type: 'Explore', description: 'Look around', status: 'waiting' }]
  await eng($).agent.spawn(spawn('a1', 'Look around', 'Explore'))
  await eng($).turn.complete(turnDone('a1', { input_tokens: 100, cache_creation_input_tokens: 400, output_tokens: 500 }))
  await clock.advance(10_000)
  expect(stateOf(await paneTexts($), 'Look around')).toBe('waiting · 10s')
  expect(deskLine(await paneTexts($, 'desktop'), 'Look around')).toEqual({ state: 'waiting', elapsed: '10s' })

  await eng($).turn.complete(turnDone('a1'))
  await clock.advance(114_000)
  expect(stateOf(await paneTexts($), 'Look around')).toBe('waiting · 2m 04s')
  expect(deskLine(await paneTexts($, 'desktop'), 'Look around')).toEqual({ state: 'waiting', elapsed: '2m 04s' })
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
  // The desktop Feed lists the same agents in the same order, each with its state word in the time column.
  const d = await paneTexts($, 'desktop')
  expect(d.filter(x => x.startsWith('Agent '))).toEqual(order)
  for (const s of ['running', 'waiting', 'idle', 'pending']) expect(deskLine(d, `Agent ${s}`)?.state).toBe(s)
  for (const s of ['completed', 'failed', 'killed']) expect(deskLine(d, `Agent ${s}`)).toBeUndefined()
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
  const d = await paneTexts($, 'desktop')
  expect(deskLine(d, 'Known one')).toBeUndefined()
  expect(deskLine(d, 'Unseen one')).toEqual({ state: 'running', elapsed: undefined })
})

test('an agent that vanishes from the engine\'s list is ended, not finished: it leaves the Feed on both surfaces and writes no line', async ($, on) => {
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

// ---- the desktop Feed's agent rows ---------------------------------------------------

test('a live agent row on the desktop is the state word in blue, a dot, the bold description and its elapsed time; ended agents have none; the terminal Feed lists only the running one, not dimmed', async ($, on) => {
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
  const texts = await desktop.findAll({ type: 'Text' })
  await desktop.unmount()
  const all = texts.map(x => x.text)
  const i = all.indexOf('Still going')
  expect(all.slice(i - 2, i + 2)).toEqual(['running', '●', 'Still going', '1s'])
  const prop = (text: string, name: string) => texts.find(x => x.text === text)?.props?.[name]
  expect(prop('running', 'color')).toBe('suggestion')
  expect(prop('●', 'color')).toBe('suggestion')
  expect(prop('Still going', 'bold')).toBe(true)
  expect(prop('Still going', 'wrap')).toBe('truncate-end')
  expect(prop('1s', 'dimColor')).toBe(true)
  // Ended agents are not agent rows in the Feed: only their event lines (dim) say how they ended.
  expect(all).not.toContain('Finished fine')
  expect(all).not.toContain('Finished badly')
  expect(texts.find(x => x.text === 'general-purpose failed: Finished badly')?.props?.dimColor).toBe(true)

  const terminal = await mount($, PANE, 'terminal', { bodyColumns: 60 })
  const tTexts = await terminal.findAll({ type: 'Text' })
  await terminal.unmount()
  const dim = (t: string) => tTexts.find(x => x.text === t)?.props?.dimColor
  expect(dim('Still going')).toBeFalsy()
  expect(tTexts.some(x => x.text === 'Finished fine' || x.text === 'Finished badly')).toBe(false)
  expect(tTexts.find(x => x.text === 'general-purpose failed: Finished badly')?.props?.dimColor).toBe(true)
  // The state text is dim.
  expect(tTexts.find(x => /^running · /.test(x.text ?? ''))?.props?.dimColor).toBe(true)
})

// ---- the Feed's agent rows, on both surfaces ---------------------------

// What the desktop Feed draws for an agent: its state word in the time column and, when its start is known,
// the elapsed time after the description. undefined when the agent has no row.
const deskLine = (t: string[], description: string) => {
  const i = t.indexOf(description)
  if (i === -1) return undefined
  const next = t[i + 1]

  return { state: t[i - 2], elapsed: next !== undefined && /^\d+(s|m \d\ds)$/.test(next) ? next : undefined }
}
// Waits for the desktop pane to list each agent as the engine reports it: a live one with its state word, an ended one not at all.
const untilRowsAre = async ($: never, list: { description: string; status: string }[]) => {
  let seen: string[] = []
  for (let i = 0; i < 300; i++) {
    seen = await paneTexts($, 'desktop')
    if (list.every(a => (isEndedStatus(a.status) ? deskLine(seen, a.description) === undefined : deskLine(seen, a.description)?.state === a.status))) return
    await new Promise(r => setTimeout(r, 5))
  }
  throw new Error(`the rows never showed ${JSON.stringify(list)}; the desktop pane listed ${JSON.stringify(seen)}`)
}
// Puts agents in the world and waits for the engine's next check of its list to bring in their statuses.
const seedAgents = async (w: World, clock: { advance: (ms: number) => Promise<unknown> }, $: never, list: { id: string; type: string; description: string; status: string }[]) => {
  w.agents = list
  for (const a of list) await eng($).agent.spawn(spawn(a.id, a.description, a.type))
  await clock.advance(1_000)
  await untilRowsAre($, list)
}

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

test('the desktop Feed pins the live agents on top, working ones first, each with its state word, and no ended agent', async ($, on) => {
  const { world, clock } = boot(on)
  await startSession($)
  await seedAgents(world, clock, $, [
    { id: 'r1', type: 'Explore', description: 'First running', status: 'running' },
    { id: 'r2', type: 'Plan', description: 'Second running', status: 'waiting' },
    { id: 'i1', type: 'Plan', description: 'Idle one', status: 'idle' },
    { id: 'c1', type: 'builder', description: 'Finished fine', status: 'completed' },
  ])
  await eng($).tool.call({ tool: NOTE, text: 'A note' })
  const d = await mount($, PANE, 'desktop', { bodyColumns: 60 })
  const texts = await textsOf(d)
  const order = texts.filter(x => /^(First|Second) running$|^Idle one$|^A note$/.test(x))
  // Working agents first (the newest start first), then the idle one, then the log under them.
  expect(order.slice(0, 2).sort()).toEqual(['First running', 'Second running'])
  expect(order.slice(2)).toEqual(['Idle one', 'A note'])
  expect(texts).not.toContain('Finished fine')
  expect(texts[texts.indexOf('FEED') + 1]).toBe('5')
  expect(texts.some(x => x.startsWith('Running') || x.startsWith('Finished'))).toBe(false)
  expect((await d.findAll({ type: 'Button' })).map(b => b.key)).not.toContain('finished-toggle')
  await d.unmount()
})

// ---- agent lines without a start, usage and the empty pane --------------------------------------------------------------------------------

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

test('the pane shows no usage meters on either surface: no tiles, no bars; both panes carry the budget warning line', async ($, on) => {
  const { world } = boot(on)
  world.usage = { context: 41, limits: [limit('five_hour', 85, RESET_5H()), limit('seven_day', 8, RESET_WEEK())] }
  const usage = /context|session|week|[█░]/i
  // The desktop pane warns at 80% in one line at the top, as the terminal's does, and shows nothing else of usage.
  const desktop = await mount($, PANE, 'desktop', { bodyColumns: 60 })
  expect((await desktop.findAll({ type: 'Svg' })).length).toBe(0)
  const deskTexts = await textsOf(desktop)
  expect(deskTexts).toEqual(['5-hour limit 85% · resets in 1h 29m', 'Nothing waiting on you.'])
  expect((await desktop.findAll({ type: 'Text', text: '5-hour limit 85% · resets in 1h 29m' }))[0]!.props?.color).toBe('warning')
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
  // With something to show, still no meters; the desktop draws only its marks.
  await eng($).tool.call({ tool: OPEN, question: 'Anything?' })
  const withCard = await mount($, PANE, 'desktop', { bodyColumns: 60 })
  expect((await altsOf(withCard)).filter(a => !a.startsWith('Question'))).toEqual([])
  expect((await textsOf(withCard)).some(t => usage.test(t))).toBe(false)
  expect((await textsOf(withCard)).filter(t => /limit|resets|%/.test(t))).toEqual(['5-hour limit 85% · resets in 1h 29m'])
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
  world.agents = [{ id: 'a1', type: 'general-purpose', description: 'Done already', status: 'completed' }]
  await eng($).agent.spawn(spawn('a1', 'Done already'))
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
  world.agents = [{ id: 'a1', type: 'general-purpose', description: 'Working', status: 'running' }]
  await eng($).agent.spawn(spawn('a1', 'Working'))
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

test('an alert is red, with Dismiss and no answer button: in the terminal pane\'s Waiting on you and in the desktop band; the desktop pane lists it too', async ($, on) => {
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
  const [card] = await bandSvgs(desk)
  expect(card!.alt).toBe('Alert: CI is red and I cannot fix it')
  expect(card!.drawn).toEqual(['!', 'CI is red and I cannot fix it'])
  expect(card!.source).toContain(RED)
  expect(card!.source).not.toContain(AMBER)
  expect(await bandKeys(desk)).toEqual(['dismiss-d1'])
  await desk.unmount()

  // The desktop pane's Waiting on you card has it: a red mark, the text, Dismiss and no answer button.
  const pane = await mount($, PANE, 'desktop', { bodyColumns: 60 })
  const [mark] = await svgsOf(pane)
  expect(mark!.alt).toBe('Alert')
  expect(mark!.drawn).toEqual(['!'])
  expect(mark!.source).toContain(RED)
  expect(await textsOf(pane)).toEqual(expect.arrayContaining(['CI is red and I cannot fix it', 'Recommended: Look at the log · 8:00 AM']))
  expect(await bandKeys(pane)).toEqual(['dismiss-d1'])
  await pane.unmount()
})

test('an action is blue, with Dismiss and no answer button: in the terminal pane\'s Waiting on you and in the desktop band; the desktop pane lists it too', async ($, on) => {
  boot(on)
  await open('action', 'Merge #112 when ready', { accept: 'Yes' })($)
  const term = await mount($, TERM, 'terminal')
  expect(await textsOf(term)).toEqual(expect.arrayContaining(['→', 'Merge #112 when ready']))
  expect((await term.findAll({ type: 'Text', text: '→' }))[0]!.props?.color).toBe('suggestion')
  expect((await term.findAll({ type: 'Box' })).some(b => b.props?.backgroundColor !== undefined)).toBe(false)
  expect(await bandKeys(term)).toEqual(['dismiss-d1'])
  await term.unmount()

  const desk = await mount($, BAND, 'desktop')
  const [card] = await bandSvgs(desk)
  expect(card!.alt).toBe('Waiting on you: Merge #112 when ready')
  expect(card!.drawn).toEqual(['→', 'Merge #112 when ready'])
  expect(card!.source).toContain(BLUE)
  expect(await bandKeys(desk)).toEqual(['dismiss-d1'])
  await desk.unmount()

  const pane = await mount($, PANE, 'desktop', { bodyColumns: 60 })
  const [mark] = await svgsOf(pane)
  expect(mark!.alt).toBe('Waiting on you')
  expect(mark!.drawn).toEqual(['→'])
  expect(mark!.source).toContain(BLUE)
  expect(await textsOf(pane)).toContain('Merge #112 when ready')
  expect(await bandKeys(pane)).toEqual(['dismiss-d1'])
  await pane.unmount()
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
  const plainBand = await mount($, BAND, 'desktop')
  const plain = (await bandSvgs(plainBand))[0]!
  await plainBand.unmount()
  await eng($).tool.call({ tool: CLOSE, id: 'd1' })
  await open('question', 'Explicit?', { accept: 'Yes' })($)
  for (const surface of SURFACES) {
    const d = await mountWaits($, surface)
    expect(await bandKeys(d)).toEqual(['accept-d2', 'dismiss-d2'])
    expect(await textsOf(d)).toEqual(expect.arrayContaining(['?', 'Explicit?']))
    if (surface === 'desktop') {
      const [explicit] = await bandSvgs(d)
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

test('both panes list every item, most urgent first, with the WARN lines of the check under its item; neither has an answer field', async ($, on) => {
  const { world } = boot(on)
  await open('action', 'Action one', { link: 'https://github.com/o/r/pull/1' })($)
  await open(undefined, 'Question one', { accept: 'Yes' })($)
  await open('alert', 'Alert one')($)
  await bash(world, $, 'mentat check', WARN_RUN)
  for (const [surface, spec] of [['terminal', TERM], ['desktop', PANE]] as const) {
    const d = await mount($, spec, surface, { bodyColumns: 60 })
    const texts = await textsOf(d)
    const at = (x: string) => texts.indexOf(x)
    // Alert, question, check warning, action.
    expect([at('Alert one'), at('Question one'), at('Check passed with 2 warnings'), at('Action one')].every((n, i, all) => n > -1 && (i === 0 || n > all[i - 1]!))).toBe(true)
    // The check item's WARN lines come from the check result, one line each, under its time.
    expect(texts).toEqual(expect.arrayContaining(['WARN: gh is old', 'WARN: codex is old']))
    expect(at('Check passed with 2 warnings')).toBeLessThan(at('WARN: gh is old'))
    expect(at('WARN: gh is old')).toBeLessThan(at('WARN: codex is old'))
    expect(at('WARN: codex is old')).toBeLessThan(at('Action one'))
    expect((await d.findAll({ type: 'Input' })).length).toBe(0)
    expect(texts).not.toContain('Nothing waiting on you.')
    expect(await bandKeys(d)).toEqual(['dismiss-d3', 'accept-d2', 'dismiss-d2', 'dismiss-check', 'dismiss-d1'])
    await d.unmount()
  }
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
    // Both draw the link short: `#112`.
    expect(b.links.map(l => l.props?.label)).toEqual(['#112'])
    // Dismiss is drawn beside the link.
    expect(b.keys).toEqual(['dismiss-d1'])
  }
  await open('alert', 'Alert link', { link: `  ${url}  ` })($)
  // The desktop band shows the urgent item's link; the terminal pane every item's.
  expect((await bandOf('desktop')).hrefs).toEqual([url])
  expect((await bandOf('terminal')).hrefs).toEqual([url, url])
  // The desktop pane lists every item's, like the terminal's, drawn short and opening the whole address.
  const pane = await mount($, PANE, 'desktop', { bodyColumns: 60 })
  expect((await pane.findAll({ type: 'Link' })).map(l => [l.props?.href, l.props?.label])).toEqual([[url, '#112'], [url, '#112']])
  await pane.unmount()
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

test('the terminal pane draws a GitHub issue or pull request link as #<number>, any other link as its host, and the Link opens the whole address', async ($, on) => {
  boot(on)
  const cases: [string, string][] = [
    ['https://github.com/ericfurspan/mentat/issues/160', '#160'],
    ['https://github.com/o/r/pull/9', '#9'],
    ['https://github.com/other/repo/issues/12', '#12'],
    ['https://github.com/o/r/issues/7#issuecomment-1', '#7'],
    ['https://example.com/some/long/path?x=1', 'example.com'],
    ['https://github.com/o/r', 'github.com'],
    ['https://docs.example.org:8443/a', 'docs.example.org:8443'],
  ]
  for (const [i, [url, label]] of cases.entries()) {
    await open('action', `Rotate the token ${i}`, { link: url })($)
    const d = await mount($, TERM, 'terminal')
    const links = await d.findAll({ type: 'Link' })
    expect(links.map(l => [l.props?.href, l.props?.label])).toEqual([[url, label]])
    await d.unmount()
    await eng($).tool.call({ tool: CLOSE, id: `d${i + 1}` })
  }
})

test('a terminal row with a link keeps the mark and the space after it, and the text is what is cut', async ($, on) => {
  boot(on)
  await open('action', 'Rotate the token that the deploy job reads from the secrets store', { link: 'https://github.com/ericfurspan/mentat/issues/160' })($)
  for (const cols of [60, 85]) {
    const d = await mount($, PANE, 'terminal', { bodyColumns: cols })
    const boxes = await d.findAll({ type: 'Box' })
    // The mark is in a Box that does not shrink and has a margin after it, so a tight row cannot take the space away.
    const mark = boxes.find(b => b.key === 'mark-box')!
    expect(mark.props?.flexShrink).toBe(0)
    expect(mark.props?.marginRight).toBe(1)
    // The text can shrink and is cut with an ellipsis; the controls do not shrink.
    expect(boxes.find(b => b.key === 'text')?.props?.flexShrink).toBe(1)
    expect(boxes.find(b => b.key === 'controls')?.props?.flexShrink).toBe(0)
    const texts = await d.findAll({ type: 'Text' })
    expect(texts.find(t => t.text === 'Rotate the token that the deploy job reads from the secrets store')?.props?.wrap).toBe('truncate-end')
    // Left to right: the side line, the mark, the text, the short link, Dismiss, the side line.
    const all = texts.map(t => t.text)
    const i = all.indexOf('│ ')
    expect(all.slice(i, i + 6)).toEqual(['│ ', '→', 'Rotate the token that the deploy job reads from the secrets store', '#160', 'Dismiss', ' │'])
    await d.unmount()
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
  const out = { texts: await textsOf(d), alts: (await bandSvgs(d)).map(v => v.alt) }
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
  expect((await bandSvgs(desk))[0]!.source).toContain(RED)
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
    expect(texts).toEqual(['The tests read the old log', '!'])
    if (surface === 'desktop') expect(alts).toEqual(['Note: The tests read the old log'])
    expect(moreFor(texts)).toBeUndefined()
  }
  const term = await mount($, TERM, 'terminal')
  expect((await term.findAll({ type: 'Text', text: '!' }))[0]!.props?.color).toBe('warning')
  await term.unmount()
  const desk = await mount($, BAND, 'desktop')
  expect((await bandSvgs(desk))[0]!.source).toContain(AMBER)
  expect(await bandKeys(desk)).toEqual([])
  await desk.unmount()

  await note($, 'Merged', 'done')
  expect((await bandWith($, 'desktop')).texts).toEqual(['Merged', '✓'])

  // A budget warning outranks the note; with the limit gone the note is back.
  world.usage = { context: 5, limits: [limit('seven_day', 91, RESET_WEEK())] }
  expect((await bandWith($, 'desktop')).texts).toContain('Week limit 91% · resets Thu 7:00 PM')
  world.usage = { context: 5, limits: [limit('seven_day', 10)] }
  expect((await bandWith($, 'desktop')).texts).toEqual(['Merged', '✓'])

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
  const cards = (await bandSvgs(d)).filter(v => v.alt.startsWith('Alert'))
  await d.unmount()
  return cards
}
const HUE_AMBER = '#C98A0E'
const toastTexts = (w: World) => w.toasts.map(t => (JSON.parse(t) as { text: string }).text)

test('a failed mentat check pins one alert, with Dismiss, in the desktop band and in both panes', async ($, on) => {
  const { world } = boot(on)
  await bash(world, $, 'cd "a b" && mentat check 2>&1', FAILED_RUN)
  const [card, ...more] = await alertsOf($)
  expect(more).toEqual([])
  expect(card!.alt).toBe('Alert: Check failed: 2 problem(s)')
  expect(card!.drawn).toEqual(['!', 'Check failed: 2 problem(s)'])
  for (const surface of SURFACES) expect((await waitTexts($, surface)).includes('Check failed: 2 problem(s)')).toBe(true)
  // The desktop pane has it in its Waiting on you card.
  const pane = await paneTexts($, 'desktop')
  expect(pane).toEqual(expect.arrayContaining(['WAITING ON YOU', 'Check failed: 2 problem(s)']))
  // The PROBLEM lines are not drawn on either pane.
  expect((await waitTexts($, 'terminal')).some(x => x.includes('codex is not installed'))).toBe(false)
  expect(pane.some(x => x.includes('codex is not installed'))).toBe(false)
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
  expect(await bandTexts($)).toEqual(['Check failed: 1 problem(s)', '!'])
})

const WARN_RUN = 'OK: gh is installed\nWARN: gh is old\nWARN: codex is old\nCheck OK (2 warning(s))\n'
const CLEAN_RUN = 'OK: gh is installed\nCheck OK (0 warning(s))\n'
const SESSION_MODE = { plugin: 'mentat', component: 'SessionMode' }
// The footer label's words as one string (its Texts joined), on the terminal.
const footerTextOf = async ($: never) => (await footerOf($, 'terminal')).map(t => t.text).join('')
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
  const cards = (await bandSvgs(d)).filter(v => v.alt.startsWith('Check warnings'))
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
      { text: '●', color: 'warning', dim: false },
      { text: ' Mentat', color: undefined, dim: false },
      { text: ' · ', color: undefined, dim: true },
      { text: '1 waiting', color: 'warning', dim: false },
      { text: 'focus', color: undefined, dim: true },
    ])
  }
  await bash(world, $, 'mentat check', 'WARN: gh is old\nCheck OK (1 warning(s))\n')
  expect((await footerOf($, 'terminal')).slice(0, 4)).toEqual([
    { text: '●', color: 'warning', dim: false },
    { text: ' Mentat', color: undefined, dim: false },
    { text: ' · ', color: undefined, dim: true },
    { text: '1 waiting', color: 'warning', dim: false },
  ])

  await bash(world, $, 'mentat check', FAILED_RUN)
  for (const surface of SURFACES) {
    expect(await footerOf($, surface, ['focus'])).toEqual([
      { text: '●', color: 'error', dim: false },
      { text: ' Mentat', color: undefined, dim: false },
      { text: ' · ', color: undefined, dim: true },
      { text: '1 waiting', color: 'warning', dim: false },
      { text: 'focus', color: undefined, dim: true },
    ])
  }
  // A run that says nothing certain leaves the label as it was.
  await bash(world, $, 'mentat check', 'usage: mentat check\n')
  expect((await footerOf($, 'terminal'))[0]).toEqual({ text: '●', color: 'error', dim: false })
  // A subagent's check does not change it either.
  await bash(world, $, 'mentat check', CLEAN_RUN, { agentId: 'a1' })
  expect((await footerOf($, 'terminal'))[0]).toEqual({ text: '●', color: 'error', dim: false })
  expect(toastTexts(world)).toEqual([])
  // Dismissing the item leaves the label as today: red, with nothing waiting.
  const pane = await mount($, TERM, 'terminal')
  await pane.press({ key: 'dismiss-check' })
  await pane.unmount()
  expect(await footerOf($, 'terminal')).toEqual([{ text: '● Mentat check failed', color: 'error', dim: false }])
})

test('with items open the footer reads `● Mentat · N waiting` with only the dot in the check color, whatever the check said', async ($, on) => {
  const { world } = boot(on)
  // A warn check with its item open: the dot and the count are both amber, and the check's words are left out.
  await bash(world, $, 'mentat check', 'WARN: gh is old\nCheck OK (1 warning(s))\n')
  for (const surface of SURFACES) {
    expect(await footerOf($, surface)).toEqual([
      { text: '●', color: 'warning', dim: false },
      { text: ' Mentat', color: undefined, dim: false },
      { text: ' · ', color: undefined, dim: true },
      { text: '1 waiting', color: 'warning', dim: false },
    ])
    expect((await footerOf($, surface)).map(t => t.text).join('')).toBe('● Mentat · 1 waiting')
  }
  // A failed check with its item open: the dot is red.
  await bash(world, $, 'mentat check', FAILED_RUN)
  for (const surface of SURFACES) {
    const f = await footerOf($, surface)
    expect(f[0]).toEqual({ text: '●', color: 'error', dim: false })
    expect(f.map(t => t.text).join('')).toBe('● Mentat · 1 waiting')
  }
  // A clean pass with an agent question open: the dot is green; before any check it is dim.
  await bash(world, $, 'mentat check', CLEAN_RUN)
  await eng($).tool.call({ tool: OPEN, question: 'One?' })
  expect((await footerOf($, 'terminal'))[0]).toEqual({ text: '●', color: 'success', dim: false })
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
  expect(terminal.found).toEqual([{ key: 'mentat-open', label: '● Mentat · 3 waiting', plain: true }])
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
  // The desktop pane lists the warning with its WARN lines under it, one line each, then the action.
  const pane = await paneTexts($, 'desktop')
  const from = pane.indexOf('Check passed with 2 warnings')
  expect(pane.slice(from).filter(x => /^(WARN: |An action)/.test(x))).toEqual(['WARN: gh is old', 'WARN: codex is old', 'An action stays?'])
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

test('a warning count the output does not show is still counted: in the item and its WARN lines, and the footer counts the item', async ($, on) => {
  const { world } = boot(on)
  await bash(world, $, 'mentat check', 'WARN: seen\nCheck OK (2 warning(s))\n')
  expect(await footerTextOf($)).toBe('● Mentat · 1 waiting')
  const [card] = await checkItemsOf($)
  expect(card!.alt).toBe('Check warnings: Check passed with 2 warnings')
  // The terminal pane lists the line it saw and one for the warning whose text it did not.
  const seen = (await waitTexts($, 'terminal')).filter(t => t.startsWith('WARN: '))
  expect(seen).toEqual(['WARN: seen', 'WARN: A warning whose text was not in the output'])

  const warns = Array.from({ length: 8 }, (_, i) => `warning number ${i + 1}`)
  await bash(world, $, 'mentat check', `${warns.map(w => `WARN: ${w}`).join('\n')}\nCheck OK (8 warning(s))`)
  expect(await footerTextOf($)).toBe('● Mentat · 1 waiting')
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
  expect((await bandSvgs(desk))[0]!.source).toContain(HUE_AMBER)
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
  expect(await footerTextOf($)).toBe('● Mentat · 1 waiting')
  expect((await checkItemsOf($)).length).toBe(1)
  await classic.SessionStart({ source: 'startup' })
  await classic.SessionStart({ source: 'compact' })
  expect(await footerTextOf($)).toBe('● Mentat · 1 waiting')
  expect((await footerOf($, 'terminal'))[0]).toEqual({ text: '●', color: 'warning', dim: false })

  for (const source of ['clear', 'resume', 'fork']) {
    await bash(world, $, 'mentat check', FAILED_RUN)
    expect((await footerOf($, 'terminal'))[0]).toEqual({ text: '●', color: 'error', dim: false })
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

// ---- the Log (the Feed) ---------------------------------------------------------------------------------

const GH = 'https://github.com/o/r'
// The log rows the pane draws (newest first), as time, icon and text, and the label of the toggle button, if any.
const logOf = async ($: never, surface: 'terminal' | 'desktop' = 'terminal') => {
  const pane = await mount($, PANE, surface, { bodyColumns: 60 })
  const t = await textsOf(pane)
  const toggle = (await pane.findAll({ type: 'Button' })).filter(b => b.key === 'log-toggle').map(b => String(b.props?.label))
  const hasSvg = (await pane.findAll({ type: 'Svg' })).length > 0
  await pane.unmount()
  const rows: { time: string; icon: string; text: string }[] = []
  // The Feed on either surface: the pinned agents, then a time, an icon and the text per entry.
  for (let i = t.indexOf('FEED') + 1; i > 0 && i + 2 < t.length; i++) {
    if (!/^\d+:\d\d [AP]M$/.test(t[i]!)) continue
    rows.push({ time: t[i]!, icon: t[i + 1]!, text: t[i + 2]! })
    i += 2
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
  expect(await lines($, 'desktop')).toEqual(['▸ Next: the rules', '✓ The Log card is built', '◌ Waiting on your merge of #148', '! The mod tests also read the old log', '◆ Keep the band for #150', '▸ Only the Log changes in this pull request'])
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

// How many entries the Feed shows before `Show all`, on either surface.
const SHOWN = 10

test('the Feed shows the newest ten on both surfaces; Show all N shows the rest, Show fewer goes back, and the choice is kept', async ($, on) => {
  boot(on)
  await startSession($)
  for (let i = 1; i <= 12; i++) await note($, `Note ${i}`)
  for (const surface of SURFACES) {
    const first = await logOf($, surface)
    expect(first.rows.map(r => r.text)).toEqual(Array.from({ length: SHOWN }, (_, k) => `Note ${12 - k}`))
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
    expect(fewer.rows).toHaveLength(SHOWN)
    expect(fewer.toggle).toEqual(['Show all 12'])
  }
})

test('with no more entries than a surface shows there is no toggle; with none there is no Log or Feed section', async ($, on) => {
  boot(on)
  await startSession($)
  expect(await paneTexts($)).not.toContain('FEED')
  expect(await paneTexts($, 'desktop')).not.toContain('FEED')
  for (let i = 0; i < 10; i++) await note($, `Note ${i}`)
  const got = await logOf($)
  expect(got.rows).toHaveLength(10)
  expect(got.toggle).toEqual([])
  expect((await logOf($, 'desktop')).toggle).toEqual([])
  await note($, 'Note 10')
  expect((await logOf($)).toggle).toEqual(['Show all 11'])
  expect((await logOf($, 'desktop')).toggle).toEqual(['Show all 11'])
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

test('the log rows are plain native rows on both surfaces, with no Svg; the live agents are pinned above them', async ($, on) => {
  const { world } = boot(on)
  await startSession($)
  await eng($).tool.call({ tool: OPEN, question: 'Open one?' })
  await note($, 'A decision', 'decision')
  world.agents = [{ id: 'a1', type: 'Explore', description: 'Look around', status: 'running' }]
  await eng($).agent.spawn(spawn('a1', 'Look around', 'Explore'))
  for (const surface of SURFACES) {
    const pane = await mount($, PANE, surface, { bodyColumns: 60 })
    const t = await textsOf(pane)
    // The pinned agent sits above the Log rows, both under the Feed heading; the open item is in the section above.
    expect(t.indexOf('Look around')).toBeGreaterThan(t.indexOf('FEED'))
    expect(t.indexOf('Look around')).toBeLessThan(t.indexOf('A decision'))
    expect(t.indexOf('Open one?')).toBeLessThan(t.indexOf('FEED'))
    const rows = (await pane.findAll({ type: 'Box' })).filter(b => String(b.key).startsWith('log-'))
    // The note, and the line for the question the pane saw opened.
    expect(rows.length).toBeGreaterThanOrEqual(2)
    expect(rows.every(b => b.props?.backgroundColor === undefined)).toBe(true)
    // The log's marks are Text glyphs, not pictures.
    expect((await svgsOf(pane)).map(v => v.alt)).toEqual(surface === 'desktop' ? ['Question'] : [])
    await pane.unmount()
  }
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
  await untilFooter($, 'terminal', '●', 'warning')
  const cards = await checkItemsOf($)
  expect(cards.length).toBe(1)
  expect(cards[0]!.alt).toBe('Check warnings: Check passed with 2 warnings')
})

test('a session start with a failing check (exit 1) pins the alert and turns the label red', async ($, on) => {
  const { world } = boot(on)
  world.git = GIT_YES
  world.check = failedExit('PROBLEM: gh is not logged in\nCheck failed: 1 problem(s)\n')
  await startSession($)
  await untilFooter($, 'terminal', '●', 'error')
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
  await untilFooter($, 'terminal', '●', 'error')
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

test('the desktop band has one Box that holds the answer button, Dismiss, the link and Details, and it does not shrink', async ($, on) => {
  boot(on)
  await open('question', 'Ship it?', { accept: 'Yes' })($)
  const d = await mount($, BAND, 'desktop')
  // The buttons are in one Box that does not shrink or wrap; there is no second row of controls.
  const controls = (await d.findAll({ type: 'Box' })).filter(b => b.props?.flexShrink === 0 && b.props?.width === undefined)
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
  expect(texts).toEqual(['Keep this one', '◆'])
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

// ---- the desktop pane: two cards of native rows -----------------------------------------------------------------

const DESK = { ...PANE, props: { bodyColumns: 60 } }
// Opens two items (one with a recommendation and an answer, the check's warning item), an agent and some log.
const deskWorld = async ($: never, w: World) => {
  await startSession($)
  await eng($).tool.call({ tool: OPEN, question: 'Ship the change now?', recommendation: 'Yes, it passed', accept: 'Yes' })
  await bash(w, $, 'mentat check', WARN_RUN)
  await note($, 'A note for the Feed', 'decision')
  w.agents = [{ id: 'a1', type: 'builder', description: 'Build the pane', status: 'running' }]
  await eng($).agent.spawn(spawn('a1', 'Build the pane', 'builder'))
}

test('the desktop pane has a Waiting on you card and a Feed card, each with its heading and count and the card tint', async ($, on) => {
  const { world } = boot(on)
  await deskWorld($, world)
  const d = await mount($, DESK, 'desktop')
  const boxes = await d.findAll({ type: 'Box' })
  const waiting = boxes.find(b => b.key === 'card-waiting')!
  const feed = boxes.find(b => b.key === 'card-feed')!
  // The card surface is the one tint constant, on each card and nowhere else.
  expect(waiting.props?.backgroundColor).toBe(CARD_TINT)
  expect(feed.props?.backgroundColor).toBe(CARD_TINT)
  expect(boxes.filter(b => b.props?.backgroundColor !== undefined)).toHaveLength(2)
  expect(waiting.props?.flexDirection).toBe('column')
  expect(waiting.props?.borderStyle).toBe('round')
  // Headings: bold, Waiting on you in the warning color and Feed muted, the count dim. Two items; the agent, the
  // Asked line, the check line and the note make four Feed entries.
  const texts = await d.findAll({ type: 'Text' })
  const head = (title: string) => texts.findIndex(t => t.text === title)
  expect(texts[head('WAITING ON YOU')]!.props).toMatchObject({ bold: true, color: 'warning' })
  expect(texts[head('WAITING ON YOU') + 1]).toMatchObject({ text: '2', props: { dimColor: true } })
  expect(texts[head('FEED')]!.props).toMatchObject({ bold: true, color: 'subtle' })
  expect(texts[head('FEED') + 1]).toMatchObject({ text: '4', props: { dimColor: true } })
  expect(head('WAITING ON YOU')).toBeLessThan(head('FEED'))
  await d.unmount()
  // A card is left out when it has nothing: no open item, no Waiting on you card.
  await eng($).tool.call({ tool: CLOSE, id: 'd1' })
  await bash(world, $, 'mentat check', CLEAN_RUN)
  const t = await paneTexts($, 'desktop')
  expect(t).not.toContain('WAITING ON YOU')
  expect(t).toContain('FEED')
})

test('a desktop item row is a mark, the text that shrinks, the controls that do not, and under it the recommendation and the time', async ($, on) => {
  const { world } = boot(on)
  await deskWorld($, world)
  const d = await mount($, DESK, 'desktop')
  const boxes = await d.findAll({ type: 'Box' })
  const texts = await d.findAll({ type: 'Text' })
  // The text Box grows and shrinks and the Text is cut with an ellipsis; the controls keep their size.
  const row = boxes.find(b => b.key === 'item-d1')!
  expect(row.props?.flexDirection).toBe('column')
  expect(texts.find(t => t.text === 'Ship the change now?')?.props?.wrap).toBe('truncate-end')
  expect(boxes.filter(b => b.props?.flexGrow === 1 && b.props?.flexShrink === 1).length).toBeGreaterThan(0)
  expect(boxes.filter(b => b.props?.flexShrink === 0 && b.props?.flexDirection === 'row').length).toBeGreaterThan(0)
  // The line under the text is muted and cut; the check's item has its WARN lines each on one muted line.
  for (const line of ['Recommended: Yes, it passed · 8:00 AM', '8:00 AM', 'WARN: gh is old', 'WARN: codex is old']) {
    const t = texts.find(x => x.text === line)
    expect(t?.props).toMatchObject({ dimColor: true, wrap: 'truncate-end' })
  }
  // The pane reads left to right: the mark, the text, then the buttons, in the terminal's order.
  expect(await bandKeys(d)).toEqual(['accept-d1', 'dismiss-d1', 'dismiss-check'])
  const marks = await svgsOf(d)
  expect(marks.map(v => v.alt)).toEqual(['Question', 'Check warnings'])
  expect(marks.map(v => v.drawn)).toEqual([['?'], ['!']])
  expect(marks[0]!.source).toContain(AMBER)
  await d.unmount()
})

test('the desktop answer button is primary and sends the answer once; a sent answer shows its line in place of the button; Dismiss removes the item', async ($, on) => {
  const { world } = boot(on)
  await startSession($)
  await eng($).tool.call({ tool: OPEN, question: 'Mock it?', recommendation: 'Yes', accept: 'Yes' })
  await eng($).tool.call({ tool: OPEN, question: 'Drop it?' })
  const d = await mount($, DESK, 'desktop')
  const buttons = await d.findAll({ type: 'Button' })
  const accept = buttons.find(b => b.key === 'accept-d1')!
  expect(accept.props).toMatchObject({ label: 'Yes', variant: 'primary' })
  // Dismiss is a plain native button; only the answer is primary.
  expect(buttons.filter(b => b.props?.variant === 'primary')).toHaveLength(1)
  expect(buttons.find(b => b.key === 'dismiss-d1')?.props?.variant).toBeUndefined()
  await d.press({ key: 'accept-d1' })
  expect(world.sent).toEqual(['Answer to decision d1 ("Mock it?"): Yes'])
  await d.unmount()
  const after = await mount($, DESK, 'desktop')
  expect(await bandKeys(after)).toEqual(['dismiss-d2', 'dismiss-d1'])
  expect(await textsOf(after)).toContain('Sent: Yes')
  // Dismiss removes the item (and its sent line) and leaves a dim event line in the Feed.
  await after.press({ key: 'dismiss-d2' })
  await after.unmount()
  const t = await paneTexts($, 'desktop')
  expect(t).not.toContain('Drop it?')
  expect(t).toContain('Mock it?')
  expect(t).toContain('You dismissed: Drop it?')
})

test('the desktop pane draws a GitHub link as #<number> and any other as its host; the band does too', async ($, on) => {
  boot(on)
  await eng($).tool.call({ tool: OPEN, kind: 'action', question: 'Merge it', link: 'https://github.com/ericfurspan/mentat/issues/160' })
  await eng($).tool.call({ tool: OPEN, kind: 'alert', question: 'Read this', link: 'https://example.com/some/long/path' })
  const d = await mount($, DESK, 'desktop')
  expect((await d.findAll({ type: 'Link' })).map(l => [l.props?.href, l.props?.label])).toEqual([
    ['https://example.com/some/long/path', 'example.com'],
    ['https://github.com/ericfurspan/mentat/issues/160', '#160'],
  ])
  await d.unmount()
  // The band shows the most urgent item, the alert, with its link as the host.
  const band = await mount($, BAND, 'desktop')
  expect((await band.findAll({ type: 'Link' })).map(l => [l.props?.href, l.props?.label])).toEqual([['https://example.com/some/long/path', 'example.com']])
  await band.unmount()
  await eng($).tool.call({ tool: CLOSE, id: 'd2' })
  const github = await mount($, BAND, 'desktop')
  expect((await github.findAll({ type: 'Link' })).map(l => [l.props?.href, l.props?.label])).toEqual([['https://github.com/ericfurspan/mentat/issues/160', '#160']])
  await github.unmount()
})

test('the desktop Feed shows the newest ten with Show all N and Show fewer as a native button; notes are plain and events muted', async ($, on) => {
  boot(on)
  await startSession($)
  for (let i = 1; i <= 12; i++) await note($, `Note ${i}`)
  await eng($).tool.call({ tool: OPEN, question: 'An event comes?' })
  const d = await mount($, DESK, 'desktop')
  const buttons = await d.findAll({ type: 'Button' })
  const toggle = buttons.find(b => b.key === 'log-toggle')!
  expect(toggle.props?.label).toBe('Show all 13')
  expect((await d.findAll({ type: 'Text' })).filter(t => /^Note \d+$/.test(t.text ?? '')).length).toBe(9)
  const texts = await d.findAll({ type: 'Text' })
  // The newest entry is the Asked line (an event, muted); notes are in the full text color.
  expect(texts.find(t => t.text === 'Asked you: An event comes?')?.props?.dimColor).toBe(true)
  expect(texts.find(t => t.text === 'Note 12')?.props?.dimColor).toBeUndefined()
  await d.press({ key: 'log-toggle' })
  await d.unmount()
  const all = await mount($, DESK, 'desktop')
  expect((await textsOf(all)).filter(t => /^Note \d+$/.test(t))).toHaveLength(12)
  expect((await all.findAll({ type: 'Button' })).find(b => b.key === 'log-toggle')?.props?.label).toBe('Show fewer')
  await all.press({ key: 'log-toggle' })
  await all.unmount()
  expect((await textsOf(await mount($, DESK, 'desktop'))).filter(t => /^Note \d+$/.test(t))).toHaveLength(9)
})

test('the desktop pane puts the budget warning first, says Nothing waiting on you only when there is nothing else, and has no Svg wider than a mark', async ($, on) => {
  const { world } = boot(on)
  world.usage = { context: 41, limits: [limit('five_hour', 91, RESET_5H())] }
  const empty = await mount($, DESK, 'desktop')
  expect(await textsOf(empty)).toEqual(['5-hour limit 91% · resets in 1h 29m', 'Nothing waiting on you.'])
  expect((await empty.findAll({ type: 'Text', text: 'Nothing waiting on you.' }))[0]!.props?.dimColor).toBe(true)
  await empty.unmount()
  world.usage = { context: 41, limits: [] }
  await deskWorld($, world)
  await eng($).tool.call({ tool: OPEN, kind: 'action', question: 'A very long action that goes on and on past the end of the row, the way a real one can, and then some more words', link: 'https://github.com/o/r/pull/5' })
  await eng($).tool.call({ tool: OPEN, kind: 'alert', question: 'An alert' })
  for (let i = 0; i < 15; i++) await note($, `Note ${i}`)
  const drawn: string[] = []
  for (const cols of [30, 60, 140]) {
    const d = await mount($, PANE, 'desktop', { bodyColumns: cols })
    const svgs = await d.findAll({ type: 'Svg' })
    // One small mark per open item (four) and no picture of a card: the rows are native, so they follow the divider.
    expect(svgs).toHaveLength(4)
    for (const v of svgs) {
      expect(Number(v.props?.width)).toBeLessThanOrEqual(24)
      expect(Number(v.props?.height)).toBeLessThanOrEqual(24)
      expect(String(v.props?.alt)).not.toBe('')
    }
    // Nothing in the pane is measured from the width: the drawing is the same at any width.
    drawn.push(JSON.stringify(await textsOf(d)))
    await d.unmount()
  }
  expect(new Set(drawn).size).toBe(1)
})

test('every desktop Box that can shrink has minWidth 0, and the text Boxes hide their overflow, so a narrow pane cuts the text and not the card', async ($, on) => {
  const { world } = boot(on)
  await deskWorld($, world)
  await eng($).tool.call({ tool: OPEN, kind: 'action', question: 'Rotate the token that the deploy job reads from the secrets store', link: 'https://github.com/o/r/issues/160' })
  const d = await mount($, DESK, 'desktop')
  const boxes = await d.findAll({ type: 'Box' })
  await d.unmount()
  // Why: the desktop lays rows out with CSS flexbox, where a flex item's min-width is `auto` (its content's
  // width), so flexShrink alone never shrinks a Box below its text. minWidth 0 is what lets the text be cut
  // with an ellipsis, on the Box itself and on every Box between it and the card.
  const fixed = (b: { key?: string; props?: Record<string, unknown> }) =>
    b.props?.flexShrink === 0 || b.props?.width !== undefined || String(b.key).endsWith('-head') || b.key === 'log-more'
  const shrinking = boxes.filter(b => !fixed(b))
  expect(shrinking.length).toBeGreaterThan(10)
  for (const b of shrinking) expect({ key: b.key, minWidth: b.props?.minWidth }).toEqual({ key: b.key, minWidth: 0 })
  // The text Boxes are the ones that grow and shrink: they also hide the overflow.
  const text = boxes.filter(b => b.props?.flexShrink === 1)
  expect(text.length).toBeGreaterThanOrEqual(8)
  for (const b of text) expect(b.props).toMatchObject({ flexGrow: 1, minWidth: 0, overflow: 'hidden' })
  // The cards and the pane's outer column are among those with minWidth 0.
  for (const key of ['card-waiting', 'card-feed', 'item-d1', 'item-d2', 'item-check']) expect(boxes.find(b => b.key === key)?.props?.minWidth).toBe(0)
  // Marks (the 3-cell column), time columns and the button groups never shrink; a group holds the link.
  const widths = boxes.filter(b => b.props?.width !== undefined)
  expect(widths.length).toBeGreaterThan(0)
  for (const b of widths) expect(b.props?.flexShrink).toBe(0)
  const groups = boxes.filter(b => b.props?.flexShrink === 0 && b.props?.flexDirection === 'row')
  expect(groups.length).toBeGreaterThanOrEqual(3)
})

// ---- the desktop band: one native row ------------------------------------------------------------------------

test('the desktop band is one row of a mark, the text, the pill right after it, a spacer and the controls', async ($, on) => {
  boot(on)
  await open('question', 'Ship it?', { accept: 'Yes' })($)
  await open('question', 'And this?')($)
  const d = await mount($, BAND, 'desktop')
  const boxes = await d.findAll({ type: 'Box' })
  const keys = boxes.map(b => b.key).filter(k => ['mark', 'text', 'more', 'spacer'].includes(String(k)))
  // Left to right: the mark, the text, then the pill right after the text and before the spacer.
  expect(keys).toEqual(['mark', 'text', 'more', 'spacer'])
  const text = boxes.find(b => b.key === 'text')!
  expect(text.props).toMatchObject({ flexShrink: 1, minWidth: 0, overflow: 'hidden' })
  expect(boxes.find(b => b.key === 'spacer')?.props?.flexGrow).toBe(1)
  expect(boxes.find(b => b.key === 'more')?.props?.flexShrink).toBe(0)
  expect(boxes.find(b => b.key === 'mark')?.props?.flexShrink).toBe(0)
  // The text is cut with an ellipsis and bold; the pill is a Text in the warning color on a tint.
  const texts = await d.findAll({ type: 'Text' })
  expect(texts[0]).toMatchObject({ text: 'And this?', props: { bold: true, wrap: 'truncate-end' } })
  expect(texts[1]).toMatchObject({ text: '+1 more', props: { color: 'warning' } })
  expect(boxes.find(b => b.key === 'more')?.props?.backgroundColor).toBeDefined()
  // Every Box that can shrink has minWidth 0 (a flex item otherwise never shrinks below its content).
  for (const b of boxes.filter(b => b.props?.flexShrink !== 0 && b.props?.width === undefined && b.key !== 'engine-own' && b.key !== 'band')) {
    expect({ key: b.key, minWidth: b.props?.minWidth }).toEqual({ key: b.key, minWidth: 0 })
  }
  await d.unmount()
})

test('the desktop band has only a small mark for an Svg, and its tree does not depend on bodyColumns', async ($, on) => {
  const { world } = boot(on)
  const states: (() => Promise<unknown>)[] = [
    async () => undefined,
    async () => note($, 'A note', 'done'),
    async () => {
      world.usage = { context: 5, limits: [limit('five_hour', 95, RESET_5H())] }
    },
    async () => {
      await open('action', 'Rotate the token that the deploy job reads from the secrets store', { link: 'https://github.com/o/r/issues/160' })($)
      await open('alert', 'An alert')($)
    },
  ]
  const trees: string[] = []
  // Every state of the band, quiet to an item with its pill, at three widths.
  for (const setup of states) {
    await setup()
    const seen: string[] = []
    for (const cols of [30, 60, 140]) {
      const d = await mount($, BAND, 'desktop', { bodyColumns: cols })
      const svgs = await d.findAll({ type: 'Svg' })
      for (const v of svgs) {
        expect(Number(v.props?.width)).toBeLessThanOrEqual(24)
        expect(Number(v.props?.height)).toBeLessThanOrEqual(24)
        expect(String(v.props?.alt)).not.toBe('')
      }
      seen.push(JSON.stringify([await textsOf(d), (await d.findAll({ type: 'Box' })).map(b => b.props), svgs.map(v => v.props)]))
      await d.unmount()
    }
    expect(new Set(seen).size).toBe(1)
    trees.push(seen[0]!)
  }
  expect(new Set(trees).size).toBe(4)
})

test('the band marks a note in its color and the rate limit, and the quiet line has no mark', async ($, on) => {
  const { world } = boot(on)
  let d = await mount($, BAND, 'desktop')
  expect((await d.findAll({ type: 'Svg' })).length).toBe(0)
  await d.unmount()
  await note($, 'A surprise', 'surprise')
  d = await mount($, BAND, 'desktop')
  expect((await bandSvgs(d)).map(v => v.alt)).toEqual(['Note: A surprise'])
  expect((await bandSvgs(d))[0]!.source).toContain(AMBER)
  expect((await d.findAll({ type: 'Text' }))[0]!.props?.bold).toBeUndefined()
  await d.unmount()
  world.usage = { context: 5, limits: [limit('five_hour', 95, RESET_5H())] }
  d = await mount($, BAND, 'desktop')
  expect((await bandSvgs(d)).map(v => v.alt)).toEqual(['Rate limit: 5-hour limit 95% · resets in 1h 29m'])
  expect((await d.findAll({ type: 'Text' }))[0]!.props).toMatchObject({ color: 'warning', wrap: 'truncate-end' })
  await d.unmount()
})

test('the desktop band keeps minWidth off every Box above what the engine draws beneath it, which the engine refuses', async ($, on) => {
  boot(on)
  await open('question', 'Ship it?', { accept: 'Yes' })($)
  const d = await mount($, BAND, 'desktop')
  const boxes = await d.findAll({ type: 'Box' })
  await d.unmount()
  // The engine's own node (the mock draws a Box keyed engine-own) is in the drawing, so the band was not refused.
  expect(boxes.some(b => b.key === 'engine-own')).toBe(true)
  // The one Box that holds it is the band's outer column: it has no minWidth, and no other Box is above it.
  const outer = boxes.find(b => b.key === 'band')!
  expect(outer.props?.flexDirection).toBe('column')
  expect(outer.props?.minWidth).toBeUndefined()
  // The row inside it, which holds the shrinking text, keeps minWidth 0.
  expect(boxes.find(b => b.key === 'band-row')?.props?.minWidth).toBe(0)
})
