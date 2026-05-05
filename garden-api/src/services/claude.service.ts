import Anthropic from '@anthropic-ai/sdk';
import logger from '../shared/logger.js';

// Fail fast if key is missing: better to crash on startup than silently use a dummy key
const ANTHROPIC_API_KEY = process.env.ANTHROPIC_API_KEY;

// Client is created lazily on first call so missing key only matters when agents are actually used
let _client: Anthropic | null = null;
function getClient(): Anthropic {
    if (!ANTHROPIC_API_KEY) {
        throw new Error('ANTHROPIC_API_KEY is not set — Claude agents are disabled');
    }
    if (!_client) {
        _client = new Anthropic({ apiKey: ANTHROPIC_API_KEY });
    }
    return _client;
}

export async function callClaude(
    systemPrompt: string,
    userMessage: string,
    maxTokens: number = 1024
): Promise<any> {
    const start = Date.now();
    const response = await getClient().messages.create({
        model: process.env.CLAUDE_MODEL || 'claude-sonnet-4-6',
        max_tokens: maxTokens,
        system: systemPrompt,
        messages: [
            {
                role: 'user',
                content: userMessage,
            },
        ],
    });

    const content = response.content[0];
    if (!content || content.type !== 'text') {
        throw new Error('Respuesta inesperada de Claude: sin bloque de texto');
    }

    // Limpiar posibles bloques de código markdown antes de parsear
    const clean = content.text
        .replace(/```json\n?/g, '')
        .replace(/```\n?/g, '')
        .trim();

    try {
        return JSON.parse(clean);
    } catch (parseErr) {
        logger.error('[Claude] JSON parse failed', {
            raw: clean.slice(0, 300),
            durationMs: Date.now() - start,
            error: parseErr instanceof Error ? parseErr.message : String(parseErr),
        });
        throw new Error(`Claude devolvió JSON inválido: ${(parseErr as Error).message}`);
    }
}
