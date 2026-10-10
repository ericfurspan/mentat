import { expect, mock, test } from 'claude-code/testing'

import { CARD_TINT, isNote, resetAt, withoutSettled } from './progress'

// Tests for pane/progress.tsx. The test's hooks stand for the engine: `git` and `mentat check` are
// canned answers (nothing talks to GitHub), `$.agent.list` and `$.session.usage` are tables too, and the
// clock moves only when a test moves it.

const OPEN = 'mcp__mentat__open_decision'
const CLOSE = 'mcp__mentat__close_decision'
const NOTE = 'mcp__mentat__note'
// The band above the prompt: Mentat draws nothing there, so this is only what the engine and other plugins draw.
const BAND = { plugin: 'mentat', component: 'AbovePrompt', props: { hasSurvey: false } }
const PANE = { plugin: 'mentat', component: 'Pane', requestId: 'mentat' }
// The terminal pane at a width that draws frames.
const TERM = { ...PANE, props: { bodyColumns: 80 } }
// The desktop pane.
const DESK = { ...PANE, props: { bodyColumns: 60 } }
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
  // $.store, in memory: what a process left behind is what a test seeds (`boot(on, { store })`).
  store: Record<string, unknown>
  // When set, $.store.set rejects (a full or unwritable store); storeWrites counts the sets that went through.
  storeFails: boolean
  storeWrites: number
  // The tools the pane registered, as it described them.
  tools: { name: string; description: string; inputSchema: { required: string[]; properties: Record<string, { enum?: string[] }> }; isDeferred: boolean }[]
}

const isCall = (argv: string[], ...words: string[]) => words.every((w, i) => argv[i] === w)

