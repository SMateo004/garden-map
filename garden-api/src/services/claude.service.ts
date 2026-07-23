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
        system: [
            {
                type: 'text',
                text: systemPrompt,
                cache_control: { type: 'ephemeral' },
            },
        ],
        messages: [
            {
                role: 'user',
                content: userMessage,
            },
        ],
    } as any);

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

/**
 * Igual que callClaude pero adjunta un archivo (visión) junto al texto del
 * mensaje — imagen o PDF. Los PDF se mandan como bloque `document` (soporte
 * nativo de Claude para leer texto e imágenes dentro del PDF), las imágenes
 * como bloque `image`, igual que antes.
 */
export async function callClaudeVision(
    systemPrompt: string,
    userMessage: string,
    imageBuffer: Buffer,
    mediaType: 'image/jpeg' | 'image/png' | 'image/webp' | 'image/gif' | 'application/pdf',
    maxTokens: number = 512
): Promise<any> {
    const fileBlock = mediaType === 'application/pdf'
        ? {
            type: 'document',
            source: {
                type: 'base64',
                media_type: mediaType,
                data: imageBuffer.toString('base64'),
            },
        }
        : {
            type: 'image',
            source: {
                type: 'base64',
                media_type: mediaType,
                data: imageBuffer.toString('base64'),
            },
        };

    const response = await getClient().messages.create({
        model: process.env.CLAUDE_MODEL || 'claude-sonnet-4-6',
        max_tokens: maxTokens,
        system: [
            {
                type: 'text',
                text: systemPrompt,
                cache_control: { type: 'ephemeral' },
            },
        ],
        messages: [
            {
                role: 'user',
                content: [
                    fileBlock,
                    { type: 'text', text: userMessage },
                ],
            },
        ],
    } as any);

    const content = response.content[0];
    if (!content || content.type !== 'text') {
        throw new Error('Respuesta inesperada de Claude: sin bloque de texto');
    }

    const clean = content.text
        .replace(/```json\n?/g, '')
        .replace(/```\n?/g, '')
        .trim();

    try {
        return JSON.parse(clean);
    } catch (parseErr) {
        logger.error('[Claude Vision] JSON parse failed', {
            raw: clean.slice(0, 300),
            error: parseErr instanceof Error ? parseErr.message : String(parseErr),
        });
        throw new Error(`Claude devolvió JSON inválido: ${(parseErr as Error).message}`);
    }
}
