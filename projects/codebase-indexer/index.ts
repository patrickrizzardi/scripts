#!/usr/bin/env bun

/**
 * Codebase Indexer
 *
 * Scans a TypeScript project and generates a markdown index of all exports
 * (functions, types, interfaces, constants, schemas).
 *
 * Uses file hashing for incremental updates - only re-parses changed files.
 *
 * Usage: bun run index.ts <project-path> [project-name]
 *
 * Output:
 *   - .claude/registry/{project-name}-registry.md (the index)
 *   - .claude/registry/.indexer-cache.json (hash cache for speed)
 */

import { readdir, readFile, writeFile, mkdir, exists } from 'fs/promises';
import { join, relative, resolve, basename } from 'path';
import { createHash } from 'crypto';

// ============================================================================
// Types
// ============================================================================

interface FileExports {
  functions: string[];
  types: string[];
  interfaces: string[];
  constants: string[];
  schemas: string[];
  classes: string[];
}

interface CacheEntry {
  hash: string;
  exports: FileExports | null;
}

interface Cache {
  [filePath: string]: CacheEntry;
}

interface IndexedFile {
  path: string;
  exports: FileExports;
}

type Category = 'shared' | 'utility' | 'types' | 'schemas' | 'constants' | 'feature';

// ============================================================================
// Configuration
// ============================================================================

const IGNORED_DIRS = new Set([
  'node_modules',
  'dist',
  'build',
  '.git',
  '.next',
  'coverage',
  '.turbo',
  '.cache',
  '.claude',
]);

const FILE_EXTENSIONS = ['.ts', '.tsx'];

// ============================================================================
// Helpers
// ============================================================================

function hashContent(content: string): string {
  return createHash('md5').update(content).digest('hex');
}

async function getAllFiles(dir: string, files: string[] = []): Promise<string[]> {
  const entries = await readdir(dir, { withFileTypes: true });

  for (const entry of entries) {
    if (IGNORED_DIRS.has(entry.name)) continue;

    const fullPath = join(dir, entry.name);

    if (entry.isDirectory()) {
      await getAllFiles(fullPath, files);
    } else if (FILE_EXTENSIONS.some((ext) => entry.name.endsWith(ext))) {
      files.push(fullPath);
    }
  }

  return files;
}

