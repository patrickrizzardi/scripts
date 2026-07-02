/**
 * Utilities for escaping special characters in regex patterns.
 */

/** Characters that have special meaning in regex and need escaping */
const REGEX_SPECIAL_CHARS = /[.*+?^${}()|[\]\\]/g;

/**
 * Escape special regex characters in a string so it can be used as a literal match.
 * @example escapeRegex("hello.world") => "hello\\.world"
 */
export function escapeRegex(text: string): string {
  return text.replace(REGEX_SPECIAL_CHARS, '\\$&');
}

/**
 * Escape special characters and also handle common whitespace for display.
 * Converts actual newlines/tabs to their escaped representations.
 * @example escapeRegexWithWhitespace("hello\nworld") => "hello\\nworld"
 */
export function escapeRegexWithWhitespace(text: string): string {
  return escapeRegex(text).replace(/\n/g, '\\n').replace(/\r/g, '\\r').replace(/\t/g, '\\t');
}

/**
 * Check if a string contains characters that would need escaping in a regex.
 */
export function hasSpecialChars(text: string): boolean {
  return REGEX_SPECIAL_CHARS.test(text);
}

/**
 * Check if a string contains newlines or other whitespace that spans lines.
 */
export function hasMultilineContent(text: string): boolean {
  return /[\n\r]/.test(text);
}

/**
 * Unescape a regex pattern back to literal text (inverse of escapeRegex).
 * Note: This is a best-effort function and may not perfectly reverse all escapes.
 */
export function unescapeRegex(pattern: string): string {
  return pattern.replace(/\\(.)/g, '$1').replace(/\\n/g, '\n').replace(/\\r/g, '\r').replace(/\\t/g, '\t');
}
