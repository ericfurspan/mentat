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
