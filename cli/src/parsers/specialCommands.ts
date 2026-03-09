/**
 * Parsers for special commands that require dedicated remote session handling
 */

export interface CompactCommandResult {
    isCompact: boolean;
    originalMessage: string;
}

export interface ClearCommandResult {
    isClear: boolean;
}

export interface SpecialCommandResult {
    type: 'compact' | 'clear' | 'status' | 'cost' | 'plan'
        | 'fast' | 'rewind' | 'fork' | 'memory'
        | 'task' | 'insights' | 'plugins' | null;
    originalMessage?: string;
}

/**
 * Parse /compact command
 * Matches messages starting with "/compact " or exactly "/compact"
 */
export function parseCompact(message: string): CompactCommandResult {
    const trimmed = message.trim();
    
    if (trimmed === '/compact') {
        return {
            isCompact: true,
            originalMessage: trimmed
        };
    }
    
    if (trimmed.startsWith('/compact ')) {
        return {
            isCompact: true,
            originalMessage: trimmed
        };
    }
    
    return {
        isCompact: false,
        originalMessage: message
    };
}

/**
 * Parse /clear command
 * Only matches exactly "/clear"
 */
export function parseClear(message: string): ClearCommandResult {
    const trimmed = message.trim();
    
    return {
        isClear: trimmed === '/clear'
    };
}

/**
 * Unified parser for special commands
 * Returns the type of command and original message if applicable
 */
export function parseSpecialCommand(message: string): SpecialCommandResult {
    const compactResult = parseCompact(message);
    if (compactResult.isCompact) {
        return {
            type: 'compact',
            originalMessage: compactResult.originalMessage
        };
    }
    
    const clearResult = parseClear(message);
    if (clearResult.isClear) {
        return {
            type: 'clear'
        };
    }

    const trimmed = message.trim();
    if (trimmed === '/status') {
        return { type: 'status' };
    }
    if (trimmed === '/cost') {
        return { type: 'cost' };
    }
    if (trimmed === '/plan') {
        return { type: 'plan' };
    }
    if (trimmed === '/fast') {
        return { type: 'fast' };
    }
    if (trimmed === '/rewind' || trimmed.startsWith('/rewind ')) {
        return { type: 'rewind', originalMessage: trimmed };
    }
    if (trimmed === '/fork' || trimmed.startsWith('/fork ')) {
        return { type: 'fork', originalMessage: trimmed };
    }
    if (trimmed === '/memory') {
        return { type: 'memory' };
    }
    if (trimmed === '/task' || trimmed === '/tasks') {
        return { type: 'task' };
    }
    if (trimmed === '/insights') {
        return { type: 'insights' };
    }
    if (trimmed === '/plugins') {
        return { type: 'plugins' };
    }

    return {
        type: null
    };
}