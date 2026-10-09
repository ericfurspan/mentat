import { expect, mock, test } from 'claude-code/testing'

const OPEN = 'mcp__mentat__open_decision'
const CLOSE = 'mcp__mentat__close_decision'
const BAND = { plugin: 'mentat', component: 'AbovePrompt', props: { hasSurvey: false } }
const PANE = { plugin: 'mentat', component: 'Pane', requestId: 'decisions', props: {} }

const texts = async (ui: { findAll: (q: { type: string }) => Promise<{ text?: string }[]> }) =>
  (await ui.findAll({ type: 'Text' })).map(t => t.text ?? '')

test('an opened decision shows in the band and pane, and closing it settles it', async ($, on) => {
  mock.clock(on)
  on('ui.render', ($, e) => {
    const { Box } = $.ui.resolve(e)
    return <Box key="engine-own" />
  })

  const opened = await $.tool.call({ tool: OPEN, question: 'Open the issue?', recommendation: 'yes' } as never)
  expect(String((opened as { result?: unknown }).result)).toContain('d1')

  for (const surface of ['terminal', 'desktop'] as const) {
    const band = await $.ui.mount({ ...BAND, surface } as never)
    expect(await texts(band as never)).toContain('1 decision waits on you')
    await band.unmount()

    const pane = await $.ui.mount({ ...PANE, surface } as never)
    expect((await texts(pane as never)).some(t => t.includes('Open the issue?'))).toBe(true)
    await pane.unmount()
  }

  await $.tool.call({ tool: CLOSE, id: 'd1', outcome: 'opened' } as never)

  const band = await $.ui.mount({ ...BAND, surface: 'terminal' } as never)
  expect((await texts(band as never)).some(t => t.includes('waits on you'))).toBe(false)
  await band.unmount()

  const pane = await $.ui.mount({ ...PANE, surface: 'terminal' } as never)
  expect((await texts(pane as never)).some(t => t.includes('Open the issue?') && t.includes('opened'))).toBe(true)
  await pane.unmount()
})

test('closing an unknown id is refused', async $ => {
  const ran = await $.tool.call({ tool: CLOSE, id: 'd99' } as never)
  expect((ran as { deny?: string }).deny).toContain('No open decision')
})

test('answering in the pane sends the answer to chat as a prompt', async ($, on) => {
  mock.clock(on)
  const sent: string[] = []
  on('prompt.submit', (_$, e) => {
    const text = (e as { text: string }).text
    sent.push(text)
    return { text } as never
  })
  await $.tool.call({ tool: OPEN, question: 'Keep it?' } as never)

  for (const surface of ['terminal', 'desktop'] as const) {
    const pane = await $.ui.mount({ ...PANE, surface } as never)
    await (pane as never as { input: (a: { key: string; text: string }) => Promise<unknown> }).input({ key: 'answer-d1', text: 'yes, for now' })
    await pane.unmount()
  }
  expect(sent).toEqual([
    'Answer to decision d1 ("Keep it?"): yes, for now',
    'Answer to decision d1 ("Keep it?"): yes, for now',
  ])
})

test('two decisions opened at once get different ids and both are kept', async ($, on) => {
  mock.clock(on)
  on('ui.render', ($, e) => {
    const { Box } = $.ui.resolve(e)
    return <Box key="engine-own" />
  })
  const [a, b] = await Promise.all([
    $.tool.call({ tool: OPEN, question: 'First?' } as never),
    $.tool.call({ tool: OPEN, question: 'Second?' } as never),
  ])
  const ids = [a, b].map(r => String((r as { result?: unknown }).result))
  expect(ids.sort()).toEqual(['Opened decision d1.', 'Opened decision d2.'])

  const band = await $.ui.mount({ ...BAND, surface: 'terminal' } as never)
  expect(await texts(band as never)).toContain('2 decisions wait on you')
  await band.unmount()
})

test('an open decision is kept however many come after it', async ($, on) => {
  mock.clock(on)
  for (let i = 1; i <= 60; i++) {
    await $.tool.call({ tool: OPEN, question: `Question ${i}?` } as never)
  }
  const closed = await $.tool.call({ tool: CLOSE, id: 'd1' } as never)
  expect(String((closed as { result?: unknown }).result)).toBe('Closed decision d1.')
})

