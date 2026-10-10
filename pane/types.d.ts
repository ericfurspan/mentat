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
  // Model, effort and start are known only for agents spawned while this mod was loaded.
  model?: string
  effort?: string
  status: AgentStatus
  startedAt?: number
  endedAt?: number
  // As last reported by a turn.complete of the agent: input + cache write + output.
  tokens?: number
}

export type Checks = { failed: number; running: number; passed: number }

export type PrSnapshot = {
  ref: string
  seq: number
  head: string
  number: number
  title: string
  state: string
  isDraft: boolean
  reviewDecision: string
  mergeState: string
  checks: Checks
  // Other open pull requests; isLimit when the list hit its limit.
  others?: { count: number; isLimit: boolean }
}

export type CodexRead =
  | { kind: 'running'; sha: string }
  // hasReview: the app also posted a review object on the head (it may have no inline comment).
  | { kind: 'completed'; sha: string; findings: number; replied: number; hasReview: boolean }
  | { kind: 'failed'; sha: string }
  // The app's summary is about another commit than the head.
  | { kind: 'other'; sha: string }
  | { kind: 'none' }
  // A summary in a format this mod does not know.
  | { kind: 'unknown' }

export type ReviewSnapshot = {
  ref: string
  seq: number
  head: string
  codex: CodexRead
  local?: { sha: string; result?: 'NO FINDINGS' | 'FINDINGS' }
}

// The kinds of note in the pane's Log card; each has its own icon and color.
export type LogKind = 'decision' | 'plan' | 'surprise' | 'waiting' | 'done'

// One line of the Log card, a note Claude Code added: when (clock time), its kind and its text (one line).
export type LogEntry = { at: number; kind: LogKind; text: string }

// The last `mentat check` of the main session: pass, pass with warnings, or fail.
export type CheckResult = { state: 'pass' | 'warn' | 'fail'; warnings: string[] }

// okAt and failedAt are clock times of the last good and the last failed read (0: none).
// cause 'user': the read that failed was the agent account's login, not the review itself.
export type ReadMark = { seq: number; okAt: number; failedAt: number; cause?: 'user' }

declare module 'claude-code' {
  interface PluginState {
    'mentat': {
      decisionsItems: Decision[]
      decisionsNextId: number
      // Decisions whose answer was pressed, with the answer. isDelivered: the prompt entered the
      // session; until then it is held for the end of the running turn.
      decisionsSent: { id: string; text: string; isDelivered?: boolean }[]
      agents: AgentRow[]
      // True while the pane's Finished group of agents is collapsed (default: open).
      agentsFinishedHidden: boolean
      // The session's pull request as owner/repo#N, or '' for none.
      prRef: string
      pr: PrSnapshot | null
      prMark: ReadMark
      review: ReviewSnapshot | null
      reviewMark: ReadMark
      // The login gh acts as: the agent account.
      me: string
      seq: number
      // The last `mentat check` run this conversation; null until one has run.
      checkResult: CheckResult | null
      // The session's log, oldest first (the pane shows it newest first); capped.
      log: LogEntry[]
      // True while the pane's Log card shows every entry (default: the last five).
      logAll: boolean
    }
  }
}
