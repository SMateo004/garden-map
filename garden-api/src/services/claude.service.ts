import Anthropic from '@anthropic-ai/sdk';
import { env } from '../config/env.js';

const client = new Anthropic({
    apiKey: process.env.ANTHROPIC_API_KEY || 'sk-ant-dummy-placeholder',
});

export async function callClaude(
    systemPrompt: string,
    userMessage: string,
    maxTokens: number = 1024
): Promise<any> {
    const response = await client.messages.create({
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
        throw new Error('Respuesta inesperada de Claude');
    }

    // Limpiar posibles bloques de código markdown antes de parsear
    const clean = content.text
        .replace(/```json\n?/g, '')
        .replace(/```\n?/g, '')
        .trim();

    return JSON.parse(clean);
}