test('the band keeps what other plugins draw there', async ($, on) => {
  mock.clock(on)
  on('ui.render', ($, e) => {
    const { Text } = $.ui.resolve(e)
    return <Text>another plugin's band</Text>
  })
  await $.tool.call({ tool: OPEN, question: 'Keep both?' } as never)

  for (const surface of ['terminal', 'desktop'] as const) {
    const band = await $.ui.mount({ ...BAND, surface } as never)
    const shown = await texts(band as never)
    expect(shown).toContain('1 decision waits on you')
    expect(shown).toContain("another plugin's band")
    await band.unmount()
  }
})

test('recently settled lists the latest closed first, whatever order they were opened in', async ($, on) => {
  const clock = mock.clock(on)
  on('ui.render', ($, e) => {
    const { Box } = $.ui.resolve(e)
    return <Box key="engine-own" />
  })
  for (let i = 1; i <= 7; i++) {
    await $.tool.call({ tool: OPEN, question: `Question ${i}?` } as never)
  }
  for (let i = 2; i <= 7; i++) {
    await clock.advance(1000)
    await $.tool.call({ tool: CLOSE, id: `d${i}` } as never)
  }
  await clock.advance(1000)
  await $.tool.call({ tool: CLOSE, id: 'd1' } as never)

  const pane = await $.ui.mount({ ...PANE, surface: 'terminal' } as never)
  const settledRows = (await texts(pane as never)).filter(t => t.startsWith('✓'))
  expect(settledRows[0]).toContain('Question 1?')
  expect(settledRows).toHaveLength(5)
  await pane.unmount()
})

const BASH = 'Bash'
const PASSED = 'OK: git is installed\nOK: codex is installed (codex-cli 0.46.0)\nOK: gh is signed in\nCheck OK (0 warning(s))\n'
const WARNED = 'OK: git is installed\nWARN: codex is not installed: mentat challenge needs it\nCheck OK (1 warning(s))\n'
const FAILED = 'OK: git is installed\nPROBLEM: gh is not signed in (run gh auth login)\nCheck failed: 1 problem(s)\n'

type Shown = { text?: string; props?: { color?: string; dimColor?: boolean } }
const rows = async (ui: unknown) =>
  ((await (ui as { findAll: (q: { type: string }) => Promise<Shown[]> }).findAll({ type: 'Text' })) ?? []).map(t => ({
    text: (t.text ?? '').trim(),
    color: t.props?.color,
    dim: t.props?.dimColor === true,
  }))

// What the engine would answer for a Bash call: the typed record, or for a failing
// command (exit 1) an error whose text is what the model read.
const answer = (output: string, failed = false) =>
  (failed
    ? { isError: true, result: undefined, text: `Exit code 1\n${output}` }
    : { result: { stdout: output, stderr: '', interrupted: false }, text: output }) as never

const withBash = ($: { tool: { call: (a: never) => Promise<unknown> } }, on: never, reply: () => unknown) => {
  ;(on as (e: string, h: () => unknown) => void)('tool.call', reply)
  return (command: string) => $.tool.call({ tool: BASH, command } as never)
}

const bandRows = async ($: { ui: { mount: (a: never) => Promise<unknown> } }, surface: 'terminal' | 'desktop', props = {}) => {
  const band = await $.ui.mount({ ...BAND, props: { hasSurvey: false, ...props }, surface } as never)
  const shown = await rows(band)
  await (band as { unmount: () => Promise<unknown> }).unmount()
  return shown
}

const stubBand = (on: Parameters<typeof mock.clock>[0], drawn?: string) => {
  mock.clock(on)
  on('ui.render', ($, e) => {
    const { Box, Text } = $.ui.resolve(e)
    return drawn === undefined ? <Box key="engine-own" /> : <Text>{drawn}</Text>
  })
}

test('before any check the band says only that Mentat is loaded', async ($, on) => {
  stubBand(on)
  for (const surface of ['terminal', 'desktop'] as const) {
    expect(await bandRows($ as never, surface)).toEqual([{ text: 'Mentat loaded', color: undefined, dim: true }])
  }
})

