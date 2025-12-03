import { readdir, readFile, writeFile } from "fs/promises";
import { join } from "path";

// ============================================
// CONFIGURATION - Edit these values to customize
// ============================================
const config = {
  targetDir: "../printify-bulk-upload/app/data", // Directory to search in
  fileExtension: ".json", // File extension to look for
  mustContain: "\"image\":", // Only process files containing this (string or regex)
  findPattern: /"image":\s*"[^"]*"/g, // Pattern to find (string or regex)
  replaceWith: '"image": ""', // What to replace it with
};

// ============================================
// SCRIPT - No need to edit below this line
// ============================================

interface ReplaceConfig {
  targetDir: string;
  fileExtension: string;
  mustContain: string | RegExp;
  findPattern: string | RegExp;
  replaceWith: string;
}

async function* walkDir(dir: string, ext: string): AsyncGenerator<string> {
  const files = await readdir(dir, { withFileTypes: true });
  for (const file of files) {
    const path = join(dir, file.name);
    if (file.isDirectory()) {
      yield* walkDir(path, ext);
    } else if (file.name.endsWith(ext)) {
      yield path;
    }
  }
}

async function findAndReplace(config: ReplaceConfig): Promise<void> {
  const matchingFiles: string[] = [];

  // Step 1: Find all files that contain the required string
  const mustContainDisplay =
    typeof config.mustContain === "string"
      ? config.mustContain
      : config.mustContain.source;
  console.log(
    `Step 1: Finding files in "${config.targetDir}" containing "${mustContainDisplay}"...\n`,
  );

  for await (const file of walkDir(config.targetDir, config.fileExtension)) {
    const content = await readFile(file, "utf-8");
    const matches =
      typeof config.mustContain === "string"
        ? content.includes(config.mustContain)
        : config.mustContain.test(content);

    if (matches) {
      matchingFiles.push(file);
      console.log(`  Found: ${file}`);
    }
  }

  console.log(`\n  Total files found: ${matchingFiles.length}\n`);

  if (matchingFiles.length === 0) {
    console.log("No files found. Exiting.");
    return;
  }

  // Step 2: Replace in those files
  console.log("Step 2: Performing replacements...\n");

  let replacedCount = 0;
  let totalReplacements = 0;

  for (const file of matchingFiles) {
    const content = await readFile(file, "utf-8");
    const updated = content.replace(config.findPattern, config.replaceWith);

    if (updated !== content) {
      await writeFile(file, updated);
      replacedCount++;

      // Count how many replacements were made in this file
      const matches = content.match(config.findPattern);
      const numReplacements = matches ? matches.length : 0;
      totalReplacements += numReplacements;

      console.log(
        `  ✓ ${file} (${numReplacements} replacement${numReplacements > 1 ? "s" : ""})`,
      );
    }
  }

  console.log(`\n${"=".repeat(60)}`);
  console.log(`Done! Replaced in ${replacedCount} file(s).`);
  console.log(`Total replacements made: ${totalReplacements}`);
  console.log("=".repeat(60));
}

// Run the script
await findAndReplace(config);
