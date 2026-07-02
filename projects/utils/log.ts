import chalk from 'chalk';

/**
 * Shared log utility with colored console output.
 * Provides consistent styling across all CLI tools.
 */

export const log = {
  /** Print an info message (cyan) */
  info: (message: string) => console.log(chalk.cyan(message)),

  /** Print a success message (green) */
  success: (message: string) => console.log(chalk.green(message)),

  /** Print a warning message (yellow) */
  warn: (message: string) => console.log(chalk.yellow(message)),

  /** Print an error message (red) */
  error: (message: string) => console.log(chalk.red(message)),

  /** Print a header/title (bold cyan) */
  header: (message: string) => console.log(chalk.bold.cyan(message)),

  /** Print a subheader (bold white) */
  subheader: (message: string) => console.log(chalk.bold.white(message)),

  /** Print dimmed/muted text (gray) */
  dim: (message: string) => console.log(chalk.dim(message)),

  /** Print plain text (no color) */
  plain: (message: string) => console.log(message),

  /** Print a separator line */
  separator: (char = '─', length = 50) => console.log(chalk.dim(char.repeat(length))),

  /** Print an empty line */
  newline: () => console.log(),

  /** Print a labeled value (label in dim, value in white) */
  labeled: (label: string, value: string) => console.log(`${chalk.dim(label)} ${chalk.white(value)}`),

  /** Print a list item with bullet */
  bullet: (message: string, indent = 2) => console.log(`${' '.repeat(indent)}${chalk.dim('•')} ${message}`),

  /** Print a success list item with checkmark */
  check: (message: string, indent = 2) => console.log(`${' '.repeat(indent)}${chalk.green('✓')} ${message}`),

  /** Print an error list item with x */
  cross: (message: string, indent = 2) => console.log(`${' '.repeat(indent)}${chalk.red('✗')} ${message}`),
};

/** Chalk instance for custom formatting */
export { chalk };
