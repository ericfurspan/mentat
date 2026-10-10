// What an open item is: a question to answer, an action only the maintainer can take, or an
// alert (a failure the agent could not resolve). An item stored without a kind is a question.
// A warning is the mod's own: the item for a passing `mentat check` with warnings; the agent
// cannot open one.
export type DecisionKind = 'question' | 'action' | 'alert' | 'warning'

export type Decision = {
  id: string
  kind?: DecisionKind
  // The text of the item; for an alert from `mentat check`, its `Check failed:` line.
  question: string
  // An https URL (the issue or pull request that holds the steps); other values are not stored.
  link?: string
  recommendation?: string
  // The label of a one-press answer (for example Yes); the band shows it as a button.
  accept?: string
  openedAt: number
}

export type AgentStatus = 'pending' | 'running' | 'waiting' | 'idle' | 'completed' | 'failed' | 'killed' | 'unknown'

export type AgentRow = {
  id: string
  type: string
  description: string
  status: AgentStatus
  // Known only for agents spawned while this mod was loaded.
  startedAt?: number
  endedAt?: number
}

// The kinds of note in the pane's Log; each has its own icon and color.
export type LogKind = 'decision' | 'plan' | 'surprise' | 'waiting' | 'done'

// The kinds of event line the pane writes to the Log itself. The `note` tool never takes one.
export type EventKind = 'agentDone' | 'agentFailed' | 'asked' | 'answered' | 'dismissed' | 'check' | 'prOpened'

// What an `asked` or `check` event line is marked with: the kind of the item asked, or the result of the check.
export type EventMark = 'question' | 'action' | 'alert' | 'pass' | 'warn' | 'fail'

// One line of the Log (the Feed): when (clock time), its kind and its text (one line). A note is one
// Claude Code added; an event is one the pane wrote, drawn dim. A line stored without a source is a note.
export type NoteEntry = { at: number; kind: LogKind; text: string; source?: 'note' }
export type EventEntry = { at: number; kind: EventKind; text: string; source: 'event'; mark?: EventMark }
export type LogEntry = NoteEntry | EventEntry

// The last `mentat check` of the main session: pass, pass with warnings, or fail.
export type CheckResult = { state: 'pass' | 'warn' | 'fail'; warnings: string[] }

// An item that left the list without close_decision: dismissed in the band, or cleared when a new
// conversation started (source: clear, resume or fork). at is the clock time it left.
export type GoneEntry = { id: string; why: 'dismissed' | 'cleared'; source?: string; at: number }

// What the pane keeps in `$.store` for one conversation (key `conv:<session id>`), so
// `claude --continue` or `--resume` brings it back. Agent rows and view toggles are not kept.
export type SavedConversation = {
  // The clock time of the last change; a session start prunes the store to the 20 newest.
  savedAt: number
  items: Decision[]
  nextId: number
  sent: { id: string; text: string; isDelivered?: boolean }[]
  log: LogEntry[]
  checkResult: CheckResult | null
  gone: GoneEntry[]
}

declare module 'claude-code' {
  interface PluginState {
    'mentat': {
      decisionsItems: Decision[]
      decisionsNextId: number
      // Decisions whose answer was pressed, with the answer. isDelivered: the prompt entered the
      // session; until then it is held for the end of the running turn.
      decisionsSent: { id: string; text: string; isDelivered?: boolean }[]
      agents: AgentRow[]
      // The last `mentat check` run this conversation; null until one has run.
      checkResult: CheckResult | null
      // The session's log, oldest first (the pane shows it newest first); capped.
      log: LogEntry[]
      // Counts the conversations: bumped where a session start brings another session id's state in, so a
      // write that waited for the engine can tell it began in an earlier conversation.
      conversation: number
      // True while the Feed shows every log entry (default: the newest ten).
      logAll: boolean
      // Items that left without close_decision, oldest first; capped at 50, never drawn.
      decisionsGone: GoneEntry[]
      // The session id the conversation state above belongs to; null until a session start has set it. A
      // session start with another id loads that conversation from the store, and the same id keeps this.
      sessionOwner: string | null
    }
  }
}
