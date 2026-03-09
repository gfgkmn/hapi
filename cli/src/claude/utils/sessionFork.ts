/**
 * Session fork: duplicate a session JSONL and file-history for branching
 */

import { readFile, writeFile, readdir, copyFile, mkdir } from 'fs/promises';
import { join } from 'path';
import { homedir } from 'os';
import { existsSync } from 'fs';
import { randomUUID } from 'crypto';
import { logger } from '@/ui/logger';

interface ForkOptions {
    sessionId: string;
    workingDirectory: string;
    /** Fork from a specific message (truncate new session to this point) */
    messageId?: string;
}

interface ForkResult {
    success: boolean;
    message: string;
    newSessionId: string;
}

/**
 * Fork (branch) a Claude session by duplicating JSONL and file-history.
 *
 * - `/fork` → duplicate entire session
 * - `/fork <messageId>` → duplicate up to the specified message
 */
export async function forkSession(options: ForkOptions): Promise<ForkResult> {
    const { sessionId, workingDirectory, messageId } = options;
    const newSessionId = randomUUID();

    const claudeDir = join(homedir(), '.claude');
    const projectsDir = join(claudeDir, 'projects');

    // Find source JSONL
    const sourceJsonlPath = await findSessionJsonl(projectsDir, sessionId);
    if (!sourceJsonlPath) {
        return { success: false, message: `No session file found for ${sessionId}`, newSessionId: '' };
    }

    logger.debug(`[fork] Source JSONL: ${sourceJsonlPath}`);

    const rawContent = await readFile(sourceJsonlPath, 'utf-8');
    let lines = rawContent.split('\n').filter(l => l.trim());

    // If messageId provided, truncate to that point
    if (messageId) {
        const entries = lines.map((line, idx) => {
            try {
                return { parsed: JSON.parse(line), index: idx };
            } catch {
                return { parsed: null, index: idx };
            }
        });

        const targetIdx = entries.findIndex(e =>
            e.parsed?.uuid === messageId ||
            e.parsed?.messageId === messageId ||
            e.parsed?.message?.id === messageId
        );

        if (targetIdx !== -1) {
            lines = lines.slice(0, targetIdx);
            logger.debug(`[fork] Truncated new session to line ${targetIdx}`);
        } else {
            logger.debug(`[fork] Message ${messageId} not found, forking entire session`);
        }
    }

    // Write new JSONL with replaced session ID references
    const newLines = lines.map(line => {
        // Replace sessionId references in the JSONL entries
        return line.replaceAll(sessionId, newSessionId);
    });

    const sourceDir = join(sourceJsonlPath, '..');
    const newJsonlPath = join(sourceDir, `${newSessionId}.jsonl`);
    await writeFile(newJsonlPath, newLines.join('\n') + '\n');
    logger.debug(`[fork] Written new JSONL: ${newJsonlPath}`);

    // Copy file-history directory
    const sourceHistoryDir = join(claudeDir, 'file-history', sessionId);
    const newHistoryDir = join(claudeDir, 'file-history', newSessionId);

    if (existsSync(sourceHistoryDir)) {
        try {
            await mkdir(newHistoryDir, { recursive: true });
            const files = await readdir(sourceHistoryDir);
            for (const file of files) {
                await copyFile(
                    join(sourceHistoryDir, file),
                    join(newHistoryDir, file)
                );
            }
            logger.debug(`[fork] Copied ${files.length} file-history entries`);
        } catch (err) {
            logger.debug(`[fork] Failed to copy file-history: ${err}`);
        }
    }

    return {
        success: true,
        message: `Session forked. New session: ${newSessionId}`,
        newSessionId
    };
}

async function findSessionJsonl(projectsDir: string, sessionId: string): Promise<string | null> {
    if (!existsSync(projectsDir)) return null;

    try {
        const projectDirs = await readdir(projectsDir);
        for (const dir of projectDirs) {
            const candidate = join(projectsDir, dir, `${sessionId}.jsonl`);
            if (existsSync(candidate)) {
                return candidate;
            }
        }
    } catch {
        // Ignore readdir errors
    }

    return null;
}
