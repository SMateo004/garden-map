import prisma from '../config/database.js';

export async function logAgentCall(params: {
  agentType: string;
  action: string;
  input?: unknown;
  output?: unknown;
  durationMs?: number;
  status?: 'SUCCESS' | 'ERROR';
  userId?: string;
}): Promise<void> {
  try {
    await prisma.agentLog.create({
      data: {
        agentType: params.agentType,
        action: params.action,
        input: params.input as any ?? null,
        output: params.output as any ?? null,
        durationMs: params.durationMs,
        status: params.status ?? 'SUCCESS',
        userId: params.userId,
      },
    });
  } catch (_) {
    // Never block main flow due to logging failure
  }
}
