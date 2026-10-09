export type Decision = {
  id: string
  question: string
  recommendation?: string
  // The label of a one-press answer (for example Yes); the pane shows it as a button.
  accept?: string
  openedAt: number
  closedAt?: number
  outcome?: string
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
  | { kind: 'completed'; sha: string; findings: number; replied: number }
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
  isFinalChecked: boolean
}

// okAt and failedAt are clock times of the last good and the last failed read (0: none).
export type ReadMark = { seq: number; okAt: number; failedAt: number }

declare module 'claude-code' {
  interface PluginState {
    'mentat': {
      decisionsItems: Decision[]
      decisionsNextId: number
      // Decisions whose answer field is open.
      decisionsAnswering: string[]
      agents: AgentRow[]
      // The session's pull request as owner/repo#N, or '' for none.
      prRef: string
      pr: PrSnapshot | null
      prMark: ReadMark
      review: ReviewSnapshot | null
      reviewMark: ReadMark
      // The login gh acts as: the agent account.
      me: string
      seq: number
    }
  }
}
