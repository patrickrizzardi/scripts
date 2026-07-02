import clipboardy from 'clipboardy';

/**
 * Cross-platform clipboard utilities with graceful error handling.
 */

export interface ClipboardResult {
  success: boolean;
  error?: string;
}

/**
 * Copy text to the system clipboard.
 * Returns success status - never throws.
 */
export async function copyToClipboard(text: string): Promise<ClipboardResult> {
  try {
    await clipboardy.write(text);
    return { success: true };
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Unknown clipboard error';
    return { success: false, error: message };
  }
}

/**
 * Read text from the system clipboard.
 * Returns the text or null if failed.
 */
export async function readFromClipboard(): Promise<string | null> {
  try {
    return await clipboardy.read();
  } catch {
    return null;
  }
}