test('a passing check shows Mentat engaged in green with the Codex version', async ($, on) => {
  stubBand(on)
  const run = withBash($ as never, on as never, () => answer(PASSED))
  await run('mentat check')
  for (const surface of ['terminal', 'desktop'] as const) {
    expect(await bandRows($ as never, surface)).toEqual([
      { text: '● Mentat engaged · codex-cli 0.46.0', color: 'success', dim: false },
    ])
  }
})

test('a check with warnings shows each warning in yellow under the green line', async ($, on) => {
  stubBand(on)
  const run = withBash($ as never, on as never, () => answer(WARNED))
  await run('mentat check')
  for (const surface of ['terminal', 'desktop'] as const) {
    expect(await bandRows($ as never, surface)).toEqual([
      { text: '● Mentat engaged', color: 'success', dim: false },
      { text: 'codex is not installed: mentat challenge needs it', color: 'warning', dim: false },
    ])
  }
})

test('a failing check shows each problem in red, and a later pass replaces it', async ($, on) => {
  stubBand(on)
  let reply: unknown = answer(FAILED, true)
  const run = withBash($ as never, on as never, () => reply)
  await run('mentat check')
  for (const surface of ['terminal', 'desktop'] as const) {
    expect(await bandRows($ as never, surface)).toEqual([
      { text: '● Mentat check failed', color: 'error', dim: false },
      { text: 'gh is not signed in (run gh auth login)', color: 'error', dim: false },
    ])
  }
  reply = answer(PASSED)
  await run('mentat check')
  expect((await bandRows($ as never, 'terminal'))[0]?.text).toBe('● Mentat engaged · codex-cli 0.46.0')
})

test('the check is found however the agent words the command', async ($, on) => {
  stubBand(on)
  let reply: unknown
  const run = withBash($ as never, on as never, () => reply)
  for (const command of [
    'cd "/some path/repo" && mentat check 2>&1',
    'mentat check 2>&1 | cat',
    '"${CLAUDE_PLUGIN_ROOT}/bin/mentat" check',
    '/opt/mentat/bin/mentat check; echo done',
  ]) {
    reply = answer(PASSED)
    await run('mentat check')
    expect((await bandRows($ as never, 'terminal'))[0]?.text).toBe('● Mentat engaged · codex-cli 0.46.0')
    reply = answer(FAILED, true)
    await run(command)
    expect((await bandRows($ as never, 'terminal'))[0]?.text).toBe('● Mentat check failed')
  }
})

test('an unrelated Bash call, or a check with no final line, changes nothing', async ($, on) => {
  stubBand(on)
  let reply: unknown = answer(FAILED, true)
  const run = withBash($ as never, on as never, () => reply)
  const loaded = [{ text: 'Mentat loaded', color: undefined, dim: true }]
  for (const command of ['ls', 'echo mentat checkout', 'mentat review', 'git commit -m "mentat checks"']) {
    await run(command)
    expect(await bandRows($ as never, 'terminal')).toEqual(loaded)
  }
  reply = answer('OK: git is installed\n')
  await run('mentat check | head -n 1')
  expect(await bandRows($ as never, 'terminal')).toEqual(loaded)

  // A passed check stays as it was when an unrelated call comes after it.
  reply = answer(PASSED)
  await run('mentat check')
  await run('ls')
  expect((await bandRows($ as never, 'terminal'))[0]?.text).toBe('● Mentat engaged · codex-cli 0.46.0')
})

test('the check line sits above open decisions, and a survey takes the band from both', async ($, on) => {
  stubBand(on, "another plugin's band")
  const run = withBash($ as never, on as never, () => answer(PASSED))
  await run('mentat check')
  await $.tool.call({ tool: OPEN, question: 'Keep both?' } as never)

  for (const surface of ['terminal', 'desktop'] as const) {
    const shown = (await bandRows($ as never, surface)).map(r => r.text)
    expect(shown).toEqual([
      '● Mentat engaged · codex-cli 0.46.0',
      '1 decision waits on you',
      '· Keep both?',
      "another plugin's band",
    ])
    expect(await bandRows($ as never, surface, { hasSurvey: true })).toEqual([
      { text: "another plugin's band", color: undefined, dim: false },
    ])
  }
})