function parseExports(content: string): FileExports {
  const exports: FileExports = {
    functions: [],
    types: [],
    interfaces: [],
    constants: [],
    schemas: [],
    classes: [],
  };

  // Exported functions
  const funcPatterns = [
    /export\s+(?:async\s+)?function\s+(\w+)/g,
    /export\s+const\s+(\w+)\s*=\s*(?:async\s*)?\(/g,
    /export\s+const\s+(\w+)\s*=\s*(?:async\s*)?\w+\s*=>/g,
  ];

  for (const pattern of funcPatterns) {
    let match;
    while ((match = pattern.exec(content)) !== null) {
      if (!exports.functions.includes(match[1])) {
        exports.functions.push(match[1]);
      }
    }
  }

  // Exported types
  const typePattern = /export\s+type\s+(\w+)/g;
  let match;
  while ((match = typePattern.exec(content)) !== null) {
    exports.types.push(match[1]);
  }

  // Exported interfaces
  const interfacePattern = /export\s+interface\s+(\w+)/g;
  while ((match = interfacePattern.exec(content)) !== null) {
    exports.interfaces.push(match[1]);
  }

  // Exported classes
  const classPattern = /export\s+class\s+(\w+)/g;
  while ((match = classPattern.exec(content)) !== null) {
    exports.classes.push(match[1]);
  }

  // Exported constants (non-function) - more careful regex
  const lines = content.split('\n');
  for (const line of lines) {
    // Match: export const NAME = something (not a function)
    const constMatch = line.match(/^export\s+const\s+(\w+)\s*[=:]/);
    if (constMatch) {
      const name = constMatch[1];

      // Skip if already captured as function
      if (exports.functions.includes(name)) continue;

      // Check if it's a schema
      if (
        name.toLowerCase().includes('schema') ||
        line.includes('v.object') ||
        line.includes('z.object') ||
        line.includes('Joi.object')
      ) {
        exports.schemas.push(name);
      } else if (!line.includes('=>') && !line.match(/=\s*(?:async\s*)?\(/)) {
        exports.constants.push(name);
      }
    }
  }

  return exports;
}

function categorizeFile(filePath: string, projectPath: string): Category {
  const relativePath = relative(projectPath, filePath).toLowerCase();

  if (relativePath.includes('shared/') || relativePath.startsWith('shared/')) {
    return 'shared';
  }
  if (relativePath.includes('/utils/') || relativePath.includes('utils/')) {
    return 'utility';
  }
  if (relativePath.includes('/types/') || relativePath.includes('types/')) {
    return 'types';
  }
  if (relativePath.includes('/schemas/') || relativePath.includes('schemas/')) {
    return 'schemas';
  }
  if (relativePath.includes('/constants/') || relativePath.includes('constants/')) {
    return 'constants';
  }

  return 'feature';
}

function hasExports(exports: FileExports): boolean {
  return Object.values(exports).some((arr) => arr.length > 0);
}

// ============================================================================
// Main
// ============================================================================

async function main() {
  const args = process.argv.slice(2);

  if (args.length < 1) {
    console.error('Usage: bun run index.ts <project-path> [project-name]');
    process.exit(1);
  }

  const projectPath = resolve(args[0]);
  const projectName = args[1] || basename(projectPath);

  if (!(await exists(projectPath))) {
    console.error(`Project path does not exist: ${projectPath}`);
    process.exit(1);
  }

  // Setup output directory
  const outputDir = join(projectPath, '.claude', 'registry');
  await mkdir(outputDir, { recursive: true });

  const cacheFile = join(outputDir, '.indexer-cache.json');
  const outputFile = join(outputDir, `${projectName}-registry.md`);

  // Load cache
  let cache: Cache = {};
  if (await exists(cacheFile)) {
    try {
      const cacheContent = await readFile(cacheFile, 'utf8');
      cache = JSON.parse(cacheContent);
    } catch {
      cache = {};
    }
  }

  // Scan files
  console.log(`Scanning ${projectPath}...`);
  const files = await getAllFiles(projectPath);
  console.log(`Found ${files.length} TypeScript files`);

  const newCache: Cache = {};
  const results: Record<Category, IndexedFile[]> = {
    shared: [],
    utility: [],
    types: [],
    schemas: [],
    constants: [],
    feature: [],
  };

  let parsed = 0;
  let skipped = 0;

  for (const file of files) {
    const content = await readFile(file, 'utf8');
    const hash = hashContent(content);
    const relativePath = relative(projectPath, file);

    // Check cache
    if (cache[relativePath]?.hash === hash) {
      // Use cached result
      newCache[relativePath] = cache[relativePath];
      if (cache[relativePath].exports) {
        const category = categorizeFile(file, projectPath);
        results[category].push({
          path: relativePath,
          exports: cache[relativePath].exports,
        });
      }
      skipped++;
    } else {
      // Parse file
      const exports = parseExports(content);
      const fileHasExports = hasExports(exports);

      newCache[relativePath] = {
        hash,
        exports: fileHasExports ? exports : null,
      };

      if (fileHasExports) {
        const category = categorizeFile(file, projectPath);
        results[category].push({
          path: relativePath,
          exports,
        });
      }
      parsed++;
    }
  }

  console.log(`Parsed: ${parsed}, Cached: ${skipped}`);

  // Save cache
  await writeFile(cacheFile, JSON.stringify(newCache, null, 2));

  // Generate markdown
  const timestamp = new Date().toISOString();
  let md = `# Codebase Registry: ${projectName}\n\n`;
  md += `**Last Updated**: ${timestamp}\n`;
  md += `**Files Scanned**: ${files.length}\n\n`;

  const sections: { key: Category; title: string }[] = [
    { key: 'shared', title: 'Shared (Project-wide)' },
    { key: 'utility', title: 'Utilities' },
    { key: 'types', title: 'Types' },
    { key: 'schemas', title: 'Schemas' },
    { key: 'constants', title: 'Constants' },
    { key: 'feature', title: 'Feature-specific' },
  ];

  for (const section of sections) {
    const items = results[section.key];
    if (items.length === 0) continue;

    md += `## ${section.title}\n\n`;

    for (const item of items) {
      md += `### \`${item.path}\`\n`;

      const e = item.exports;
      if (e.functions.length > 0) {
        md += `- **Functions**: ${e.functions.join(', ')}\n`;
      }
      if (e.types.length > 0) {
        md += `- **Types**: ${e.types.join(', ')}\n`;
      }
      if (e.interfaces.length > 0) {
        md += `- **Interfaces**: ${e.interfaces.join(', ')}\n`;
      }
      if (e.schemas.length > 0) {
        md += `- **Schemas**: ${e.schemas.join(', ')}\n`;
      }
      if (e.constants.length > 0) {
        md += `- **Constants**: ${e.constants.join(', ')}\n`;
      }
      if (e.classes.length > 0) {
        md += `- **Classes**: ${e.classes.join(', ')}\n`;
      }
      md += '\n';
    }
  }

  await writeFile(outputFile, md);
  console.log(`Registry written to: ${outputFile}`);
}

main().catch(console.error);