// `band: false` leaves what the band draws beneath the plugin to the test.
const boot = (on: never, opts: { band?: boolean; zone?: string; store?: Record<string, unknown> } = {}) => {
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
    store: JSON.parse(JSON.stringify(opts.store ?? {})),
    storeFails: false,
    storeWrites: 0,
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
  onFn('store.get', (_$: unknown, e: { key: string }) => ({ value: world.store[e.key] }))
  onFn('store.set', (_$: unknown, e: { key: string; value: unknown }) => {
    if (world.storeFails) throw new Error('the store is full')
    world.storeWrites += 1
    world.store[e.key] = JSON.parse(JSON.stringify(e.value))
    return { value: undefined }
  })
  onFn('store.delete', (_$: unknown, e: { key: string }) => {
    delete world.store[e.key]
    return { value: undefined }
  })
  onFn('store.keys', () => ({ value: Object.keys(world.store) }))
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
// The keys of the answer buttons and Dismiss buttons of a drawing (of the terminal pane or the desktop pane).
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
// What the band above the prompt draws: nothing of Mentat's on either surface, so only what is beneath it.
const bandTexts = async ($: never, surface: 'terminal' | 'desktop' = 'desktop') => {
  const d = await mount($, BAND, surface)
  const t = await textsOf(d)
  await d.unmount()

  return t
}
// Where each surface shows what waits on the maintainer, with its buttons: the Waiting on you section of its pane
// (a card on the desktop, a bordered section on the terminal).
const WAITS = { terminal: TERM, desktop: DESK } as const
// Where each surface shows a budget warning: at the top of its pane.
const budgetTexts = ($: never, surface: 'terminal' | 'desktop') => paneTexts($, surface, 60)
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

// The engine's SessionStart. Each call is a new session id unless the test names one (`session_id`), as a
// /clear, a /branch and an in-app resume each begin under a new id; a compaction goes on under the same.
let sessionCount = 0
const classicOf = ($: never) => {
  const raw = ($ as never as { classic: { SessionStart: (a: { source: string; session_id?: string }) => Promise<unknown> } }).classic
  return {
    SessionStart: (a: { source: string; session_id?: string }) =>
      raw.SessionStart({ ...a, session_id: a.session_id ?? (a.source === 'compact' ? `s${sessionCount}` : `s${++sessionCount}`) }),
  }
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

test('an opened question shows in Waiting on you on both surfaces, and closing it leaves it out', async ($, on) => {
  boot(on)
  const opened = await eng($).tool.call({ tool: OPEN, question: 'Open the issue?', recommendation: 'yes' })
  expect(String(opened.result)).toContain('d1')

  // Mentat draws no band on either surface.
  for (const surface of SURFACES) expect(await bandTexts($, surface)).toEqual([])
  for (const surface of SURFACES) {
    const t = await waitTexts($, surface)
    expect(t).toContain('Open the issue?')
    expect(t.some(x => x.includes('more'))).toBe(false)
  }
  // Both panes have the recommendation under it.
  for (const surface of SURFACES) expect((await paneTexts($, surface)).some(x => x.startsWith('Recommended: yes · '))).toBe(true)

  await eng($).tool.call({ tool: CLOSE, id: 'd1', outcome: 'opened' })
  for (const surface of SURFACES) {
    const t = await paneTexts($, surface)
    expect(t).not.toContain('Open the issue?')
    expect(t).not.toContain('WAITING ON YOU')
  }
})

test('AbovePrompt draws nothing of Mentat\'s on either surface, whatever is open, near a limit or noted; what is beneath stays, and so does a survey', async ($, on) => {
  const { world } = boot(on, { band: false })
  on('ui.render', ($, e) => {
    const { Text } = $.ui.resolve(e)
    return <Text>another plugin's band</Text>
  })
  world.usage = { context: 5, limits: [{ kind: 'five_hour', percentUsed: 95, resetsAt: new Date(T0 + 3600_000).toISOString() }] }
  await eng($).tool.call({ tool: NOTE, text: 'A note' })
  await eng($).tool.call({ tool: OPEN, question: 'Keep both?', accept: 'Yes' })
  for (const surface of SURFACES) {
    for (const hasSurvey of [false, true]) {
      const d = await mount($, BAND, surface, { hasSurvey })
      expect(await textsOf(d)).toEqual(["another plugin's band"])
      expect((await d.findAll({ type: 'Button' })).length).toBe(0)
      expect((await d.findAll({ type: 'Svg' })).length).toBe(0)
      await d.unmount()
    }
  }
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
  expect(await waitTexts($, 'desktop')).toContain('Open before the load')
})

test('both panes list all the questions, newest first', async ($, on) => {
  boot(on)
  await eng($).tool.call({ tool: OPEN, question: 'First one?' })
  await eng($).tool.call({ tool: OPEN, question: 'Newest one?' })
  for (const surface of SURFACES) {
    const pane = await waitTexts($, surface)
    expect(pane.indexOf('Newest one?')).toBeGreaterThan(-1)
    expect(pane.indexOf('Newest one?')).toBeLessThan(pane.indexOf('First one?'))
    expect(pane.some(x => x.includes('more'))).toBe(false)
  }
})

test('the desktop pane is native rows with small Svg marks found by alt text; the terminal draws text; neither has a band', async ($, on) => {
  const { world } = boot(on)
  world.usage = { context: 41, limits: [{ kind: 'five_hour', percentUsed: 85, resetsAt: new Date(T0 + 3600_000).toISOString() }] }
  await eng($).tool.call({ tool: OPEN, question: 'Open it?', recommendation: 'Yes', accept: 'Yes' })
  world.agents = [{ id: 'a1', type: 'general-purpose', description: 'Check the docs', status: 'running' }]
  await eng($).agent.spawn(spawn('a1'))

  // Desktop pane: native rows. The only Svg is the item's small mark; the agent is text. No usage tiles (the app's own popover shows those).
  const pane = await mount($, DESK, 'desktop')
  expect((await svgsOf(pane)).map(v => v.alt)).toEqual(['Question'])
  expect((await pane.findAll({ type: 'Button' })).map(b => b.key)).toEqual(['accept-d1', 'dismiss-d1'])
  const t = await textsOf(pane)
  expect(t).toEqual(expect.arrayContaining(['WAITING ON YOU', 'Open it?', 'FEED', 'Check the docs']))
  // The budget is one warning line at the top, as in the terminal; no meters or tiles.
  expect(t.filter(x => /context|%/i.test(x))).toEqual(['5-hour limit 85% · resets in 1h 0m'])
  await pane.unmount()

  // The terminal draws no Svg at all, only text: the question and the agent are in its pane.
  const tPane = await mount($, TERM, 'terminal')
  expect((await tPane.findAll({ type: 'Svg' })).length).toBe(0)
  const tt = await textsOf(tPane)
  expect(tt).toContain('Check the docs')
  expect(tt).toContain('Open it?')
  expect(tt.some(x => /[█░]|Context/.test(x))).toBe(false)
  await tPane.unmount()
  // Neither surface has a band of Mentat's.
  for (const surface of SURFACES) expect(await bandTexts($, surface)).toEqual([])
})

test('a new conversation (clear, resume, branch) drops the open questions too; a reload and a compaction keep them', async ($, on) => {
  boot(on)
  const classic = classicOf($)
  for (const source of ['clear', 'resume', 'fork']) {
    await eng($).tool.call({ tool: OPEN, question: `Asked before ${source}?` })
    await classic.SessionStart({ source })
    for (const surface of SURFACES) {
      const t = await paneTexts($, surface)
      expect(t.some(x => x.includes('Asked before'))).toBe(false)
      expect(t).toContain('Nothing waiting on you.')
    }
  }
  // A startup begins a conversation; a reload, a repeated start of it and a compaction keep what it holds.
  await classic.SessionStart({ source: 'startup', session_id: 'kept' })
  await eng($).tool.call({ tool: OPEN, question: 'Kept?' })
  await startSession($)
  await classic.SessionStart({ source: 'startup', session_id: 'kept' })
  await classic.SessionStart({ source: 'compact' })
  for (const surface of SURFACES) expect(await waitTexts($, surface)).toContain('Kept?')
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
  // Each question is the newest when it is answered.
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
  const classic = classicOf($)
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
  classicOf($).SessionStart({ source })

test('close_decision on an item dismissed in the pane succeeds and names the time, on both surfaces', async ($, on) => {
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
  await classicOf($).SessionStart({ source: 'startup', session_id: 'here' })
  await eng($).tool.call({ tool: OPEN, question: 'Still here?' })
  await classicOf($).SessionStart({ source: 'startup', session_id: 'here' })
  await newConversation($, 'compact')
  expect(String((await eng($).tool.call({ tool: CLOSE, id: 'd1' })).result)).toBe('Closed decision d1.')
  expect((await eng($).tool.call({ tool: CLOSE, id: 'd1' })).deny).toContain('no record')
})

test('the record of items that left keeps the last 50, oldest dropped, and survives a reload of the pane', async ($, on) => {
  boot(on)
  for (let i = 1; i <= 52; i++) await eng($).tool.call({ tool: OPEN, question: `Question ${i}?` })
  // The pane lists the newest item first, so Dismiss takes d52, d51 ... d33 in turn; then /clear takes d1..d32.
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
  expect(await waitTexts($, 'desktop')).not.toContain('WAITING ON YOU')
  expect(await waitTexts($, 'terminal')).not.toContain('WAITING ON YOU')
  for (const surface of SURFACES) {
    // The record itself is never drawn, and the Feed has no trace of the dismissal.
    expect((await paneTexts($, surface)).filter(t => t.includes('dismissed'))).toEqual([])
  }
})

test('a check alert replaced or removed by a later run is not recorded', async ($, on) => {
  const { world } = boot(on)
  await bash(world, $, 'mentat check', FAILED_RUN)
  await bash(world, $, 'mentat check', FAILED_RUN)
  await bash(world, $, 'mentat check', 'Check OK (0 warning(s))')
  expect((await eng($).tool.call({ tool: CLOSE, id: 'check' })).deny).toContain('no record')
})

test('the accept button sends its label as the answer, once, in either pane; a sent question keeps only Dismiss', async ($, on) => {
  const { world } = boot(on)
  // d1 for the terminal pane and d2 for the desktop pane; d3 has no one-press answer.
  await eng($).tool.call({ tool: OPEN, question: 'Mock it?', recommendation: 'Yes', accept: 'Yes' })
  const first = await mount($, TERM, 'terminal')
  expect(await bandKeys(first)).toEqual(['accept-d1', 'dismiss-d1'])
  await first.press({ key: 'accept-d1' })
  await first.unmount()
  await eng($).tool.call({ tool: OPEN, question: 'Mock it?', recommendation: 'Yes', accept: 'Yes' })
  const second = await mount($, DESK, 'desktop')
  expect(await bandKeys(second)).toEqual(['accept-d2', 'dismiss-d2', 'dismiss-d1'])
  await second.press({ key: 'accept-d2' })
  await second.unmount()
  expect(world.sent).toEqual(['Answer to decision d1 ("Mock it?"): Yes', 'Answer to decision d2 ("Mock it?"): Yes'])

  await eng($).tool.call({ tool: OPEN, question: 'No one-press answer?' })
  // Sending an answer does not settle the question: the model closes it. Both panes list all three; the two sent
  // ones have only Dismiss.
  for (const [surface, spec] of [['terminal', TERM], ['desktop', DESK]] as const) {
    const pane = await mount($, spec, surface)
    expect(await bandKeys(pane)).toEqual(['dismiss-d3', 'dismiss-d2', 'dismiss-d1'])
    await pane.unmount()
  }
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
  for (const surface of SURFACES) expect((await paneTexts($, surface)).includes('Drop it?')).toBe(false)
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
  for (const surface of SURFACES) expect(await bandKeys(await mountWaits($, surface))).toEqual(['dismiss-d2', 'dismiss-d1'])
})

test('an open question is kept however many come after it', async ($, on) => {
  boot(on)
  for (let i = 1; i <= 60; i++) {
    await eng($).tool.call({ tool: OPEN, question: `Question ${i}?` })
  }
  const closed = await eng($).tool.call({ tool: CLOSE, id: 'd1' })
  expect(String(closed.result)).toBe('Closed decision d1.')
})

test('the footer label is a Button that opens the pane on both surfaces, in every state', async ($, on) => {
  const { world } = boot(on)
  for (const surface of SURFACES) {
    world.opened.length = 0
    const footer = await mount($, SESSION_MODE, surface, { modes: [] })
    expect((await footer.findAll({ type: 'Button' })).map(b => b.key)).toEqual(['mentat-open'])
    await footer.press({ key: 'mentat-open' })
    await footer.unmount()
    expect(world.opened).toEqual(['mentat'])
  }
  // With items open the label says so and still opens the pane.
  await eng($).tool.call({ tool: OPEN, question: 'Open it?' })
  await eng($).tool.call({ tool: OPEN, kind: 'action', question: 'And this' })
  for (const surface of SURFACES) {
    world.opened.length = 0
    const footer = await mount($, SESSION_MODE, surface, { modes: [] })
    const [button] = await footer.findAll({ type: 'Button' })
    expect(button).toMatchObject({ key: 'mentat-open', props: { plain: true, label: '● Mentat · 2 waiting' } })
    expect(await textsOf(footer)).toEqual(['●', ' Mentat', ' · ', '2 waiting'])
    await footer.press({ key: 'mentat-open' })
    await footer.unmount()
    expect(world.opened).toEqual(['mentat'])
  }
  // The pane says so when nothing waits.
  await eng($).tool.call({ tool: CLOSE, id: 'd1' })
  await eng($).tool.call({ tool: CLOSE, id: 'd2' })
  for (const surface of SURFACES) expect((await paneTexts($, surface)).includes('WAITING ON YOU')).toBe(false)
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
  expect(t).toContain('general-purpose finished: Check the docs')
  const desk = await paneTexts($, 'desktop')
  expect(deskLine(desk, 'Check the docs')).toBeUndefined()
  expect(desk).toContain('general-purpose finished: Check the docs')
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
  expect(t).toContain('general-purpose finished: Known one')
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
  expect(prop('Still going', 'wrap')).toBe('wrap')
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

test('a terminal agent line: role mark, bold wrapping title, then its state and elapsed time dim; no background', async ($, on) => {
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
  expect(build.props?.wrap).toBe('wrap')
  expect(build.props?.bold).toBe(true)
  expect(boxes.some(b => b.props?.backgroundColor !== undefined)).toBe(false)
  // The line reads: role mark, title, state and elapsed time.
  const all = texts.map(x => x.text)
  const i = all.indexOf('Build it')
  expect(all.slice(i - 1, i + 2)).toEqual(['◆', 'Build it', 'running · 1s'])
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
  // The terminal pane warns at 80%, in one line, and shows nothing else of usage.
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

// ---- the budget warning ------------------------------------------------------------

test('a rate limit at 80 shows at the top of both panes, and not at 79', async ($, on) => {
  const { world } = boot(on)
  world.usage = { context: 5, limits: [limit('five_hour', 79, RESET_5H()), limit('seven_day', 10)] }
  for (const surface of SURFACES) expect((await budgetTexts($, surface)).some(t => t.includes('limit'))).toBe(false)

  world.usage = { context: 5, limits: [limit('five_hour', 80, RESET_5H()), limit('seven_day', 10)] }
  for (const surface of SURFACES) expect(await budgetTexts($, surface)).toContain('5-hour limit 80% · resets in 1h 29m')
  // The warning is text: neither pane has a button for it.
  for (const surface of SURFACES) {
    const t = await mount($, PANE, surface, { bodyColumns: 60 })
    expect((await t.findAll({ type: 'Button' })).length).toBe(0)
    await t.unmount()
  }

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

test('the context meter alone does not raise a warning, and a failed usage read means none: the pane says nothing waits', async ($, on) => {
  const { world } = boot(on)
  world.usage = { context: 90, limits: [limit('five_hour', 12), limit('seven_day', 8)] }
  for (const surface of SURFACES) expect(await paneTexts($, surface)).toEqual(['Nothing waiting on you.'])

  world.usageFails = true
  for (const surface of SURFACES) expect(await paneTexts($, surface)).toEqual(['Nothing waiting on you.'])
})

test('a budget warning shows above the agents in both panes', async ($, on) => {
  const { world } = boot(on)
  world.usage = { context: 5, limits: [limit('five_hour', 90, RESET_5H())] }
  world.agents = [{ id: 'a1', type: 'general-purpose', description: 'Working', status: 'running' }]
  await eng($).agent.spawn(spawn('a1', 'Working'))
  for (const surface of SURFACES) {
    const t = await paneTexts($, surface)
    expect(t.indexOf('5-hour limit 90% · resets in 1h 29m')).toBe(0)
    expect(t).toContain('Working')
  }
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

test('an item that waits and the budget warning are both in the pane, the warning on top, and the warning stays when the item is closed', async ($, on) => {
  const { world } = boot(on)
  world.usage = { context: 5, limits: [limit('five_hour', 95, RESET_5H())] }
  await startSession($)
  await eng($).tool.call({ tool: OPEN, question: 'Ask first?' })
  for (const surface of SURFACES) {
    const pane = await paneTexts($, surface)
    expect(pane).toContain('Ask first?')
    expect(pane.indexOf('5-hour limit 95% · resets in 1h 29m')).toBe(0)
  }
  await eng($).tool.call({ tool: CLOSE, id: 'd1' })
  for (const surface of SURFACES) expect((await paneTexts($, surface)).some(x => x.includes('limit'))).toBe(true)
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

test('an alert is red, with Dismiss and no answer button, in the Waiting on you of both panes', async ($, on) => {
  boot(on)
  await open('alert', 'CI is red and I cannot fix it', { accept: 'Yes', recommendation: 'Look at the log' })($)
  const term = await mount($, TERM, 'terminal')
  const t = await textsOf(term)
  expect(t).toEqual(expect.arrayContaining(['!', 'CI is red and I cannot fix it', 'Recommended: Look at the log · 8:00 AM']))
  expect((await term.findAll({ type: 'Text', text: '!' }))[0]!.props?.color).toBe('error')
  expect((await term.findAll({ type: 'Box' })).some(b => b.props?.backgroundColor !== undefined)).toBe(false)
  expect(await bandKeys(term)).toEqual(['dismiss-d1'])
  await term.unmount()

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

test('an action is blue, with Dismiss and no answer button, in the Waiting on you of both panes', async ($, on) => {
  boot(on)
  await open('action', 'Merge #112 when ready', { accept: 'Yes' })($)
  const term = await mount($, TERM, 'terminal')
  expect(await textsOf(term)).toEqual(expect.arrayContaining(['→', 'Merge #112 when ready']))
  expect((await term.findAll({ type: 'Text', text: '→' }))[0]!.props?.color).toBe('suggestion')
  expect((await term.findAll({ type: 'Box' })).some(b => b.props?.backgroundColor !== undefined)).toBe(false)
  expect(await bandKeys(term)).toEqual(['dismiss-d1'])
  await term.unmount()

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
  const plainPane = await mount($, DESK, 'desktop')
  const plain = (await svgsOf(plainPane))[0]!
  await plainPane.unmount()
  await eng($).tool.call({ tool: CLOSE, id: 'd1' })
  await open('question', 'Explicit?', { accept: 'Yes' })($)
  for (const surface of SURFACES) {
    const d = await mountWaits($, surface)
    expect(await bandKeys(d)).toEqual(['accept-d2', 'dismiss-d2'])
    expect(await textsOf(d)).toEqual(expect.arrayContaining(['?', 'Explicit?']))
    if (surface === 'desktop') {
      const [explicit] = await svgsOf(d)
      expect(explicit!.alt).toBe('Question')
      expect(explicit!.source).toContain(AMBER)
      // The same mark for both.
      expect(plain.source).toBe(explicit!.source)
    }
    await d.unmount()
  }
})

test('an unknown kind is refused with a message and records nothing', async ($, on) => {
  boot(on)
  const refused = await eng($).tool.call({ tool: OPEN, kind: 'urgent', question: 'Now?' })
  expect(refused.deny).toBe('open_decision kind must be question, action or alert.')
  for (const surface of SURFACES) expect(await paneTexts($, surface)).toEqual(['Nothing waiting on you.'])
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
  // Both panes list every item's, drawn short and opening the whole address.
  for (const surface of SURFACES) expect((await bandOf(surface)).hrefs).toEqual([url, url])
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

test('a terminal row with a link keeps the mark and the space after it, and the text is what wraps', async ($, on) => {
  boot(on)
  await open('action', 'Rotate the token that the deploy job reads from the secrets store', { link: 'https://github.com/ericfurspan/mentat/issues/160' })($)
  for (const cols of [60, 85]) {
    const d = await mount($, PANE, 'terminal', { bodyColumns: cols })
    const boxes = await d.findAll({ type: 'Box' })
    // The mark is in a Box that does not shrink and has a margin after it, so a tight row cannot take the space away.
    const mark = boxes.find(b => b.key === 'mark-box')!
    expect(mark.props?.flexShrink).toBe(0)
    expect(mark.props?.marginRight).toBe(1)
    // The text can shrink and wraps under itself; the controls do not shrink.
    expect(boxes.find(b => b.key === 'text')?.props?.flexShrink).toBe(1)
    expect(boxes.find(b => b.key === 'controls')?.props?.flexShrink).toBe(0)
    const texts = await d.findAll({ type: 'Text' })
    expect(texts.find(t => t.text === 'Rotate the token that the deploy job reads from the secrets store')?.props?.wrap).toBe('wrap')
    // The first row is the mark and the text; under it, the time and then the short link and Dismiss.
    const all = texts.map(t => t.text)
    const i = all.indexOf('→')
    expect(all.slice(i, i + 5)).toEqual(['→', 'Rotate the token that the deploy job reads from the secrets store', '8:00 AM', '#160', 'Dismiss'])
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

// The order of the Waiting on you section, the budget warning above it and the notes in the Feed.
const indexIn = (t: string[], x: string) => t.indexOf(x)

test('both panes list what waits most urgent first, newest first within a kind, as each is closed; the budget is above and the notes are in the Feed', async ($, on) => {
  const { world } = boot(on)
  world.usage = { context: 5, limits: [limit('five_hour', 95, RESET_5H())] }
  await note($, 'A note too', 'done')
  await open('action', 'Do the thing')($)
  await open(undefined, 'Ask first?')($)
  await open('alert', 'Old alert')($)
  await open('alert', 'New alert')($)
  const ids = { action: 'd1', question: 'd2', old: 'd3', fresh: 'd4' }
  const order = async (surface: 'terminal' | 'desktop') => {
    const t = await paneTexts($, surface)
    return { t, waiting: ['New alert', 'Old alert', 'Ask first?', 'Do the thing'].filter(x => t.includes(x)) }
  }

  // Everything is open: the alerts first (the newest first), then the question, then the action. The budget
  // line is on top and the note is under the Feed heading.
  for (const surface of SURFACES) {
    const { t, waiting } = await order(surface)
    expect(waiting).toEqual(['New alert', 'Old alert', 'Ask first?', 'Do the thing'])
    expect(indexIn(t, '5-hour limit 95% · resets in 1h 29m')).toBe(0)
    expect(indexIn(t, 'A note too')).toBeGreaterThan(indexIn(t, 'FEED'))
    expect(indexIn(t, 'Do the thing')).toBeLessThan(indexIn(t, 'FEED'))
  }
  const term = await mount($, TERM, 'terminal')
  expect((await term.findAll({ type: 'Text', text: '!' }))[0]!.props?.color).toBe('error')
  expect((await term.findAll({ type: 'Box' })).some(b => b.props?.backgroundColor !== undefined)).toBe(false)
  await term.unmount()
  const desk = await mount($, DESK, 'desktop')
  expect((await svgsOf(desk))[0]!.source).toContain(RED)
  await desk.unmount()

  // The alerts closed: the question, then the action.
  await eng($).tool.call({ tool: CLOSE, id: ids.fresh })
  await eng($).tool.call({ tool: CLOSE, id: ids.old })
  for (const surface of SURFACES) expect((await order(surface)).waiting).toEqual(['Ask first?', 'Do the thing'])

  // The question closed: the action alone, with the budget still above it.
  await eng($).tool.call({ tool: CLOSE, id: ids.question })
  for (const surface of SURFACES) {
    const { t, waiting } = await order(surface)
    expect(waiting).toEqual(['Do the thing'])
    expect(indexIn(t, '5-hour limit 95% · resets in 1h 29m')).toBe(0)
  }

  // The action closed: the budget warning and the Feed, and no Waiting on you.
  await eng($).tool.call({ tool: CLOSE, id: ids.action })
  for (const surface of SURFACES) {
    const { t } = await order(surface)
    expect(t).not.toContain('WAITING ON YOU')
    expect(t).toContain('5-hour limit 95% · resets in 1h 29m')
  }

  // Under the limit: no warning.
  world.usage = { context: 5, limits: [limit('five_hour', 79, RESET_5H())] }
  for (const surface of SURFACES) expect((await paneTexts($, surface)).some(x => x.includes('limit'))).toBe(false)
})

test('a check warning comes before an action, and a question before the warning, in both panes', async ($, on) => {
  const { world } = boot(on)
  await open('action', 'Do the thing')($)
  await bash(world, $, 'mentat check', WARN_RUN)
  for (const surface of SURFACES) {
    const t = await paneTexts($, surface)
    expect(indexIn(t, 'Check passed with 2 warnings')).toBeGreaterThan(-1)
    expect(indexIn(t, 'Check passed with 2 warnings')).toBeLessThan(indexIn(t, 'Do the thing'))
  }
  await open(undefined, 'Ask first?')($)
  for (const surface of SURFACES) {
    const t = await paneTexts($, surface)
    expect(indexIn(t, 'Ask first?')).toBeLessThan(indexIn(t, 'Check passed with 2 warnings'))
  }
})

test('the Feed of both panes shows the notes newest first, each with its kind\'s icon and color, and a new conversation empties it', async ($, on) => {
  const { world } = boot(on)
  await startSession($)
  for (const surface of SURFACES) expect(await paneTexts($, surface)).toEqual(['Nothing waiting on you.'])

  await note($, 'Keep the notes for #150', 'decision')
  await note($, 'The tests read the old log', 'surprise')
  await note($, 'Merged', 'done')
  for (const surface of SURFACES) {
    expect(await lines($, surface)).toEqual(['✓ Merged', '! The tests read the old log', 'Keep the notes for #150'])
  }
  const term = await mount($, TERM, 'terminal')
  expect((await term.findAll({ type: 'Text', text: '!' }))[0]!.props?.color).toBe('warning')
  await term.unmount()
  const desk = await mount($, DESK, 'desktop')
  expect((await desk.findAll({ type: 'Text', text: '!' }))[0]!.props?.color).toBe('warning')
  expect(await bandKeys(desk)).toEqual([])
  await desk.unmount()

  // A budget warning is above the Feed, not instead of it.
  world.usage = { context: 5, limits: [limit('seven_day', 91, RESET_WEEK())] }
  for (const surface of SURFACES) {
    const t = await paneTexts($, surface)
    expect(t[0]).toBe('Week limit 91% · resets Thu 7:00 PM')
    expect(t).toContain('Merged')
  }
  world.usage = { context: 5, limits: [limit('seven_day', 10)] }

  // A new conversation empties the log.
  const classic = classicOf($)
  await classic.SessionStart({ source: 'clear' })
  for (const surface of SURFACES) expect(await paneTexts($, surface)).toEqual(['Nothing waiting on you.'])
})

test('a lone action is listed with its mark, its link and Dismiss and no count; a second item is listed beside it, in both panes', async ($, on) => {
  boot(on)
  await open('action', 'Run the plugin update', { link: 'https://github.com/o/r/pull/9' })($)
  for (const surface of SURFACES) {
    const t = await waitTexts($, surface)
    expect(t).toEqual(expect.arrayContaining(['→', 'Run the plugin update']))
    expect(t.some(x => /^\+\d+ more$/.test(x))).toBe(false)
    const d = await mountWaits($, surface)
    expect(await hrefsOf(d)).toEqual(['https://github.com/o/r/pull/9'])
    await d.unmount()
  }
  await open('action', 'Another')($)
  for (const [surface, spec] of [['terminal', TERM], ['desktop', DESK]] as const) {
    const pane = await mount($, spec, surface)
    expect(await keysOf(pane)).toEqual(['dismiss-d2', 'dismiss-d1'])
    await pane.unmount()
  }
})

test('/mentat opens the pane for an open action or alert', async ($, on) => {
  const { world } = boot(on)
  await open('action', 'Do it')($)
  await eng($).command.run({ command: 'mentat', args: '' })
  expect(world.opened).toEqual(['mentat'])
})

test('closing an alert or an action by id removes it, and a new conversation drops them too', async ($, on) => {
  boot(on)
  const classic = classicOf($)
  await open('alert', 'Down')($)
  await open('action', 'Do it')($)
  await eng($).tool.call({ tool: CLOSE, id: 'd1' })
  for (const surface of SURFACES) {
    expect(await waitTexts($, surface)).not.toContain('Down')
    expect(await waitTexts($, surface)).toContain('Do it')
  }
  await classic.SessionStart({ source: 'clear' })
  for (const surface of SURFACES) expect(await paneTexts($, surface)).toEqual(['Nothing waiting on you.'])
})

// ---- the `mentat check` signal ----------------------------------------------------------------

const FAILED_RUN = 'OK: gh is installed\nPROBLEM: codex is not installed\nPROBLEM: gh is not logged in\nCheck failed: 2 problem(s)\n'
// The marks of the alerts in the desktop pane's Waiting on you card.
const alertsOf = async ($: never) => {
  const d = await mount($, DESK, 'desktop')
  const cards = (await svgsOf(d)).filter(v => v.alt === 'Alert')
  await d.unmount()
  return cards
}
const HUE_AMBER = '#C98A0E'
const toastTexts = (w: World) => w.toasts.map(t => (JSON.parse(t) as { text: string }).text)

test('a failed mentat check pins one alert, with Dismiss, in both panes', async ($, on) => {
  const { world } = boot(on)
  await bash(world, $, 'cd "a b" && mentat check 2>&1', FAILED_RUN)
  const [card, ...more] = await alertsOf($)
  expect(more).toEqual([])
  expect(card!.drawn).toEqual(['!'])
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
  // The alert is above the agent's question, which stays listed beside it.
  const t = await paneTexts($, 'desktop')
  expect(t.indexOf('Check failed: 1 problem(s)')).toBeLessThan(t.indexOf('A question stays?'))
  expect(t.filter(x => x.startsWith('Check failed'))).toEqual(['Check failed: 1 problem(s)'])
  await eng($).tool.call({ tool: CLOSE, id: 'd1' })
  expect(await waitTexts($, 'desktop')).toContain('Check failed: 1 problem(s)')
  expect(await alertsOf($)).toHaveLength(1)
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
// The marks of the check warning items in the desktop pane's Waiting on you card.
const checkItemsOf = async ($: never) => {
  const d = await mount($, DESK, 'desktop')
  const cards = (await svgsOf(d)).filter(v => v.alt === 'Check warnings')
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
  for (const surface of SURFACES) expect(await paneTexts($, surface)).not.toContain('WAITING ON YOU')
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

test('the footer label counts every open item and is a Button that opens the pane, on both surfaces', async ($, on) => {
  const { world } = boot(on)
  const buttonsOf = async (surface: 'terminal' | 'desktop') => {
    const d = await mount($, SESSION_MODE, surface, { modes: [] })
    const found = (await d.findAll({ type: 'Button' })).map(b => ({ key: b.key, label: b.props?.label, plain: b.props?.plain }))
    const texts = (await d.findAll({ type: 'Text' })).map(t => ({ text: t.text, color: t.props?.color }))
    await d.unmount()
    return { found, texts }
  }
  // Nothing waits: the label is as it was, and opens the pane.
  for (const surface of SURFACES) expect((await buttonsOf(surface)).found).toEqual([{ key: 'mentat-open', label: '● Mentat', plain: true }])

  await eng($).tool.call({ tool: OPEN, question: 'One?' })
  await eng($).tool.call({ tool: OPEN, kind: 'action', question: 'Two' })
  await bash(world, $, 'mentat check', WARN_RUN)
  // Every open item counts, the check's warning item included.
  for (const surface of SURFACES) {
    const label = await buttonsOf(surface)
    expect(label.found).toEqual([{ key: 'mentat-open', label: '● Mentat · 3 waiting', plain: true }])
    expect(label.texts.find(t => t.text === '3 waiting')?.color).toBe('warning')

    world.opened.length = 0
    const footer = await mount($, SESSION_MODE, surface, { modes: [] })
    await footer.press({ key: 'mentat-open' })
    await footer.unmount()
    expect(world.opened).toEqual(['mentat'])
  }
  world.opened.length = 0
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

  // The warning is above the agent's action, which is listed beside it.
  const [card, ...more] = await checkItemsOf($)
  expect(more).toEqual([])
  expect(card!.drawn).toEqual(['!'])
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
  expect((await paneTexts($, 'desktop')).filter(x => x.startsWith('Check passed'))).toEqual(['Check passed with 1 warning'])

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
  expect(await paneTexts($, 'desktop')).toEqual(expect.arrayContaining(['→', 'An action stays?']))
  expect(toastTexts(world)).toEqual([])
})

test('a warning count the output does not show is still counted: in the item and its WARN lines, and the footer counts the item', async ($, on) => {
  const { world } = boot(on)
  await bash(world, $, 'mentat check', 'WARN: seen\nCheck OK (2 warning(s))\n')
  expect(await footerTextOf($)).toBe('● Mentat · 1 waiting')
  expect((await checkItemsOf($)).length).toBe(1)
  expect(await paneTexts($, 'desktop')).toContain('Check passed with 2 warnings')
  // The terminal pane lists the line it saw and one for the warning whose text it did not.
  const seen = (await waitTexts($, 'terminal')).filter(t => t.startsWith('WARN: '))
  expect(seen).toEqual(['WARN: seen', 'WARN: A warning whose text was not in the output'])

  const warns = Array.from({ length: 8 }, (_, i) => `warning number ${i + 1}`)
  await bash(world, $, 'mentat check', `${warns.map(w => `WARN: ${w}`).join('\n')}\nCheck OK (8 warning(s))`)
  expect(await footerTextOf($)).toBe('● Mentat · 1 waiting')
  expect((await checkItemsOf($)).length).toBe(1)
  expect(await paneTexts($, 'desktop')).toContain('Check passed with 8 warnings')
  expect((await waitTexts($, 'terminal')).filter(t => t.startsWith('WARN: '))).toEqual(warns.map(w => `WARN: ${w}`))
})

test('both panes put the alert first, then the question, then the check warning, then the action, as each is closed in turn', async ($, on) => {
  const { world } = boot(on)
  await open('action', 'Do the thing')($)
  await bash(world, $, 'mentat check', WARN_RUN)
  await open(undefined, 'Ask first?')($)
  await open('alert', 'Down')($)
  const first = async (surface: 'terminal' | 'desktop') => {
    const t = await paneTexts($, surface)
    return ['Down', 'Ask first?', 'Check passed with 2 warnings', 'Do the thing'].filter(x => t.includes(x))
  }
  for (const surface of SURFACES) expect(await first(surface)).toEqual(['Down', 'Ask first?', 'Check passed with 2 warnings', 'Do the thing'])
  await eng($).tool.call({ tool: CLOSE, id: 'd3' })
  for (const surface of SURFACES) expect(await first(surface)).toEqual(['Ask first?', 'Check passed with 2 warnings', 'Do the thing'])
  await eng($).tool.call({ tool: CLOSE, id: 'd2' })
  for (const surface of SURFACES) expect(await first(surface)).toEqual(['Check passed with 2 warnings', 'Do the thing'])
  await bash(world, $, 'mentat check', CLEAN_RUN)
  for (const surface of SURFACES) expect(await first(surface)).toEqual(['Do the thing'])
})

test('the agent cannot open a warning: open_decision refuses the kind and records nothing', async ($, on) => {
  boot(on)
  const refused = await eng($).tool.call({ tool: OPEN, kind: 'warning', question: 'Careful?' })
  expect(refused.deny).toBe('open_decision kind must be question, action or alert.')
  for (const surface of SURFACES) expect(await paneTexts($, surface)).toEqual(['Nothing waiting on you.'])
})

test('the check warning comes after an alert and a question and before an action, with the budget above them', async ($, on) => {
  const { world } = boot(on)
  world.usage = { context: 5, limits: [limit('five_hour', 95, RESET_5H())] }
  await open('action', 'Do the thing')($)
  await bash(world, $, 'mentat check', WARN_RUN)
  const order = async (surface: 'terminal' | 'desktop') => {
    const t = await paneTexts($, surface)
    return ['Check failed: 2 problem(s)', 'Ask first?', 'Check passed with 2 warnings', 'Do the thing'].filter(x => t.includes(x))
  }

  // The warning is above the action; the budget is above both.
  for (const surface of SURFACES) {
    expect(await order(surface)).toEqual(['Check passed with 2 warnings', 'Do the thing'])
    expect((await paneTexts($, surface)).indexOf('5-hour limit 95% · resets in 1h 29m')).toBe(0)
  }
  const term = await mount($, TERM, 'terminal')
  expect((await term.findAll({ type: 'Text', text: '!' }))[0]!.props?.color).toBe('warning')
  expect((await term.findAll({ type: 'Box' })).some(b => b.props?.backgroundColor !== undefined)).toBe(false)
  await term.unmount()
  const desk = await mount($, DESK, 'desktop')
  expect((await svgsOf(desk))[0]!.source).toContain(HUE_AMBER)
  await desk.unmount()

  // A question is above the warning.
  await open(undefined, 'Ask first?')($)
  for (const surface of SURFACES) expect(await order(surface)).toEqual(['Ask first?', 'Check passed with 2 warnings', 'Do the thing'])
  // An alert (the failed check replaces the warning) is above the question.
  await bash(world, $, 'mentat check', FAILED_RUN)
  for (const surface of SURFACES) expect(await order(surface)).toEqual(['Check failed: 2 problem(s)', 'Ask first?', 'Do the thing'])

  // Back to the warning, then a clean pass: the question is gone too, so the action is left.
  await bash(world, $, 'mentat check', WARN_RUN)
  await eng($).tool.call({ tool: CLOSE, id: 'd2' })
  await bash(world, $, 'mentat check', CLEAN_RUN)
  for (const surface of SURFACES) expect(await order(surface)).toEqual(['Do the thing'])
})

test('a new conversation drops the check result and its warning card, and a mod reload keeps them', async ($, on) => {
  const { world } = boot(on)
  const classic = classicOf($)
  await classic.SessionStart({ source: 'startup', session_id: 'kept' })
  await bash(world, $, 'mentat check', WARN_RUN)
  await startSession($)
  expect(await footerTextOf($)).toBe('● Mentat · 1 waiting')
  expect((await checkItemsOf($)).length).toBe(1)
  await classic.SessionStart({ source: 'startup', session_id: 'kept' })
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
  const d = await mount($, DESK, 'desktop')
  await d.press({ key: 'dismiss-check' })
  await d.unmount()
  expect(await alertsOf($)).toEqual([])
  expect(await paneTexts($, 'desktop')).not.toContain('WAITING ON YOU')

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
  expect(card!.drawn).toEqual(['!'])
  for (const surface of SURFACES) {
    const t = await paneTexts($, surface)
    expect(t).toContain('Check failed: 9 problem(s)')
    expect(t.some(x => x.includes('problem number'))).toBe(false)
  }
})

// ---- the Log (the Feed) ---------------------------------------------------------------------------------

const GH = 'https://github.com/o/r'
// A pull request opened by the main loop: the cheapest event line the pane writes (its own, not an agent's).
const pr = async (world: World, clock: { settle: () => Promise<void> }, $: never, n: number) => {
  await bash(world, $, 'gh pr create --title t --body x', `${GH}/pull/${n}\n`)
  await clock.settle()
}
// The Feed's log rows from the Texts of a drawing, newest first, as time, mark and text. Each row has all three
// Texts: the time is blank (a space) after the first row of a run of the same time and the mark is a space for
// an entry with none; both read back as ''. The one space between the pinned agents and the log is skipped.
const feedRowsOf = (t: string[]) => {
  const rows: { time: string; icon: string; text: string }[] = []
  for (let i = t.indexOf('FEED') + 1; i > 0 && i + 2 < t.length; i++) {
    const isTime = /^\d+:\d\d [AP]M$/.test(t[i]!)
    if (!isTime && !(t[i] === ' ' && !/^\d+:\d\d [AP]M$/.test(t[i + 1]!))) continue
    rows.push({ time: t[i]!.trim(), icon: t[i + 1]!.trim(), text: t[i + 2]! })
    i += 2
  }

  return rows
}
// The log rows the pane draws (newest first), as time, icon and text, and the label of the toggle button, if any.
const logOf = async ($: never, surface: 'terminal' | 'desktop' = 'terminal') => {
  const pane = await mount($, PANE, surface, { bodyColumns: 60 })
  const t = await textsOf(pane)
  const toggle = (await pane.findAll({ type: 'Button' })).filter(b => b.key === 'log-toggle').map(b => String(b.props?.label))
  const hasSvg = (await pane.findAll({ type: 'Svg' })).length > 0
  await pane.unmount()

  return { rows: feedRowsOf(t), toggle, hasSvg }
}
// The Feed rows of a terminal pane that is already mounted (only one can be at a time), newest first, as icon and text.
const lineOf = (r: { icon: string; text: string }) => (r.icon === '' ? r.text : `${r.icon} ${r.text}`)
const feedLines = async (d: Drawing) => feedRowsOf(await textsOf(d)).map(lineOf)
const lines = async ($: never, surface: 'terminal' | 'desktop' = 'terminal') => (await logOf($, surface)).rows.map(lineOf)
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
  expect((await logOf($)).rows).toEqual([{ time: '8:00 AM', icon: '', text: 'Only the Log changes in this pull request' }])
  await note($, 'Keep the band for #150', 'decision')
  await note($, 'The mod tests also read the old log', 'surprise')
  await note($, 'Waiting on your merge of #148', 'waiting')
  await note($, 'The Log card is built', 'done')
  await note($, 'Next: the rules', 'plan')
  expect(await lines($, 'desktop')).toEqual(['Next: the rules', '✓ The Log card is built', 'Waiting on your merge of #148', '! The mod tests also read the old log', 'Keep the band for #150', 'Only the Log changes in this pull request'])
})

test('each kind has its own icon and color on both surfaces', async ($, on) => {
  boot(on)
  await startSession($)
  // Only a done note (success) and a surprise (attention) are marked; the others have a blank mark.
  const kinds = [['decision', ''], ['plan', ''], ['surprise', '!'], ['waiting', ''], ['done', '✓']] as const
  for (const [kind] of kinds) await note($, `A ${kind} note`, kind)
  for (const surface of SURFACES) {
    const rows = (await logOf($, surface)).rows
    for (const [kind, icon] of kinds) expect(rows.find(r => r.text === `A ${kind} note`)?.icon).toBe(icon)
    expect((await drawnRow($, surface, '✓', 'A done note')).colors).toContain('success')
    expect((await drawnRow($, surface, '!', 'A surprise note')).colors).toContain('warning')
  }
})

test('a note is one line, kept in full and wrapped; only past the 1000 character limit is it cut with an ellipsis', async ($, on) => {
  boot(on)
  await startSession($)
  const long = `Moving the ${'very long '.repeat(20)}plan`
  await note($, long)
  for (const surface of SURFACES) {
    const [row] = (await logOf($, surface)).rows
    expect(row!.text).toBe(long.replace(/\s+$/, ''))
    expect([...row!.text].length).toBeGreaterThan(80)
    const pane = await mount($, PANE, surface, { bodyColumns: 60 })
    expect((await pane.findAll({ type: 'Text', text: row!.text }))[0]!.props?.wrap).toBe('wrap')
    await pane.unmount()
  }
  // Runs of spaces and line breaks make one line.
  await note($, 'two   words\nand a third line')
  expect((await lines($))[0]).toBe('two words and a third line')
  // Exactly the limit is kept whole; past it the line is cut with an ellipsis.
  await note($, 'x'.repeat(1000))
  expect([...(await logOf($)).rows[0]!.text]).toHaveLength(1000)
  expect((await logOf($)).rows[0]!.text.endsWith('…')).toBe(false)
  await note($, 'y'.repeat(2000))
  const cut = (await logOf($)).rows[0]!.text
  expect([...cut]).toHaveLength(1000)
  expect(cut.startsWith('yyyy')).toBe(true)
  expect(cut.endsWith('…')).toBe(true)
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
  expect(await lines($)).toEqual(['Waiting on you'])
  await note($, 'Waiting on you', 'plan')
  await note($, 'Waiting on you', 'waiting')
  expect(await lines($)).toEqual(['Waiting on you', 'Waiting on you', 'Waiting on you'])
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
  // Only the pane's own events: the PR opened and the builder done (a closed item writes none).
  expect(await lines($)).toEqual(['✓ Builder finished: Build the log', 'Opened PR #130'])
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
    // The note alone: opening a question writes no line.
    expect(rows.length).toBe(1)
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
  const classic = classicOf($)
  await classic.SessionStart({ source: 'startup', session_id: 'kept' })
  await startSession($)
  await note($, 'Before')
  await startSession($)
  await classic.SessionStart({ source: 'startup', session_id: 'kept' })
  await classic.SessionStart({ source: 'compact' })
  expect(await lines($)).toEqual(['Before'])
  for (const source of ['clear', 'resume', 'fork']) {
    await note($, `Second ${source}`)
    expect(await lines($)).toHaveLength(2)
    await classic.SessionStart({ source })
    expect(await lines($)).toEqual([])
    await note($, `After ${source}`)
    expect(await lines($)).toEqual([`After ${source}`])
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
  expect((await lines($)).slice(-1)).toEqual(['A note'])
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
  for (const [spec, props] of [[PANE, { bodyColumns: 60 }]] as const) {
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

test('from 60 columns each section is a Box with a dim round border and its heading as the first row; no edge strings or side lines', async ($, on) => {
  const { world } = boot(on)
  await layoutWorld($, world)
  for (const cols of [60, 72, 100]) {
    const d = await mount($, PANE, 'terminal', { bodyColumns: cols })
    const t = await textsOf(d)
    const texts = await d.findAll({ type: 'Text' })
    const boxes = await d.findAll({ type: 'Box' })
    for (const key of ['waiting', 'feed']) {
      const section = boxes.find(b => b.key === key)!
      expect(section.props).toMatchObject({ flexDirection: 'column', borderStyle: 'round', borderDimColor: true, paddingX: 1 })
      // The heading row is the first thing inside it.
      const head = boxes.find(b => b.key === `${key}-top`)!
      expect(head.props?.flexDirection).toBe('row')
      expect(boxes.indexOf(head)).toBe(boxes.indexOf(section) + 1)
    }
    // The title is bold and its count dim, side by side: `WAITING ON YOU 2`, `FEED 3`.
    for (const [title, count] of [['WAITING ON YOU', '2'], ['FEED', '3']] as const) {
      const i = texts.findIndex(x => x.text === title)
      expect(texts[i]!.props?.bold).toBe(true)
      expect(texts[i + 1]).toMatchObject({ text: count, props: { dimColor: true } })
    }
    // The border is the Box's own: no edge or side-line strings are drawn as text.
    expect(t.some(x => /[╭╮╰╯│]/.test(x))).toBe(false)
    await d.unmount()
  }
})

test('the text of an item, its detail lines, a Feed entry and an agent wraps under itself on both surfaces, beside a top-aligned mark and buttons that do not shrink', async ($, on) => {
  const { world } = boot(on)
  await startSession($)
  await eng($).tool.call({ tool: OPEN, question: 'Rotate the token that the deploy job reads from the secrets store', recommendation: 'Do it after the release, not before', accept: 'Yes' })
  await bash(world, $, 'mentat check', WARN_RUN)
  await note($, 'A long note that goes on and on past the end of the row, wrapped under itself')
  world.agents = [{ id: 'a1', type: 'Explore', description: 'A long agent description that goes on and on past the end of the row', status: 'running' }]
  await eng($).agent.spawn(spawn('a1', 'A long agent description that goes on and on past the end of the row', 'Explore'))
  for (const [surface, spec] of [['terminal', TERM], ['desktop', DESK]] as const) {
    const d = await mount($, spec, surface)
    const texts = await d.findAll({ type: 'Text' })
    const boxes = await d.findAll({ type: 'Box' })
    for (const line of [
      'Rotate the token that the deploy job reads from the secrets store',
      'A long note that goes on and on past the end of the row, wrapped under itself',
      'A long agent description that goes on and on past the end of the row',
    ]) expect(texts.find(x => x.text === line)?.props?.wrap).toBe('wrap')
    for (const x of texts.filter(x => /^(Recommended: |WARN: )/.test(x.text ?? ''))) expect(x.props).toMatchObject({ wrap: 'wrap', dimColor: true })
    expect(texts.filter(x => x.props?.wrap === 'truncate-end').map(x => x.text)).toEqual([])
    // The item's first row is top-aligned: the mark at the left and the text, neither holding buttons.
    const first = boxes.find(b => b.key === 'item-d1')!
    const row = surface === 'terminal' ? first : boxes[boxes.indexOf(first) + 1]!
    expect(row.props).toMatchObject({ flexDirection: 'row', alignItems: 'flex-start' })
    // The row under it holds the detail at the left and the buttons at the right, which do not shrink.
    const parts = boxes.filter(b => b.key === 'mark-box' || b.key === 'controls' || (surface === 'desktop' && b.props?.flexShrink === 0 && b.props?.flexDirection === 'row'))
    expect(parts.length).toBeGreaterThan(0)
    for (const b of parts) expect(b.props?.flexShrink).toBe(0)
    // The text Box takes the rest; Feed rows are top-aligned too.
    for (const b of boxes.filter(b => /^(agent|log)-/.test(String(b.key)))) expect(b.props?.alignItems).toBe('flex-start')
    for (const b of boxes.filter(b => b.key === 'text' && surface === 'terminal')) expect(b.props).toMatchObject({ flexGrow: 1, flexShrink: 1 })
    if (surface === 'desktop') for (const b of boxes.filter(b => b.props?.flexGrow === 1 && b.props?.flexShrink === 1)) expect(b.props).toMatchObject({ minWidth: 0 })
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
    expect(rule('FEED').startsWith('── FEED 3 ─')).toBe(true)
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
  expect(t).toContain('Explore finished: Ended one')
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
  expect(await paneTexts($, 'desktop')).toContain('Check passed with 2 warnings')
})

test('a session start with a failing check (exit 1) pins the alert and turns the label red', async ($, on) => {
  const { world } = boot(on)
  world.git = GIT_YES
  world.check = failedExit('PROBLEM: gh is not logged in\nCheck failed: 1 problem(s)\n')
  await startSession($)
  await untilFooter($, 'terminal', '●', 'error')
  const cards = await alertsOf($)
  expect(cards.length).toBe(1)
  expect(await paneTexts($, 'desktop')).toContain('Check failed: 1 problem(s)')
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
  const classic = classicOf($)
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

// ---- an open question survives what happens around it ----------------------------------

test('a terminal pane row ends in its buttons without width arithmetic: a growing middle and one controls Box that does not shrink', async ($, on) => {
  boot(on)
  await open('question', 'Ship it?', { accept: 'Yes' })($)
  const d = await mount($, TERM, 'terminal')
  const boxes = await d.findAll({ type: 'Box' })
  const row = boxes.find(b => b.key === 'item-d1')!
  expect(row.props?.flexDirection).toBe('row')
  // The middle grows and shrinks; the controls keep their size.
  expect(boxes.filter(b => b.key === 'text' && b.props?.flexGrow === 1 && b.props?.flexShrink === 1)).not.toHaveLength(0)
  const controls = boxes.filter(b => b.key === 'controls')
  expect(controls).toHaveLength(1)
  expect(controls[0]!.props?.flexDirection).toBe('row')
  expect(controls[0]!.props?.flexShrink).toBe(0)
  const texts = await textsOf(d)
  // The mark and the text, then under it the time and the buttons.
  expect(texts.slice(texts.indexOf('?'), texts.indexOf('Dismiss') + 1)).toEqual(['?', 'Ship it?', '8:00 AM', 'Yes', 'Dismiss'])
  expect(await bandKeys(d)).toEqual(['accept-d1', 'dismiss-d1'])
  expect((await d.findAll({ type: 'Button' })).map(b => b.key)).toEqual(['accept-d1', 'dismiss-d1'])
  await d.unmount()
})

test('with the pane open, a question opened by the agent is still open after the user types a message, and close_decision settles it', async ($, on) => {
  const { world } = boot(on)
  await classicOf($).SessionStart({ source: 'startup', session_id: 'kept' })
  await startSession($)
  const pane = await mount($, TERM, 'terminal')
  const opened = await eng($).tool.call({ tool: OPEN, question: 'Ship it?', recommendation: 'Yes', accept: 'Yes' })
  expect(String(opened.result)).toContain('d1')
  // What can happen in the session meanwhile: the user's message (the agent's turn goes on), a model
  // request, a timer-driven read, a reload and a compaction. None of them touches the open question.
  const classic = classicOf($)
  await eng($).turn.complete({ answer: 'ok', durationMs: 1, isAborted: false, turnId: 'turn-main', reason: 'end_turn' })
  await step($, undefined)
  await startSession($)
  await classic.SessionStart({ source: 'startup', session_id: 'kept' })
  await classic.SessionStart({ source: 'compact' })
  expect(await waitTexts($, 'desktop')).toContain('Ship it?')
  expect(await textsOf(pane)).toContain('Ship it?')
  const closed = await eng($).tool.call({ tool: CLOSE, id: 'd1', outcome: 'No, do not ship' })
  expect(closed.deny).toBeUndefined()
  expect(String(closed.result)).toBe('Closed decision d1.')
  expect(await paneTexts($, 'desktop')).not.toContain('Ship it?')
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

test('an agent that ends writes one line: finished (with no time), failed, or stopped; an unknown end writes none', async ($, on) => {
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
    '✓ Builder finished: Build it',
    '✓ Explore finished: Look',
    '✓ Plan finished: Map it',
    '✓ general-purpose finished: Other thing',
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
  expect(await written($)).toEqual(['✓ Explore finished: Check the docs', '✓ Explore finished: Check the docs'])
})

test('open_decision and close_decision write no Feed line, whatever the kind', async ($, on) => {
  boot(on)
  await open(undefined, 'Ship it?')($)
  await open('question', 'Ship it?')($)
  await open('action', 'Merge #5 when ready')($)
  await open('alert', 'CI is red')($)
  expect(await written($)).toEqual([])
  // A refused call writes nothing either.
  expect((await open('warning', 'Not allowed')($)).deny).toBeDefined()
  expect((await open(undefined, '  ')($)).deny).toBeDefined()
  expect(await lines($)).toEqual([])
  for (const surface of SURFACES) expect((await paneTexts($, surface)).some(x => x.startsWith('Asked you'))).toBe(false)
  // Closing one writes none either, and still answers the agent as before.
  expect(String((await eng($).tool.call({ tool: CLOSE, id: 'd3', outcome: 'merged' })).result)).toBe('Closed decision d3.')
  expect(await written($)).toEqual([])
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

test('pressing the answer button sends the answer once and marks it queued, then sent; the Feed has no line for it', async ($, on) => {
  const { world } = boot(on)
  const turn = held()
  world.promptGate = turn.gate
  await eng($).tool.call({ tool: OPEN, question: 'Mock it?', accept: 'Yes' })
  const band = await mount($, TERM, 'terminal')
  // Three presses, the last two before the drawing could have changed.
  const presses = [band.press({ key: 'accept-d1' }), band.press({ key: 'accept-d1' }), band.press({ key: 'accept-d1' })]
  await new Promise(r => setTimeout(r, 20))
  expect(await textsOf(band)).toContain('Sent: Yes · queued')
  turn.release()
  await Promise.all(presses)
  expect(world.sent).toHaveLength(1)
  expect(await textsOf(band)).toContain('Sent: Yes')
  // Pressing again after the delivery does nothing more (the answered item has no answer button).
  expect(await bandKeys(band)).toEqual(['dismiss-d1'])
  expect(await feedLines(band)).toEqual([])
  await band.unmount()
})

test('a submit that is dropped or rejected leaves the question answerable; the press that follows takes it', async ($, on) => {
  const { world } = boot(on)
  await eng($).tool.call({ tool: OPEN, question: 'Mock it?', accept: 'Yes' })
  const band = await mount($, TERM, 'terminal')
  world.dropPrompts = true
  await band.press({ key: 'accept-d1' })
  world.dropPrompts = false
  world.rejectPrompts = true
  await band.press({ key: 'accept-d1' })
  expect(world.sent).toEqual([])
  expect(await bandKeys(band)).toContain('accept-d1')
  world.rejectPrompts = false
  await band.press({ key: 'accept-d1' })
  expect(world.sent).toHaveLength(1)
  expect(await feedLines(band)).toEqual([])
  await band.unmount()
})

test('dismissing a question while its answer waits, and Dismiss on a check item, write no Feed line; close_decision still names the dismissal', async ($, on) => {
  const { world } = boot(on)
  const turn = held()
  world.promptGate = turn.gate
  await eng($).tool.call({ tool: OPEN, question: 'Mock it?', accept: 'Yes' })
  const band = await mount($, TERM, 'terminal')
  const press = band.press({ key: 'accept-d1' })
  await new Promise(r => setTimeout(r, 20))
  await band.press({ key: 'dismiss-d1' })
  turn.release()
  await press
  expect(await feedLines(band)).toEqual([])
  await band.unmount()
  expect(String((await eng($).tool.call({ tool: CLOSE, id: 'd1' })).result)).toContain('already dismissed')
  await bash(world, $, 'mentat check', FAILED_RUN)
  const alert = await mount($, TERM, 'terminal')
  await alert.press({ key: 'dismiss-check' })
  await alert.unmount()
  expect(await lines($)).toEqual(['✕ mentat check failed: 2 problems'])
})

test('close_decision writes no Feed line for an open item, one already dismissed or cleared, or an unknown id, and answers the agent as before', async ($, on) => {
  boot(on)
  await eng($).tool.call({ tool: OPEN, question: 'Merge it?' })
  await eng($).tool.call({ tool: OPEN, question: 'Merge it?' })
  await eng($).tool.call({ tool: OPEN, question: 'Closed third?' })
  await eng($).tool.call({ tool: OPEN, question: 'Cleared one?' })
  expect(String((await eng($).tool.call({ tool: CLOSE, id: 'd1', outcome: '  Yes, merge ' })).result)).toBe('Closed decision d1.')
  expect(String((await eng($).tool.call({ tool: CLOSE, id: 'd2' })).result)).toBe('Closed decision d2.')
  expect(String((await eng($).tool.call({ tool: CLOSE, id: 'd3', outcome: '   ' })).result)).toBe('Closed decision d3.')
  expect(await lines($)).toEqual([])
  const band = await mount($, TERM, 'terminal')
  await eng($).tool.call({ tool: OPEN, question: 'To dismiss?' })
  await band.press({ key: 'dismiss-d5' })
  await band.unmount()
  await eng($).tool.call({ tool: OPEN, question: 'To clear?' })
  await classicOf($).SessionStart({ source: 'clear' })
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
  expect(await written($)).toEqual(['Opened PR #130'])
  await bash(world, $, 'gh pr create --title "feat: y"', 'something went wrong\n')
  await bash(world, $, 'gh pr ready 130', `${GH}/pull/130\n`)
  await bash(world, $, 'gh pr view 130', `${GH}/pull/130\n`)
  await bash(world, $, 'gh pr create --title "feat: z" --body y', `${GH}/pull/131\n`, { agentId: 'a1' })
  await new Promise(r => setTimeout(r, 30))
  expect(await written($)).toEqual(['Opened PR #130'])
  for (const surface of SURFACES) expect((await drawnRow($, surface, ' ', 'Opened PR #130')).colors.filter(c => c !== undefined)).toEqual([])
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
    const done = await drawnRow($, surface, '✓', 'Builder finished: Build it')
    expect(done.colors).toContain('success')
    expect(done.dim).toEqual([true])
    const failedRow = await drawnRow($, surface, '✕', 'Builder failed: Break it')
    expect(failedRow.colors).toContain('error')
    expect(failedRow.dim).toEqual([true])
    expect((await drawnRow($, surface, '✓', 'A plain note')).dim).toEqual([false])
    expect((await drawnRow($, surface, ' ', 'Another note')).dim).toEqual([false])
  }
  // A note's text carries no dimColor at all.
  const pane = await mount($, PANE, 'terminal', { bodyColumns: 60 })
  expect((await pane.findAll({ type: 'Text', text: 'A plain note' }))[0]!.props?.dimColor).toBeUndefined()
  await pane.unmount()
})

test('the Feed lists a note and an event line alike, newest first, with the event muted and the note not', async ($, on) => {
  const { world, clock } = boot(on)
  await startSession($)
  await pr(world, clock, $, 1)
  for (const surface of SURFACES) expect((await lines($, surface)).length).toBe(1)
  await note($, 'Keep this one', 'decision')
  await pr(world, clock, $, 2)
  for (const surface of SURFACES) {
    expect((await lines($, surface))[0]).toBe('Opened PR #2')
    expect(await lines($, surface)).toContain('Keep this one')
  }
  const d = await mount($, DESK, 'desktop')
  const texts = await d.findAll({ type: 'Text' })
  expect(texts.find(t => t.text === 'Keep this one')?.props?.dimColor).toBeUndefined()
  expect(texts.find(t => t.text === 'Opened PR #2')?.props?.dimColor).toBe(true)
  await d.unmount()
  // Mentat draws no band on either surface.
  for (const surface of SURFACES) expect(await bandTexts($, surface)).toEqual([])
})

test('an entry stored without a source is a note; a note written now has none, and an event says so', async ($, on) => {
  const { world, clock } = boot(on)
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
  await pr(world, clock, $, 3)
  expect(stored).toEqual([
    { at: T0, kind: 'plan', text: 'Plain' },
    { at: T0, kind: 'prOpened', text: 'Opened PR #3', source: 'event' },
  ])
})

test('an equal note straight after another is added once; an event between two equal notes, or two equal events, are all kept', async ($, on) => {
  const { world, clock } = boot(on)
  await note($, 'Same', 'waiting')
  await note($, 'Same', 'waiting')
  expect(await written($)).toEqual(['Same'])
  await pr(world, clock, $, 4)
  await note($, 'Same', 'waiting')
  expect(await written($)).toEqual(['Same', 'Opened PR #4', 'Same'])
  await pr(world, clock, $, 4)
  await pr(world, clock, $, 4)
  expect((await written($)).slice(-2)).toEqual(['Opened PR #4', 'Opened PR #4'])
})

test('an event line is kept in full and wrapped, cut only past 1000 characters, and events count toward the 200-line cap', async ($, on) => {
  const { world, clock } = boot(on)
  const branch = `feat/${'a-long-branch-name-'.repeat(5)}end`
  await bash(world, $, 'git push -u origin HEAD', '', {}, `To github.com:o/r.git\n * [new branch]      ${branch} -> ${branch}\n`)
  await clock.settle()
  for (const surface of SURFACES) {
    const [row] = (await logOf($, surface)).rows
    expect(row!.text).toBe(`Pushed ${branch}`)
    const pane = await mount($, PANE, surface, { bodyColumns: 60 })
    expect((await pane.findAll({ type: 'Text', text: row!.text }))[0]!.props?.wrap).toBe('wrap')
    await pane.unmount()
  }
  const long = `x${'y'.repeat(1100)}`
  await bash(world, $, 'git push', '', {}, ` * [new branch]      ${long} -> ${long}\n`)
  await clock.settle()
  const cut = (await logOf($)).rows[0]!.text
  expect([...cut]).toHaveLength(1000)
  expect(cut.startsWith('Pushed xyyy')).toBe(true)
  expect(cut.endsWith('…')).toBe(true)
  for (let i = 0; i < 204; i++) await pr(world, clock, $, 100 + i)
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
  expect(texts[head('FEED') + 1]).toMatchObject({ text: '3', props: { dimColor: true } })
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
  expect(texts.find(t => t.text === 'Ship the change now?')?.props?.wrap).toBe('wrap')
  expect(boxes.filter(b => b.props?.flexGrow === 1 && b.props?.flexShrink === 1).length).toBeGreaterThan(0)
  expect(boxes.filter(b => b.props?.flexShrink === 0 && b.props?.flexDirection === 'row').length).toBeGreaterThan(0)
  // The line under the text is muted and cut; the check's item has its WARN lines each on one muted line.
  for (const line of ['Recommended: Yes, it passed · 8:00 AM', '8:00 AM', 'WARN: gh is old', 'WARN: codex is old']) {
    const t = texts.find(x => x.text === line)
    expect(t?.props).toMatchObject({ dimColor: true, wrap: 'wrap' })
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
  // Dismiss removes the item (and its sent line) and leaves nothing in the Feed.
  await after.press({ key: 'dismiss-d2' })
  await after.unmount()
  const t = await paneTexts($, 'desktop')
  expect(t).not.toContain('Drop it?')
  expect(t).toContain('Mock it?')
  expect(t.some(x => x.includes('dismissed'))).toBe(false)
})

test('the desktop pane draws a GitHub link as #<number> and any other as its host', async ($, on) => {
  boot(on)
  await eng($).tool.call({ tool: OPEN, kind: 'action', question: 'Merge it', link: 'https://github.com/ericfurspan/mentat/issues/160' })
  await eng($).tool.call({ tool: OPEN, kind: 'alert', question: 'Read this', link: 'https://example.com/some/long/path' })
  const d = await mount($, DESK, 'desktop')
  expect((await d.findAll({ type: 'Link' })).map(l => [l.props?.href, l.props?.label])).toEqual([
    ['https://example.com/some/long/path', 'example.com'],
    ['https://github.com/ericfurspan/mentat/issues/160', '#160'],
  ])
  await d.unmount()
})

test('the desktop Feed shows the newest ten with Show all N and Show fewer as a native button; notes are plain and events muted', async ($, on) => {
  const { world, clock } = boot(on)
  await startSession($)
  for (let i = 1; i <= 12; i++) await note($, `Note ${i}`)
  await pr(world, clock, $, 9)
  const d = await mount($, DESK, 'desktop')
  const buttons = await d.findAll({ type: 'Button' })
  const toggle = buttons.find(b => b.key === 'log-toggle')!
  expect(toggle.props?.label).toBe('Show all 13')
  expect((await d.findAll({ type: 'Text' })).filter(t => /^Note \d+$/.test(t.text ?? '')).length).toBe(9)
  const texts = await d.findAll({ type: 'Text' })
  // The newest entry is the PR line (an event, muted); notes are in the full text color.
  expect(texts.find(t => t.text === 'Opened PR #9')?.props?.dimColor).toBe(true)
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

test('every desktop Box that can shrink has minWidth 0, so a narrow pane wraps the text and does not push past the card', async ($, on) => {
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
  // The text Boxes are the ones that grow and shrink; the text wraps under itself, so none hides its overflow.
  const text = boxes.filter(b => b.props?.flexShrink === 1)
  expect(text.length).toBeGreaterThanOrEqual(8)
  for (const b of text) expect(b.props).toMatchObject({ flexGrow: 1, minWidth: 0 })
  for (const b of text) expect(b.props?.overflow).toBeUndefined()
  // The cards and the pane's outer column are among those with minWidth 0.
  for (const key of ['card-waiting', 'card-feed', 'item-d1', 'item-d2', 'item-check']) expect(boxes.find(b => b.key === key)?.props?.minWidth).toBe(0)
  // Marks (the 3-cell column), time columns and the button groups never shrink; a group holds the link.
  const widths = boxes.filter(b => b.props?.width !== undefined)
  expect(widths.length).toBeGreaterThan(0)
  for (const b of widths) expect(b.props?.flexShrink).toBe(0)
  const groups = boxes.filter(b => b.props?.flexShrink === 0 && b.props?.flexDirection === 'row')
  expect(groups.length).toBeGreaterThanOrEqual(3)
})

// ---- no band: the footer label opens the pane ------------------------------------------------------------------

test('AbovePrompt draws no Svg, Box or Button of Mentat\'s in any state: quiet, a note, the budget, an item, a survey', async ($, on) => {
  const { world } = boot(on)
  const states: (() => Promise<unknown>)[] = [
    async () => undefined,
    async () => note($, 'A note', 'done'),
    async () => {
      world.usage = { context: 5, limits: [limit('five_hour', 95, RESET_5H())] }
    },
    async () => {
      await open('action', 'Rotate the token', { link: 'https://github.com/o/r/issues/160' })($)
      await open('alert', 'An alert')($)
    },
  ]
  for (const setup of states) {
    await setup()
    for (const surface of SURFACES) {
      for (const hasSurvey of [false, true]) {
        const d = await mount($, BAND, surface, { hasSurvey, bodyColumns: 60 })
        // Only the engine's own node (the mock draws one Box keyed engine-own) is there.
        expect((await d.findAll({ type: 'Box' })).map(b => b.key)).toEqual(['engine-own'])
        expect((await d.findAll({ type: 'Text' })).length + (await d.findAll({ type: 'Svg' })).length + (await d.findAll({ type: 'Button' })).length).toBe(0)
        await d.unmount()
      }
    }
  }
})

// ---- times that are not inaccurate ------------------------------------------------------------------------------

test('a finished or failed line has no duration', async ($, on) => {
  const { world, clock } = boot(on)
  await startSession($)
  world.agents = [
    { id: 'a1', type: 'builder', description: 'Build it', status: 'running' },
    { id: 'a2', type: 'builder', description: 'Break it', status: 'running' },
  ]
  for (const id of ['a1', 'a2']) await eng($).agent.spawn(spawn(id, id === 'a1' ? 'Build it' : 'Break it', 'builder'))
  await clock.advance(30 * 60_000)
  world.agents = [
    { id: 'a1', type: 'builder', description: 'Build it', status: 'completed' },
    { id: 'a2', type: 'builder', description: 'Break it', status: 'failed' },
  ]
  await clock.advance(1_000)
  await new Promise(r => setTimeout(r, 30))
  for (const surface of SURFACES) expect((await lines($, surface)).sort()).toEqual(['✓ Builder finished: Build it', '✕ Builder failed: Break it'])
})

test('an agent resumed after it finished counts its time from the resume, not from its first start', async ($, on) => {
  const { world, clock } = boot(on)
  await startSession($)
  world.agents = [{ id: 'a1', type: 'builder', description: 'Build it', status: 'running' }]
  await eng($).agent.spawn(spawn('a1', 'Build it', 'builder'))
  await clock.advance(10 * 60_000)
  expect(deskLine(await paneTexts($, 'desktop'), 'Build it')).toEqual({ state: 'running', elapsed: '10m 00s' })
  world.agents = [{ id: 'a1', type: 'builder', description: 'Build it', status: 'completed' }]
  await clock.advance(1_000)
  await new Promise(r => setTimeout(r, 30))
  expect(deskLine(await paneTexts($, 'desktop'), 'Build it')).toBeUndefined()
  // It sits idle for an hour, then a message resumes it; the engine's list says so at the agent's next turn.
  await clock.advance(3_600_000)
  world.agents = [{ id: 'a1', type: 'builder', description: 'Build it', status: 'running' }]
  await eng($).turn.complete(turnDone('a1'))
  await clock.advance(2 * 60_000)
  for (const surface of SURFACES) {
    const t = await paneTexts($, surface)
    expect(surface === 'terminal' ? stateOf(t, 'Build it') : deskLine(t, 'Build it')?.elapsed).toMatch(/^(running · )?2m 0\ds$/)
  }
})

test('an agent first seen live after a reload, with no known start, shows no time, and a resume of it starts one', async ($, on) => {
  const { world, clock } = boot(on)
  world.agents = [{ id: 'z9', type: 'Explore', description: 'Unseen one', status: 'running' }]
  await startSession($)
  await clock.advance(5_000)
  expect(stateOf(await paneTexts($, 'terminal'), 'Unseen one')).toBe('running')
  expect(deskLine(await paneTexts($, 'desktop'), 'Unseen one')).toEqual({ state: 'running', elapsed: undefined })
  // It ends and is resumed: from then on its time is known.
  world.agents = [{ id: 'z9', type: 'Explore', description: 'Unseen one', status: 'completed' }]
  await clock.advance(1_000)
  await new Promise(r => setTimeout(r, 30))
  world.agents = [{ id: 'z9', type: 'Explore', description: 'Unseen one', status: 'running' }]
  await eng($).turn.complete(turnDone('z9'))
  await clock.advance(3_000)
  expect(deskLine(await paneTexts($, 'desktop'), 'Unseen one')?.elapsed).toMatch(/^[34]s$/)
})

// ---- the conversation survives a restart of the process (#159) ------------------------------------------
// A new process starts with empty $.state and the same $.store. The tests stand for it with a fresh `boot`
// whose store is seeded with what an earlier process wrote (`world.store['conv:S1']`), and for a session id
// that changes (/clear, /branch, an in-app resume) with a SessionStart that names another `session_id`.

const sessionsOf = (world: World) => Object.fromEntries(Object.entries(world.store).filter(([k]) => k.startsWith('conv:')).map(([k, v]) => [k.slice(5), v])) as Record<string, { savedAt: number; items: { id: string; question: string }[]; nextId: number; log: { text: string }[]; sent: unknown[]; gone: { id: string }[]; checkResult: unknown }>
// What an earlier process left for session S1: two open items and the check's warning item, a delivered
// answer and one still waiting, a note and an event line, a dismissed item, the last check result.
const LEFT_BEHIND = {
  savedAt: T0 - 3600_000,
  items: [
    { id: 'd1', question: 'Ship it?', recommendation: 'Yes', accept: 'Yes', openedAt: T0 - 7200_000 },
    { id: 'd2', question: 'Merge it?', accept: 'Go', openedAt: T0 - 7100_000 },
    { id: 'd3', kind: 'action', question: 'Rotate the token', link: 'https://github.com/o/r/issues/7', openedAt: T0 - 7000_000 },
    { id: 'check', kind: 'warning', question: 'Check passed with 2 warnings', openedAt: T0 - 6900_000 },
  ],
  nextId: 5,
  sent: [{ id: 'd1', text: 'Yes', isDelivered: true }, { id: 'd2', text: 'Go' }],
  log: [
    { at: T0 - 7200_000, kind: 'plan', text: 'Plan the release' },
    { at: T0 - 7100_000, kind: 'asked', text: 'Asked you: Merge it?', source: 'event', mark: 'question' },
    { at: T0 - 7000_000, kind: 'answered', text: 'You answered "Yes": Ship it?', source: 'event' },
    { at: T0 - 6900_000, kind: 'dismissed', text: 'You dismissed: Old?', source: 'event' },
    { at: T0 - 6800_000, kind: 'prOpened', text: 'Opened PR #9', source: 'event' },
  ],
  checkResult: { state: 'warn', warnings: ['gh is old', 'codex is old'] },
  gone: [{ id: 'd4', why: 'dismissed', at: T0 - 6000_000 }],
}

test('a restart of the same conversation (empty state, same id, source resume) brings back the items, the numbering, the Feed, the check and what was answered', async ($, on) => {
  const { world } = boot(on, { store: { 'conv:S1': LEFT_BEHIND } })
  world.git = ok('true')
  world.check = ok(CLEAN_RUN)
  // (A mod load also runs a check of its own, as it always did; this test is of the session start alone.)
  await classicOf($).SessionStart({ source: 'resume', session_id: 'S1' })
  for (const surface of SURFACES) {
    const t = await waitTexts($, surface)
    for (const q of ['Ship it?', 'Merge it?', 'Rotate the token', 'Check passed with 2 warnings']) expect(t).toContain(q)
  }
  // The Feed; the asked, answered and dismissed lines an earlier version stored are dropped.
  expect(await lines($)).toEqual(['Opened PR #9', 'Plan the release'])
  // The check result is kept, so the label is the warning one and no new check is run.
  expect(await footerTextOf($)).toBe('● Mentat · 4 waiting')
  expect((await footerOf($, 'terminal'))[0]).toEqual({ text: '●', color: 'warning', dim: false })
  expect(world.calls.filter(a => isCall(a, 'mentat', 'check'))).toEqual([])
  // The delivered answer is still marked sent; the one that had not entered the session is forgotten.
  const d = await mount($, TERM, 'terminal')
  expect(await textsOf(d)).toContain('Sent: Yes')
  expect(await bandKeys(d)).toContain('accept-d2')
  expect(await bandKeys(d)).not.toContain('accept-d1')
  await d.unmount()
  // The numbering continues, and the record of items that left is back.
  expect(String((await eng($).tool.call({ tool: OPEN, question: 'Next?' })).result)).toBe('Opened decision d5.')
  expect(String((await eng($).tool.call({ tool: CLOSE, id: 'd4' })).result)).toContain('already dismissed')
  expect(String((await eng($).tool.call({ tool: CLOSE, id: 'd1' })).result)).toBe('Closed decision d1.')
  // Nothing of it was recorded as cleared.
  expect(String((await eng($).tool.call({ tool: CLOSE, id: 'd2' })).result)).toBe('Closed decision d2.')
})

const NOTHING_STORED: [string, Record<string, unknown>][] = [
  ['no store', {}],
  ['another id only', { 'conv:S2': LEFT_BEHIND }],
  ['an entry that is not an object', { 'conv:S1': 'junk' }],
  ['an entry of the wrong shapes', { 'conv:S1': { items: 'junk', log: 4, nextId: 'x', checkResult: { state: 'bad' } } }],
]
for (const [what, store] of NOTHING_STORED) {
  test(`a restart with nothing usable stored for the id (${what}) starts empty and runs the check`, async ($, on) => {
    const { world } = boot(on, { store })
    world.git = ok('true')
    world.check = ok(CLEAN_RUN)
    await classicOf($).SessionStart({ source: 'resume', session_id: 'S1' })
    await until(() => world.calls.some(a => isCall(a, 'mentat', 'check')), 'the check')
    await until(() => world.invalidations > 0, 'the check')
    // Only the new check's own line: nothing waits and nothing else is in the Feed.
    await untilFooter($, 'terminal', '● Mentat', 'success')
    expect(await lines($)).toEqual(['✓ mentat check passed'])
    for (const surface of SURFACES) expect((await paneTexts($, surface)).includes('WAITING ON YOU')).toBe(false)
    expect(String((await eng($).tool.call({ tool: OPEN, question: 'First?' })).result)).toBe('Opened decision d1.')
  })
}

test('a resume of this conversation inside the same process keeps everything and records nothing as gone', async ($, on) => {
  const { world } = boot(on)
  await classicOf($).SessionStart({ source: 'startup', session_id: 'S1' })
  await eng($).tool.call({ tool: OPEN, question: 'Stay?', accept: 'Yes' })
  await note($, 'Before')
  await classicOf($).SessionStart({ source: 'resume', session_id: 'S1' })
  await classicOf($).SessionStart({ source: 'compact' })
  expect(await waitTexts($, 'terminal')).toContain('Stay?')
  expect(await lines($)).toEqual(['Before'])
  expect(String((await eng($).tool.call({ tool: CLOSE, id: 'd1' })).result)).toBe('Closed decision d1.')
  expect((await eng($).tool.call({ tool: CLOSE, id: 'd1' })).deny).toContain('no record')
  expect(sessionsOf(world).S1!.items).toEqual([])
})

test('a new id with nothing stored (as after /clear or /branch) starts empty and records the old items as cleared; the old conversation stays stored', async ($, on) => {
  const { world } = boot(on)
  await classicOf($).SessionStart({ source: 'startup', session_id: 'S1' })
  await eng($).tool.call({ tool: OPEN, question: 'Old?' })
  await note($, 'Old note')
  await classicOf($).SessionStart({ source: 'clear', session_id: 'S2' })
  for (const surface of SURFACES) expect(await paneTexts($, surface)).toEqual(['Nothing waiting on you.'])
  expect(await lines($)).toEqual([])
  expect(String((await eng($).tool.call({ tool: CLOSE, id: 'd1' })).result)).toBe('Decision d1 was already cleared when a new conversation started (/clear).')
  expect(String((await eng($).tool.call({ tool: OPEN, question: 'New?' })).result)).toBe('Opened decision d2.')
  // S1 is what it was; S2 holds the new conversation.
  expect(sessionsOf(world).S1!.items.map(d => d.question)).toEqual(['Old?'])
  expect(sessionsOf(world).S2!.items.map(d => d.question)).toEqual(['New?'])
})

test('a resume to a different id that has stored state loads that state, and going back loads the first again', async ($, on) => {
  const { world } = boot(on)
  await classicOf($).SessionStart({ source: 'startup', session_id: 'S1' })
  await eng($).tool.call({ tool: OPEN, question: 'Alpha?' })
  await note($, 'Alpha note')
  await classicOf($).SessionStart({ source: 'clear', session_id: 'S2' })
  await eng($).tool.call({ tool: OPEN, question: 'Beta?' })
  await classicOf($).SessionStart({ source: 'resume', session_id: 'S1' })
  expect(await waitTexts($, 'terminal')).toContain('Alpha?')
  expect(await waitTexts($, 'terminal')).not.toContain('Beta?')
  expect(await lines($)).toEqual(['Alpha note'])
  // Beta's item went as cleared (by /resume); numbering does not reuse an id that left.
  expect(String((await eng($).tool.call({ tool: CLOSE, id: 'd2' })).result)).toBe('Decision d2 was already cleared when a new conversation started (/resume).')
  expect(String((await eng($).tool.call({ tool: OPEN, question: 'Gamma?' })).result)).toBe('Opened decision d3.')
  await classicOf($).SessionStart({ source: 'resume', session_id: 'S2' })
  expect(await waitTexts($, 'terminal')).toContain('Beta?')
  expect(await waitTexts($, 'terminal')).not.toContain('Gamma?')
  expect(Object.keys(sessionsOf(world)).sort()).toEqual(['S1', 'S2'])
})

test('the store keeps one key per conversation, `conv:<session id>`, and a save writes only its own', async ($, on) => {
  const { world } = boot(on, { store: { 'conv:OTHER': { ...LEFT_BEHIND, savedAt: 5 } } })
  await classicOf($).SessionStart({ source: 'startup', session_id: 'S1' })
  expect(Object.keys(world.store)).toEqual(['conv:OTHER'])
  await eng($).tool.call({ tool: OPEN, question: 'Mine?' })
  // Another session, running at once, saves its own key meanwhile; this one's later saves leave it alone.
  world.store['conv:LIVE'] = { ...LEFT_BEHIND, savedAt: T0 + 1 }
  await note($, 'Still mine')
  await eng($).tool.call({ tool: CLOSE, id: 'd1' })
  expect(Object.keys(world.store).sort()).toEqual(['conv:LIVE', 'conv:OTHER', 'conv:S1'])
  expect(world.store['conv:LIVE']).toEqual({ ...LEFT_BEHIND, savedAt: T0 + 1 })
  expect((world.store['conv:S1'] as { log: unknown[] }).log.length).toBe(1)
  // A conversation that ends up empty has no key.
  await classicOf($).SessionStart({ source: 'clear', session_id: 'S2' })
  await eng($).tool.call({ tool: CLOSE, id: 'd1' })
  expect(Object.keys(world.store)).not.toContain('conv:S2')
})

test('the store keeps what a conversation holds under its session id, and at most the 20 most recently saved (pruned at a session start), dropping the oldest', async ($, on) => {
  const { world, clock } = boot(on)
  for (let i = 1; i <= 22; i++) {
    await clock.advance(1000)
    await classicOf($).SessionStart({ source: i === 1 ? 'startup' : 'clear', session_id: `S${i}` })
    await eng($).tool.call({ tool: OPEN, question: `Question ${i}?` })
  }
  const kept = sessionsOf(world)
  expect(Object.keys(kept).sort()).toEqual(Array.from({ length: 20 }, (_, i) => `S${i + 3}`).sort())
  const last = kept.S22!
  expect(Object.keys(last).sort()).toEqual(['checkResult', 'gone', 'items', 'log', 'nextId', 'savedAt', 'sent'])
  expect(last.items.map(d => d.question)).toEqual(['Question 22?'])
  expect(last.nextId).toBe(23)
  expect(last.savedAt).toBe(T0 + 22_000)
  expect(last.log).toEqual([])
  // The agent rows and the view toggles are not kept.
  expect(JSON.stringify(world.store)).not.toContain('logAll')
  // An old conversation that is changed again is the newest.
  await clock.advance(1000)
  await classicOf($).SessionStart({ source: 'resume', session_id: 'S3' })
  await note($, 'Touched')
  await clock.advance(1000)
  await classicOf($).SessionStart({ source: 'clear', session_id: 'S23' })
  await eng($).tool.call({ tool: OPEN, question: 'Question 23?' })
  expect(Object.keys(sessionsOf(world))).toContain('S3')
  expect(Object.keys(sessionsOf(world))).not.toContain('S4')
  expect(Object.keys(sessionsOf(world)).length).toBe(20)
})

test('a store write that throws leaves the pane working, and a later write goes through', async ($, on) => {
  const { world } = boot(on)
  await classicOf($).SessionStart({ source: 'startup', session_id: 'S1' })
  world.storeFails = true
  const opened = await eng($).tool.call({ tool: OPEN, question: 'Still works?', accept: 'Yes' })
  expect(String(opened.result)).toBe('Opened decision d1.')
  await note($, 'A note')
  const d = await mount($, TERM, 'terminal')
  expect(await textsOf(d)).toContain('Still works?')
  await d.press({ key: 'accept-d1' })
  await d.unmount()
  expect(world.sent.length).toBe(1)
  await classicOf($).SessionStart({ source: 'clear', session_id: 'S2' })
  expect(await paneTexts($, 'terminal')).toEqual(['Nothing waiting on you.'])
  expect(world.storeWrites).toBe(0)
  world.storeFails = false
  await eng($).tool.call({ tool: OPEN, question: 'Saved?' })
  expect(sessionsOf(world).S2!.items.map(d => d.question)).toEqual(['Saved?'])
})

test('a mod load before the session start does not wipe what is stored for the conversation', async ($, on) => {
  const { world } = boot(on, { store: { 'conv:S1': LEFT_BEHIND } })
  await startSession($)
  await eng($).tool.call({ tool: NOTE, text: 'Too early' })
  expect(sessionsOf(world).S1!.items.length).toBe(4)
  await classicOf($).SessionStart({ source: 'resume', session_id: 'S1' })
  expect(await waitTexts($, 'terminal')).toContain('Ship it?')
})

test('a startup session start runs no check of its own (the mod load does), and a resume that restores a kept check result runs none', async ($, on) => {
  const { world } = boot(on)
  world.git = ok('true')
  world.check = ok(CLEAN_RUN)
  await classicOf($).SessionStart({ source: 'startup', session_id: 'S1' })
  await new Promise(r => setTimeout(r, 30))
  expect(world.calls.filter(a => isCall(a, 'mentat', 'check'))).toEqual([])
  await startSession($)
  await until(() => world.calls.some(a => isCall(a, 'mentat', 'check')), 'the mod load check')
  await untilFooter($, 'terminal', '● Mentat', 'success')
  expect(world.calls.filter(a => isCall(a, 'mentat', 'check')).length).toBe(1)
  // The result is kept with the conversation: back in S1 after /clear, it is not run again.
  await classicOf($).SessionStart({ source: 'clear', session_id: 'S2' })
  await until(() => world.calls.filter(a => isCall(a, 'mentat', 'check')).length === 2, 'the check after /clear')
  await untilFooter($, 'terminal', '● Mentat', 'success')
  await classicOf($).SessionStart({ source: 'resume', session_id: 'S1' })
  await new Promise(r => setTimeout(r, 30))
  expect(world.calls.filter(a => isCall(a, 'mentat', 'check')).length).toBe(2)
  expect((await footerOf($, 'terminal'))[0]).toEqual({ text: '● Mentat', color: 'success', dim: false })
})

// ---- refinements: the detail line, the layout of an item, the Feed's marks ----------------------------------

test('a recommendation equal to the answer button label (trimmed, any case) is not repeated: the detail is only the time', async ($, on) => {
  boot(on)
  await eng($).tool.call({ tool: OPEN, question: 'Same?', recommendation: ' yes ', accept: 'Yes' })
  await eng($).tool.call({ tool: OPEN, question: 'Longer?', recommendation: 'Yes, after the release', accept: 'Yes' })
  await eng($).tool.call({ tool: OPEN, question: 'No button?', recommendation: 'Yes' })
  for (const surface of SURFACES) {
    // Newest item first: No button? and Longer? keep their Recommended line; Same? has the time alone.
    const t = await paneTexts($, surface)
    expect(t.filter(x => x.startsWith('Recommended:'))).toEqual(['Recommended: Yes · 8:00 AM', 'Recommended: Yes, after the release · 8:00 AM'])
  }
})

test('an item\'s buttons are in a row under its text, the detail at the left of them; under 40 terminal columns that row holds the buttons alone', async ($, on) => {
  boot(on)
  await eng($).tool.call({ tool: OPEN, question: 'Ship it?', recommendation: 'After the release', accept: 'Yes' })
  const keysOf = async (d: Drawing, from: string, to: string) => {
    const boxes = await d.findAll({ type: 'Box' })
    const i = boxes.findIndex(b => b.key === from)
    const end = boxes.findIndex(b => b.key === to, i + 1)
    return boxes.slice(i, end === -1 ? undefined : end).map(b => b.key)
  }
  // Terminal at a width that draws the detail: the first row is the mark and the text alone.
  const wide = await mount($, PANE, 'terminal', { bodyColumns: 60 })
  expect(await keysOf(wide, 'item-d1', 'actions-d1')).toEqual(['item-d1', 'mark-box', 'text'])
  expect((await keysOf(wide, 'actions-d1', 'zzz')).slice(0, 3)).toEqual(['actions-d1', 'detail', 'controls'])
  const wideBoxes = await wide.findAll({ type: 'Box' })
  expect(wideBoxes.find(b => b.key === 'detail')!.props).toMatchObject({ flexGrow: 1, flexShrink: 1, paddingLeft: 2 })
  expect(wideBoxes.find(b => b.key === 'controls')!.props?.flexShrink).toBe(0)
  const wideTexts = await textsOf(wide)
  expect(wideTexts.slice(wideTexts.indexOf('?'), wideTexts.indexOf('Dismiss') + 1)).toEqual(['?', 'Ship it?', 'Recommended: After the release · 8:00 AM', 'Yes', 'Dismiss'])
  await wide.unmount()
  // Under 40 columns the time and the recommendation are left out; the buttons stay, at the right.
  const narrow = await mount($, PANE, 'terminal', { bodyColumns: 30 })
  expect((await keysOf(narrow, 'actions-d1', 'zzz')).slice(0, 2)).toEqual(['actions-d1', 'controls'])
  const narrowBoxes = await narrow.findAll({ type: 'Box' })
  expect(narrowBoxes.some(b => b.key === 'detail')).toBe(false)
  expect(narrowBoxes.find(b => b.key === 'actions-d1')!.props).toMatchObject({ justifyContent: 'flex-end' })
  const narrowTexts = await textsOf(narrow)
  expect(narrowTexts.slice(narrowTexts.indexOf('?'), narrowTexts.indexOf('Dismiss') + 1)).toEqual(['?', 'Ship it?', 'Yes', 'Dismiss'])
  await narrow.unmount()
  // The desktop: the text row, then a row indented to the text with the detail at the left and the buttons.
  const desk = await mount($, DESK, 'desktop')
  const deskBoxes = await desk.findAll({ type: 'Box' })
  const actions = deskBoxes.find(b => b.key === 'actions')!
  expect(actions.props).toMatchObject({ flexDirection: 'row', paddingLeft: 4 })
  // (The mark is an Svg, drawn apart from the Texts.)
  const deskTexts = (await desk.findAll({ type: 'Text' })).map(t => t.text)
  const at = deskTexts.indexOf('Ship it?')
  expect(deskTexts.slice(at, at + 2)).toEqual(['Ship it?', 'Recommended: After the release · 8:00 AM'])
  expect(await bandKeys(desk)).toEqual(['accept-d1', 'dismiss-d1'])
  await desk.unmount()
})

// A log kept from an earlier session: the way to put every kind of entry in the Feed at once.
const withLog = async ($: never, on: never, log: { at: number; kind: string; text: string; source?: string; mark?: string }[]) => {
  const { world } = boot(on, { store: { 'conv:S1': { savedAt: T0, items: [], nextId: 1, sent: [], log, checkResult: null, gone: [] } } })
  await classicOf($).SessionStart({ source: 'resume', session_id: 'S1' })

  return world
}
const ev = (kind: string, text: string, mark?: string, at = T0) => ({ at, kind, text, source: 'event', ...(mark === undefined ? {} : { mark }) })

test('the Feed marks only a success (✓ green), a failure (✕ red) and what wants attention (! amber); every other entry has a blank mark', async ($, on) => {
  await withLog($, on, [
    { at: T0, kind: 'done', text: 'N done' },
    { at: T0, kind: 'surprise', text: 'N surprise' },
    { at: T0, kind: 'decision', text: 'N decision' },
    { at: T0, kind: 'plan', text: 'N plan' },
    { at: T0, kind: 'waiting', text: 'N waiting' },
    ev('agentDone', 'E agent finished'),
    ev('agentFailed', 'E agent failed'),
    ev('check', 'E check passed', 'pass'),
    ev('check', 'E check warned', 'warn'),
    ev('check', 'E check failed', 'fail'),
    ev('prOpened', 'E pr opened'),
    ev('pushed', 'E pushed'),
  ])
  const expected: Record<string, string> = {
    'N done': '✓', 'N surprise': '!', 'N decision': '', 'N plan': '', 'N waiting': '',
    'E agent finished': '✓', 'E agent failed': '✕',
    'E check passed': '✓', 'E check warned': '!', 'E check failed': '✕',
    'E pr opened': '', 'E pushed': '',
  }
  // Show all of them.
  const toggler = await mount($, TERM, 'terminal')
  await toggler.press({ key: 'log-toggle' })
  await toggler.unmount()
  const colorOf: Record<string, string> = { '✓': 'success', '✕': 'error', '!': 'warning' }
  for (const surface of SURFACES) {
    const rows = (await logOf($, surface)).rows
    expect(Object.fromEntries(rows.map(r => [r.text, r.icon]))).toEqual(expected)
    for (const [icon, color] of Object.entries(colorOf)) {
      const drawn = await drawnRow($, surface, icon, 'N done')
      expect(drawn.colors.length).toBeGreaterThan(0)
      // Every mark of that icon has its color.
      expect(drawn.colors.every(c => c === color)).toBe(true)
    }
  }
})

test('the Feed shows a time only on the first row of a run of the same displayed time; the rows after it leave it blank, and a time that comes back is shown again', async ($, on) => {
  await withLog($, on, [
    // Oldest first; the Feed shows the newest first: 9:00, 8:01, 8:01, 8:00, 8:01, 8:00 (by minutes).
    { at: T0, kind: 'plan', text: 'one' },
    { at: T0 + 70_000, kind: 'plan', text: 'two' },
    { at: T0 + 5_000, kind: 'plan', text: 'three' },
    { at: T0 + 75_000, kind: 'plan', text: 'four' },
    { at: T0 + 80_000, kind: 'plan', text: 'five' },
    { at: T0 + 3_600_000, kind: 'plan', text: 'six' },
  ])
  for (const surface of SURFACES) {
    expect((await logOf($, surface)).rows.map(r => [r.time, r.text])).toEqual([
      ['9:00 AM', 'six'], ['8:01 AM', 'five'], ['', 'four'], ['8:00 AM', 'three'], ['8:01 AM', 'two'], ['8:00 AM', 'one'],
    ])
  }
})

test('a pinned agent row keeps its own state and time and takes no part in the Feed time runs; Show all keeps the first row of a run timed', async ($, on) => {
  const world = await withLog($, on, Array.from({ length: 12 }, (_, i) => ({ at: T0 + i * 1000, kind: 'plan', text: `Note ${i}` })))
  world.agents = [{ id: 'a1', type: 'Explore', description: 'Look around', status: 'running' }]
  await eng($).agent.spawn(spawn('a1', 'Look around', 'Explore'))
  for (const surface of SURFACES) {
    const t = await paneTexts($, surface)
    expect(t).toContain('Look around')
    const rows = (await logOf($, surface)).rows
    expect(rows).toHaveLength(10)
    expect(rows.map(r => r.time)).toEqual(['8:00 AM', ...Array(9).fill('')])
  }
  const toggler = await mount($, TERM, 'terminal')
  await toggler.press({ key: 'log-toggle' })
  await toggler.unmount()
  expect((await logOf($)).rows.map(r => r.time)).toEqual(['8:00 AM', ...Array(11).fill('')])
})

test('on the terminal there is one blank row between the items of Waiting on you, none after the last; the gap stays under 40 columns', async ($, on) => {
  boot(on)
  await eng($).tool.call({ tool: OPEN, question: 'One?', accept: 'Yes' })
  await eng($).tool.call({ tool: OPEN, kind: 'action', question: 'Two' })
  await eng($).tool.call({ tool: OPEN, kind: 'alert', question: 'Three' })
  await eng($).tool.call({ tool: OPEN, question: 'Four?' })
  for (const cols of [80, 50, 30]) {
    const d = await mount($, PANE, 'terminal', { bodyColumns: cols })
    const blocks = (await d.findAll({ type: 'Box' })).filter(b => String(b.key).startsWith('block-'))
    // Most urgent first: the alert, then the questions (newest first), then the action.
    expect(blocks.map(b => [b.key, b.props?.marginTop])).toEqual([['block-d3', 0], ['block-d4', 1], ['block-d1', 1], ['block-d2', 1]])
    expect(blocks.every(b => b.props?.flexDirection === 'column')).toBe(true)
    await d.unmount()
  }
})

test('on the desktop an item\'s button row has room above it and is centered; the items in the card are spaced two rows apart', async ($, on) => {
  boot(on)
  await eng($).tool.call({ tool: OPEN, question: 'A long question that wraps onto a second line when the divider is dragged narrow?', accept: 'Yes' })
  await eng($).tool.call({ tool: OPEN, kind: 'action', question: 'Rotate the token', link: 'https://github.com/o/r/issues/7' })
  const d = await mount($, DESK, 'desktop')
  const boxes = await d.findAll({ type: 'Box' })
  const actions = boxes.filter(b => b.key === 'actions')
  expect(actions).toHaveLength(2)
  for (const row of actions) expect(row.props).toMatchObject({ flexDirection: 'row', alignItems: 'center', marginTop: 1, paddingLeft: 4 })
  // The card's items are one column, two rows apart; the card keeps its even side padding.
  expect(boxes.find(b => b.key === 'items')!.props).toMatchObject({ flexDirection: 'column', gap: 2 })
  expect(boxes.find(b => b.key === 'card-waiting')!.props).toMatchObject({ paddingX: 1, gap: 1 })
  await d.unmount()
  // The terminal is as it was: no top margin on its button row.
  const term = await mount($, TERM, 'terminal')
  expect((await term.findAll({ type: 'Box' })).filter(b => String(b.key).startsWith('actions-')).every(b => b.props?.marginTop === undefined)).toBe(true)
  await term.unmount()
})

// ---- the Feed records the work: pushes, and none of the pane's own bookkeeping ----------------------------

const pushLines = async (world: World, clock: { settle: () => Promise<void> }, $: never, command: string, stderr: string, extra: object = {}, stdout = '') => {
  await bash(world, $, command, stdout, extra, stderr)
  await clock.settle()

  return lines($)
}

test('a push writes one dim line naming the branch, read from git\'s own output; the count is never written because git prints none', async ($, on) => {
  const { world, clock } = boot(on)
  await startSession($)
  // An existing branch: the range line.
  expect(await pushLines(world, clock, $, 'git push', 'To github.com:o/r.git\n   abc1234..def5678  fix/x -> fix/x\n')).toEqual(['Pushed fix/x'])
  // A new branch, with a push that also sets the upstream.
  expect(await pushLines(world, clock, $, 'git push -u origin topic', 'remote: Create a pull request for \'topic\'\nTo github.com:o/r.git\n * [new branch]      topic -> topic\nbranch \'topic\' set up to track \'origin/topic\'.\n')).toEqual(['Pushed topic', 'Pushed fix/x'])
  // A forced update, a local name that differs from the remote's, a command with -C and a chain.
  expect((await pushLines(world, clock, $, 'cd /r && git -C /r push --force-with-lease origin local:remote-name', ' + abc1234...def5678 local -> remote-name (forced update)\n'))[0]).toBe('Pushed remote-name')
  // Two branches in one push are one line.
  expect((await pushLines(world, clock, $, 'git push origin a b', '   1111111..2222222  a -> a\n * [new branch]      b -> b\n'))[0]).toBe('Pushed a, b')
  // The line is dim and has no mark, on both surfaces.
  for (const surface of SURFACES) {
    const drawn = await drawnRow($, surface, ' ', 'Pushed a, b')
    expect(drawn.dim).toEqual([true])
  }
  // Git's output goes to stderr; a push that printed on stdout reads the same.
  expect((await pushLines(world, clock, $, 'git push', '', {}, '   3333333..4444444  c -> c\n'))[0]).toBe('Pushed c')
})

test('a push that did nothing, failed, was a dry run, came from a subagent or was not a push writes no line', async ($, on) => {
  const { world, clock } = boot(on)
  await startSession($)
  const cases: [string, string, object?][] = [
    ['git push', 'Everything up-to-date\n'],
    ['git push', ''],
    ['git push', 'To github.com:o/r.git\n ! [rejected]        main -> main (non-fast-forward)\nerror: failed to push some refs to \'github.com:o/r.git\'\n'],
    ['git push', 'To github.com:o/r.git\n   abc1234..def5678  main -> main\n ! [remote rejected] other -> other (protected branch hook declined)\nerror: failed to push some refs\n'],
    ['git push', 'fatal: The current branch topic has no upstream branch.\n'],
    ['git push --dry-run', 'To github.com:o/r.git\n   abc1234..def5678  main -> main\n'],
    ['git push -n', 'To github.com:o/r.git\n   abc1234..def5678  main -> main\n'],
    ['git push origin v1', 'To github.com:o/r.git\n * [new tag]         v1 -> v1\n'],
    ['git push origin :gone', 'To github.com:o/r.git\n - [deleted]         gone\n'],
    ['git push', 'To github.com:o/r.git\n   abc1234..def5678  main -> main\n', { agentId: 'a1' }],
    ['echo "   abc1234..def5678  main -> main"', '   abc1234..def5678  main -> main\n'],
    ['git pushall', '   abc1234..def5678  main -> main\n'],
    ['git log --oneline', 'abc1234..def5678  main -> main\n'],
  ]
  for (const [command, stderr, extra] of cases) expect(await pushLines(world, clock, $, command, stderr, extra ?? {})).toEqual([])
})

test('entries of the kinds asked, answered and dismissed are dropped when a log is restored, and the Feed never shows them', async ($, on) => {
  const world = await withLog($, on, [
    { at: T0, kind: 'plan', text: 'Keep me' },
    ev('asked', 'Asked you: Q?', 'question'),
    ev('answered', 'You answered "Yes": Q?'),
    ev('answered', 'Closed: Q?'),
    ev('dismissed', 'You dismissed: Q?'),
    ev('prOpened', 'Opened PR #5'),
  ])
  for (const surface of SURFACES) expect((await logOf($, surface)).rows.map(r => r.text)).toEqual(['Opened PR #5', 'Keep me'])
  // They are gone from what is kept, too.
  await note($, 'Next')
  expect(sessionsOf(world).S1!.log.map(l => l.text)).toEqual(['Keep me', 'Opened PR #5', 'Next'])
})
