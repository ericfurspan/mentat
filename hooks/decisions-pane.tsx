// The decisions pane: a /decisions command, two tools the model calls to record questions, a band above the prompt and a pane to answer them.
// The band's first line also shows the result of the agent's last `mentat check`, read from its Bash result.
// Claude Code reads this file as a mod (hooks/hooks.json lists it under "modules"); it approves, denies or changes no other tool call.

import { atom, read, update } from 'claude-code'
import type { Register } from 'claude-code'

import type { CheckResult, Decision } from '../types'

const PLUGIN = 'mentat'
const PANE = 'decisions'
const OPEN_TOOL = `mcp__${PLUGIN}__open_decision`
const CLOSE_TOOL = `mcp__${PLUGIN}__close_decision`

const items = atom({ plugin: 'mentat', key: 'decisionsItems' } as const, [])
const nextId = atom({ plugin: 'mentat', key: 'decisionsNextId' } as const, 1)
const lastCheck = atom({ plugin: 'mentat', key: 'checkResult' } as const, null)

// `mentat check` as words anywhere in a command: after a `cd ... &&`, with a
// path or quotes around mentat, before `2>&1` or a pipe.
const CHECK_COMMAND = /(?:^|[\s;&|(/"'])mentat["']?\s+check(?=$|[\s;&|)"'])/

// The OK / WARN / PROBLEM lines and the final line of `mentat check`'s output.
// The final line says whether it passed; without one (an interrupted run, a
// usage error, output cut by a pipe) there is nothing to record.
const parseCheck = (output: string): CheckResult | undefined => {
  const lines = [...new Set(output.replace(/\r/g, '').split('\n').map(l => l.trimEnd()))]
  const passed = lines.some(l => /^Check OK \(\d+ warning\(s\)\)$/.test(l))
  const failed = lines.some(l => /^Check failed: \d+ problem\(s\)$/.test(l))
  if (passed === failed) {
    return undefined
  }
  const after = (tag: string) => lines.filter(l => l.startsWith(`${tag}: `)).map(l => l.slice(tag.length + 2))
  const codex = after('OK')
    .map(l => /^codex is installed \((.+)\)$/.exec(l)?.[1])
    .find(v => v !== undefined && v !== 'version unknown')

  return { passed, codex, warnings: after('WARN'), problems: after('PROBLEM') }
}

const isOpen = (d: Decision) => d.closedAt === undefined
// Settled decisions, most recently settled first.
const settled = (list: Decision[]): Decision[] =>
  list.filter(d => !isOpen(d)).sort((a, b) => (b.closedAt ?? 0) - (a.closedAt ?? 0))
// Open decisions are never dropped; of the settled ones, the pane shows the last
// five, so ten are kept.
const keepOpenAndRecent = (list: Decision[]): Decision[] => {
  const keep = new Set(settled(list).slice(0, 10))
  return list.filter(d => isOpen(d) || keep.has(d))
}

export const register: Register = on => {
  // $.state reads and writes are separate awaits, so two tool calls running at
  // once could take the same id or drop an entry. Every change runs here, in turn.
  let queue: Promise<unknown> = Promise.resolve()
  const inTurn = <T,>(work: () => Promise<T>): Promise<T> => {
    const run = queue.then(work, work)
    queue = run.catch(() => undefined)
    return run
  }

  on('session.start', async ($, e, next) => {
    await $.command.register({
      name: 'decisions',
      description: 'Show the questions and decisions waiting on you in a pane',
    })
    await $.tool.register({
      name: 'open_decision',
      description:
        'Record a question or decision you have just put to the user in chat, so it shows in their decisions pane until answered. ' +
        'Call it once per real question that waits on the user (not rhetorical ones, not routine status). ' +
        'Returns an id; call close_decision with that id when the user answers or the question no longer applies.',
      inputSchema: {
        type: 'object',
        properties: {
          question: { type: 'string', description: 'The question, in one short plain sentence' },
          recommendation: { type: 'string', description: 'Your recommendation, in a few words, if you gave one' },
        },
        required: ['question'],
      },
      isDeferred: false,
    })
    await $.tool.register({
      name: 'close_decision',
      description:
        'Close a question opened with open_decision once the user has answered it or it no longer applies.',
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

    return next(e)
  })

  on('command.run', { command: 'decisions' }, async $ => {
    await $.ui.open({ id: PANE, title: 'Decisions' })

    return { text: 'Decisions pane opened.' }
  })

  on('tool.call', { tool: OPEN_TOOL }, async ($, e) => {
    const input = e as unknown as { question?: unknown; recommendation?: unknown }
    const question = typeof input.question === 'string' ? input.question.trim() : ''
    if (question === '') {
      return { deny: 'open_decision needs a question.' }
    }
    const recommendation =
      typeof input.recommendation === 'string' && input.recommendation.trim() !== ''
        ? input.recommendation.trim()
        : undefined
    const id = await inTurn(async () => {
      const n = await read($, nextId)
      await update($, nextId, () => n + 1)
      const openedAt = await $.clock.now()
      await update($, items, list => keepOpenAndRecent([...list, { id: `d${n}`, question, recommendation, openedAt }]))
      return `d${n}`
    })

    return { result: `Opened decision ${id}.` }
  })

  on('tool.call', { tool: CLOSE_TOOL }, async ($, e) => {
    const input = e as unknown as { id?: unknown; outcome?: unknown }
    const id = typeof input.id === 'string' ? input.id : ''
    const outcome = typeof input.outcome === 'string' && input.outcome.trim() !== '' ? input.outcome.trim() : undefined
    const isClosed = await inTurn(async () => {
      const list = await read($, items)
      if (!list.some(d => d.id === id && isOpen(d))) {
        return false
      }
      const closedAt = await $.clock.now()
      await update($, items, all => all.map(d => (d.id === id ? { ...d, closedAt, outcome } : d)))
      return true
    })
    if (!isClosed) {
      return { deny: `No open decision with id ${id}.` }
    }

    return { result: `Closed decision ${id}.` }
  })

  // Records the agent's `mentat check`. A failing check exits 1, so the Bash
  // result may be an error: its stdout is then in `text` (what the model read)
  // and not in a typed record. Both are read; a duplicate line counts once.
  on('tool.call', { tool: 'Bash' }, async ($, e, next) => {
    const ran = await next(e)
    const command = (e as unknown as { command?: unknown }).command
    if (typeof command !== 'string' || !CHECK_COMMAND.test(command) || ran.deny !== undefined) {
      return ran
    }
    const record = ran.result as { stdout?: unknown; stderr?: unknown; interrupted?: unknown } | string | undefined
    const typed = typeof record === 'object' && record !== null ? record : undefined
    if (typed?.interrupted === true) {
      return ran
    }
    const output = [typed?.stdout, typed?.stderr, typeof record === 'string' ? record : undefined, ran.text]
      .filter((part): part is string => typeof part === 'string')
      .join('\n')
    const parsed = parseCheck(output)
    if (parsed !== undefined) {
      await update($, lastCheck, () => parsed)
    }

    return ran
  })

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    if (e.props.hasSurvey) {
      return next(e)
    }
    const open = (await read($, items)).filter(isOpen)
    const check = await read($, lastCheck)
    const { Box, Button, Text } = $.ui.resolve(e)
    const latest = open[open.length - 1]
    // The band is shared: what the plugins beneath draw stays, under these rows.
    const beneath = await next(e)

    return (
      <Box flexDirection="column">
        {check === null && <Text dimColor>Mentat loaded</Text>}
        {check !== null && check.passed && (
          <Text bold color="success">
            ● Mentat engaged{check.codex !== undefined ? ` · ${check.codex}` : ''}
          </Text>
        )}
        {check !== null && check.passed && check.warnings.map((w, i) => (
          <Text key={`warn-${i}`} color="warning">
            {'  '}{w}
          </Text>
        ))}
        {check !== null && !check.passed && (
          <Text bold color="error">
            ● Mentat check failed
          </Text>
        )}
        {check !== null && !check.passed && check.problems.map((p, i) => (
          <Text key={`problem-${i}`} color="error">
            {'  '}{p}
          </Text>
        ))}
        {latest !== undefined && (
          <Box>
            <Text bold color="claude">
              {open.length === 1 ? '1 decision waits on you' : `${open.length} decisions wait on you`}
            </Text>
            <Text color="text" wrap="truncate-end">
              {' '}· {latest.question}{' '}
            </Text>
            <Button key="show" label="Show" onPress={() => $.ui.open({ id: PANE, title: 'Decisions' })} />
          </Box>
        )}
        {beneath}
      </Box>
    )
  })

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const { Box, Button, Input, Text } = $.ui.resolve(e)
    const list = await read($, items)
    const open = list.filter(isOpen)
    const closed = settled(list).slice(0, 5)

    return (
      <Box flexDirection="column">
        <Text bold>Waiting on you</Text>
        {open.length === 0 && <Text dimColor>Nothing right now.</Text>}
        {open.map(d => (
          <Box key={d.id} flexDirection="column" marginTop={1}>
            <Text>• {d.question}</Text>
            {d.recommendation !== undefined && <Text italic>  Recommended: {d.recommendation}</Text>}
            <Input
              key={`answer-${d.id}`}
              placeholder="Type your answer"
              submitLabel="Send"
              onSubmit={async answer => {
                const text = answer.trim()
                if (text === '') return
                await $.prompt.submit({
                  text: `Answer to decision ${d.id} ("${d.question}"): ${text}`,
                })
              }}
            />
            <Button
              key={`done-${d.id}`}
              label="Dismiss"
              onPress={() =>
                inTurn(async () => {
                  const closedAt = await $.clock.now()
                  await update($, items, all =>
                    all.map(x => (x.id === d.id ? { ...x, closedAt, outcome: 'dismissed in the pane' } : x)),
                  )
                })
              }
            />
          </Box>
        ))}
        {closed.length > 0 && (
          <Box flexDirection="column" marginTop={1}>
            <Text bold>Recently settled</Text>
            {closed.map(d => (
              <Text key={d.id} color="success">
                ✓ {d.question}
                {d.outcome !== undefined ? ` → ${d.outcome}` : ''}
              </Text>
            ))}
          </Box>
        )}
      </Box>
    )
  })
}
