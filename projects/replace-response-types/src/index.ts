#!/usr/bin/env bun

import { log } from '@utils/log';
import { readdir, readFile, writeFile } from 'fs/promises';
import { join } from 'path';

// ============================================
// CONFIGURATION - Edit these values to customize
// ============================================
const config = {
  // Where to search for files
  targetDir: '../vpm-v2/api',

  // Only look at files with this extension
  fileExtension: '.ts',

  // FILE FILTER: Only process files that contain this text
  // Use this to narrow down which files to even consider
  // Example: "InvoiceItem" = only files that mention InvoiceItem
  // Set to empty string "" to process all files
  fileContains: 'InvoiceItem',

  // FIND: The pattern to search for (must include /g flag for global replace)
  // This runs ONLY on files that pass the fileContains filter above
  findPattern: /(InvoiceItem\.\w+\(\s*\{[\s\S]*?)category(?=\s*:)/,

  // REPLACE: What to replace matches with. This must be a string, but if it contains
  // capture groups, it will be replaced with the capture group.
  // Example: "paymentType$1" will be replaced with the first capture group.
  replaceWith: 'paymentType$1',
};

// ============================================
// SCRIPT - No need to edit below this line
// ============================================

interface ReplaceConfig {
  targetDir: string;
  fileExtension: string;
  fileContains: string;
  findPattern: RegExp;
  replaceWith: string;
}

async function* _walkDir(dir: string, ext: string): AsyncGenerator<string> {
  const files = await readdir(dir, { withFileTypes: true });
  for (const file of files) {
    const path = join(dir, file.name);
    if (file.isDirectory()) {
      yield* _walkDir(path, ext);
    } else if (file.name.endsWith(ext)) {
      yield path;
    }
  }
}

async function findAndReplace(cfg: ReplaceConfig): Promise<void> {
  log.header(`Find and Replace`);
  log.info(`Directory: ${cfg.targetDir}`);
  if (cfg.fileContains) {
    log.info(`Only files containing: "${cfg.fileContains}"`);
  }
  log.info(`Pattern: ${cfg.findPattern.source}`);
  log.info(`Replace with: "${cfg.replaceWith}"`);
  log.newline();

  let filesScanned = 0;
  let filesMatched = 0;
  let filesModified = 0;
  let totalReplacements = 0;

  for await (const file of _walkDir(cfg.targetDir, cfg.fileExtension)) {
    filesScanned++;
    const content = await readFile(file, 'utf-8');

    // Skip files that don't contain the filter text
    if (cfg.fileContains && !content.includes(cfg.fileContains)) {
      continue;
    }
    filesMatched++;

    // Reset lastIndex for global regex (important for reuse)
    cfg.findPattern.lastIndex = 0;

    const matches = content.match(cfg.findPattern);
    if (!matches) continue;

    const updated = content.replace(cfg.findPattern, cfg.replaceWith);
    await writeFile(file, updated);

    filesModified++;
    totalReplacements += matches.length;

    log.check(`${file} (${matches.length} replacement${matches.length > 1 ? 's' : ''})`);
  }

  log.newline();
  log.separator('=', 60);

  if (filesModified === 0) {
    log.warn('No replacements made.');
    log.dim(`Scanned ${filesScanned} files, ${filesMatched} matched filter`);
  } else {
    log.success(`Done! Modified ${filesModified} file(s).`);
    log.info(`Total replacements: ${totalReplacements}`);
    log.dim(`Scanned ${filesScanned} files, ${filesMatched} matched filter`);
  }

  log.separator('=', 60);
}

// Run the script
await findAndReplace(config);
