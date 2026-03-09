/**
 * Session rewind: truncate JSONL and restore files from Claude's file-history backups
 */

import { readFile, writeFile, rm, readdir, mkdir } from 'fs/promises';
import { join } from 'path';
import { homedir } from 'os';
import { existsSync } from 'fs';
import { logger } from '@/ui/logger';

interface RewindOptions {
    sessionId: string;
    workingDirectory: string;
    /** Rewind to before this specific message */
    messageId?: string;
    /** Rewind N turns (default: 1) */
    turns?: number;
}

interface RewindResult {
    success: boolean;
    message: string;
}

interface FileHistorySnapshot {
    type: 'file-history-snapshot';
    messageId: string;
    snapshot: {
        messageId: string;
        trackedFileBackups: Record<string, {
            backupFileName: string | null;
            version: number;
            backupTime: string;
        }>;
        timestamp: string;
    };
    isSnapshotUpdate?: boolean;
}

/**
 * Rewind a Claude session by truncating JSONL and restoring files.
 *
 * - `/rewind` → remove last 1 turn (user message + assistant response)
 * - `/rewind 3` → remove last 3 turns
 * - `/rewind <messageId>` → rewind to before the specified message
 */
export async function rewindSession(options: RewindOptions): Promise<RewindResult> {
    const { sessionId, workingDirectory, messageId, turns = 1 } = options;

    const claudeDir = join(homedir(), '.claude');
    const projectsDir = join(claudeDir, 'projects');

    // Find JSONL file for this session
    const jsonlPath = await findSessionJsonl(projectsDir, sessionId);
    if (!jsonlPath) {
        return { success: false, message: `No session file found for ${sessionId}` };
    }

    logger.debug(`[rewind] Found session JSONL: ${jsonlPath}`);

    const rawContent = await readFile(jsonlPath, 'utf-8');
    const lines = rawContent.split('\n').filter(l => l.trim());

    if (lines.length === 0) {
        return { success: false, message: 'Session is empty, nothing to rewind' };
    }

    // Parse all lines
    const entries = lines.map((line, idx) => {
        try {
            return { parsed: JSON.parse(line), index: idx };
        } catch {
            return { parsed: null, index: idx };
        }
    });

    // Find user message indices (turns)
    const userMessageIndices: number[] = [];
    for (const entry of entries) {
        if (!entry.parsed) continue;
        if (entry.parsed.type === 'human' || entry.parsed.role === 'human' || entry.parsed.role === 'user') {
            userMessageIndices.push(entry.index);
        }
    }

    if (userMessageIndices.length === 0) {
        return { success: false, message: 'No turns to rewind' };
    }

    let cutIndex: number;

    if (messageId) {
        // Find the line index of the message with this ID
        const targetIdx = entries.findIndex(e =>
            e.parsed?.uuid === messageId ||
            e.parsed?.messageId === messageId ||
            e.parsed?.message?.id === messageId
        );
        if (targetIdx === -1) {
            // Try matching user message indices by proximity
            return { success: false, message: `Message ${messageId} not found in session` };
        }
        cutIndex = targetIdx;
    } else {
        // Rewind N turns from the end
        const turnsToRemove = Math.min(turns, userMessageIndices.length);
        const targetTurnIdx = userMessageIndices.length - turnsToRemove;
        cutIndex = userMessageIndices[targetTurnIdx];
    }

    // Find the most recent file-history-snapshot BEFORE the cut point
    let snapshot: FileHistorySnapshot | null = null;
    for (let i = cutIndex - 1; i >= 0; i--) {
        const entry = entries[i].parsed;
        if (entry?.type === 'file-history-snapshot') {
            snapshot = entry as FileHistorySnapshot;
            break;
        }
    }

    // Also check if there's a snapshot AT the cut point (associated with the user message being rewound)
    // The snapshot for a turn is typically stored right before or at the user message
    for (let i = cutIndex; i < Math.min(cutIndex + 3, entries.length); i++) {
        const entry = entries[i].parsed;
        if (entry?.type === 'file-history-snapshot') {
            snapshot = entry as FileHistorySnapshot;
            break;
        }
    }

    // Restore files if we have a snapshot
    let filesRestored = 0;
    if (snapshot?.snapshot?.trackedFileBackups) {
        const fileHistoryDir = join(claudeDir, 'file-history', sessionId);
        const backups = snapshot.snapshot.trackedFileBackups;

        for (const [relativePath, backup] of Object.entries(backups)) {
            const targetPath = join(workingDirectory, relativePath);

            try {
                if (backup.backupFileName) {
                    // Restore from backup
                    const backupPath = join(fileHistoryDir, backup.backupFileName);
                    if (existsSync(backupPath)) {
                        const content = await readFile(backupPath, 'utf-8');
                        // Ensure directory exists
                        const dir = join(targetPath, '..');
                        await mkdir(dir, { recursive: true });
                        await writeFile(targetPath, content);
                        filesRestored++;
                        logger.debug(`[rewind] Restored: ${relativePath}`);
                    } else {
                        logger.debug(`[rewind] Backup not found: ${backupPath}`);
                    }
                } else {
                    // null backupFileName means file was newly created — delete it
                    if (existsSync(targetPath)) {
                        await rm(targetPath);
                        filesRestored++;
                        logger.debug(`[rewind] Deleted newly-created file: ${relativePath}`);
                    }
                }
            } catch (err) {
                logger.debug(`[rewind] Failed to restore ${relativePath}: ${err}`);
            }
        }
    }

    // Truncate JSONL
    const truncatedLines = lines.slice(0, cutIndex);
    await writeFile(jsonlPath, truncatedLines.join('\n') + '\n');

    const turnsRemoved = userMessageIndices.filter(i => i >= cutIndex).length;
    const parts = [`Rewound ${turnsRemoved} turn${turnsRemoved !== 1 ? 's' : ''}`];
    if (filesRestored > 0) {
        parts.push(`restored ${filesRestored} file${filesRestored !== 1 ? 's' : ''}`);
    }

    return { success: true, message: parts.join(', ') };
}

async function findSessionJsonl(projectsDir: string, sessionId: string): Promise<string | null> {
    // Session JSONL files are at ~/.claude/projects/<encoded-path>/<sessionId>.jsonl
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
