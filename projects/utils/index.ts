/**
 * Shared utilities for CLI tools.
 * Import from this file to access all utilities.
 *
 * @example
 * import { log, copyToClipboard, escapeRegex } from "../utils";
 */

export { log, chalk } from './log.js';
export { copyToClipboard, readFromClipboard, type ClipboardResult } from './clipboard.js';
export {
  escapeRegex,
  escapeRegexWithWhitespace,
  hasSpecialChars,
  hasMultilineContent,
  unescapeRegex,
} from './escapeRegex.js';
