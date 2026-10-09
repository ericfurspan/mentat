export type Decision = {
  id: string
  question: string
  recommendation?: string
  openedAt: number
  closedAt?: number
  outcome?: string
}

// The last `mentat check` the agent ran this session, as the band shows it.
export type CheckResult = {
  passed: boolean
  codex?: string
  warnings: string[]
  problems: string[]
}

declare module 'claude-code' {
  interface PluginState {
    'mentat': { decisionsItems: Decision[]; decisionsNextId: number; checkResult: CheckResult | null }
  }
}
