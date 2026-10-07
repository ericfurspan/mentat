export type Decision = {
  id: string
  question: string
  recommendation?: string
  openedAt: number
  closedAt?: number
  outcome?: string
}

declare module 'claude-code' {
  interface PluginState {
    'mentat': { decisionsItems: Decision[]; decisionsNextId: number }
  }
}
