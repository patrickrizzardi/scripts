# Dev Helper CLI Rewrite Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `helper.sh` with an interactive TypeScript CLI (`dev-helper`) running on Bun in Docker, at `~/development/scripts/projects/dev-helper/`, with instant inotify-based file sync and multi-select dedup.

**Architecture:** One Bun/TypeScript project, `src/commands/*` (one file per menu item) + `src/commands/fileSync/*` (the sync subsystem, further split by responsibility) + `src/utils/*` (shared print/prompt/command-check helpers). `src/index.ts` is the menu loop. Every command splits pure/testable logic (arg-building, parsing, formatting) from the untestable glue that shells out or prompts interactively — mirrors how the original bats suite only tested the pure bash functions (`_rsync_apply_selection`, `_rsync_build_pairs_from_dir`, etc.), never the `read`/menu glue.

**Tech Stack:** Bun (`oven/bun:1.3-alpine` in Docker), TypeScript, `@clack/prompts` ^1.6.0 for interactive menus, `bun:test` for tests.

## Global Constraints

- Docker image pinned to `oven/bun:1.3-alpine` (spec: no Bun 3.3 release exists; 1.3 is current).
- Project root: `~/development/scripts/projects/dev-helper/` (spec: matches where other projects live).
- Folder for shared helpers is named `utils/`, not `lib/` (explicit user preference).
- The file-sync daemon (watcher + fallback) runs as a **host-native** `systemd --user` service — never inside the container (spec: must survive independent of the container).
- `docker-compose.yml` uses `network_mode: host`, `pid: host`, and bind-mounts `$HOME` + `/run/user/<uid>` with `DBUS_SESSION_BUS_ADDRESS` forwarded, so the container can reach the host's systemd/D-Bus session (spec: named tradeoff, less isolation for zero installed host runtimes).
- `helper.sh` and its bats tests are deleted once all 8 commands are ported (spec: full replacement, not a parallel tool).
- Every missing host dependency (`inotify-tools`, `rsync`, `colordiff`, `ss`, etc.) gets a checked-first, clear install-command message — never a raw failure (spec + existing `helper.sh` pattern).

---

## File Structure

```
~/development/scripts/projects/dev-helper/
├── run.sh                        # exports HOST_UID/HOST_GID, runs docker compose
├── docker-compose.yml
├── package.json
├── tsconfig.json
└── src/
    ├── index.ts
    ├── utils/
    │   ├── commandExists.ts
    │   ├── commandExists.test.ts
    │   ├── print.ts
    │   ├── print.test.ts
    │   └── prompt.ts              # thin @clack/prompts wrappers, no test (framework boilerplate)
    └── commands/
        ├── searchText.ts / .test.ts
        ├── findFiles.ts / .test.ts
        ├── diskUsage.ts
        ├── network.ts / .test.ts
        ├── systemInfo.ts / .test.ts
        ├── portUsage.ts / .test.ts
        ├── gitDiff.ts / .test.ts
        └── fileSync/
            ├── config.ts / .test.ts
            ├── addPairs.ts / .test.ts
            ├── viewPairs.ts / .test.ts
            ├── removePair.ts / .test.ts
            ├── watcher.ts / .test.ts
            ├── service.ts / .test.ts
            └── index.ts            # setupFileSync() orchestrator (menu item 8)
```

---

### Task 1: Project Scaffolding

**Files:**
- Create: `~/development/scripts/projects/dev-helper/package.json`
- Create: `~/development/scripts/projects/dev-helper/tsconfig.json`
- Create: `~/development/scripts/projects/dev-helper/docker-compose.yml`
- Create: `~/development/scripts/projects/dev-helper/run.sh`
- Create: `~/development/scripts/projects/dev-helper/.gitignore`

**Interfaces:**
- Produces: a working `bun install` / `bun test` / `bun run src/index.ts` environment inside the container for every later task to build on.

- [ ] **Step 1: Create the project directory and git-init it**

```bash
mkdir -p ~/development/scripts/projects/dev-helper/src
cd ~/development/scripts/projects/dev-helper
git init
```

- [ ] **Step 2: Write `package.json`**

```json
{
  "name": "dev-helper",
  "version": "1.0.0",
  "private": true,
  "type": "module",
  "module": "src/index.ts",
  "scripts": {
    "start": "bun run src/index.ts",
    "test": "bun test"
  },
  "dependencies": {
    "@clack/prompts": "^1.6.0"
  },
  "devDependencies": {
    "@types/bun": "latest"
  }
}
```

- [ ] **Step 3: Write `tsconfig.json`**

```json
{
  "compilerOptions": {
    "target": "ESNext",
    "module": "ESNext",
    "moduleResolution": "bundler",
    "strict": true,
    "skipLibCheck": true,
    "esModuleInterop": true,
    "types": ["bun-types"],
    "noUncheckedIndexedAccess": true
  }
}
```

- [ ] **Step 4: Write `docker-compose.yml`**

```yaml
services:
  dev-helper:
    image: oven/bun:1.3-alpine
    working_dir: /app
    volumes:
      - ./:/app
      - ${HOME}:${HOME}
      - /run/user/${HOST_UID}:/run/user/${HOST_UID}
    environment:
      - HOME=${HOME}
      - DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/${HOST_UID}/bus
    network_mode: host
    pid: host
    stdin_open: true
    tty: true
    command: sh -c "bun install && bun run src/index.ts"
```

- [ ] **Step 5: Write `run.sh`**

```bash
#!/bin/bash
# bash's $UID is a readonly builtin and is NOT exported to child processes by
# default, so docker compose can't see it via ${HOST_UID} without this export.
export HOST_UID
export HOST_GID
HOST_UID=$(id -u)
HOST_GID=$(id -g)
docker compose run --rm dev-helper
```

- [ ] **Step 6: Make `run.sh` executable and write `.gitignore`**

```bash
chmod +x run.sh
```

```gitignore
node_modules/
```

- [ ] **Step 7: Commit**

```bash
git add package.json tsconfig.json docker-compose.yml run.sh .gitignore
git commit -m "chore: scaffold dev-helper Bun/Docker project"
```

---

### Task 2: `utils/commandExists.ts`

**Files:**
- Create: `src/utils/commandExists.ts`
- Test: `src/utils/commandExists.test.ts`

**Interfaces:**
- Produces: `commandExists(cmd: string): boolean` — used by every command that shells out to an optional host binary (`du`/`df`, `ss`, `lscpu`/`free`, `colordiff`, `rsync`, `inotifywait`).

- [ ] **Step 1: Write the failing test**

```typescript
// src/utils/commandExists.test.ts
import { test, expect, describe } from "bun:test";
import { commandExists } from "./commandExists";

describe("commandExists", () => {
  test("returns true for a binary that is definitely on PATH", () => {
    expect(commandExists("ls")).toBe(true);
  });

  test("returns false for a binary that does not exist", () => {
    expect(commandExists("definitely-not-a-real-command-xyz")).toBe(false);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bun test src/utils/commandExists.test.ts`
Expected: FAIL — `Cannot find module './commandExists'`

- [ ] **Step 3: Write minimal implementation**

```typescript
// src/utils/commandExists.ts
export function commandExists(cmd: string): boolean {
  const result = Bun.spawnSync(["sh", "-c", `command -v ${cmd}`]);
  return result.exitCode === 0;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bun test src/utils/commandExists.test.ts`
Expected: PASS (2 tests)

- [ ] **Step 5: Commit**

```bash
git add src/utils/commandExists.ts src/utils/commandExists.test.ts
git commit -m "feat: add commandExists host-binary check"
```

---

### Task 3: `utils/print.ts`

**Files:**
- Create: `src/utils/print.ts`
- Test: `src/utils/print.test.ts`

**Interfaces:**
- Produces: `printError`, `printSuccess`, `printInfo`, `printWarning`, `printHeader`, `printMenuItem` (all `(msg: string) => void`, `printMenuItem(num: string, label: string) => void`) — the color-coded console output every command uses, 1:1 port of `helper.sh`'s `print_*` functions. Also exports the pure `format*` functions the tests exercise directly.

- [ ] **Step 1: Write the failing test**

```typescript
// src/utils/print.test.ts
import { test, expect, describe } from "bun:test";
import { formatError, formatSuccess, formatInfo, formatWarning, formatHeader, formatMenuItem } from "./print";

describe("print formatters", () => {
  test("formatError wraps in red and resets", () => {
    expect(formatError("boom")).toBe("\x1b[0;31mboom\x1b[0m");
  });

  test("formatSuccess wraps in green and resets", () => {
    expect(formatSuccess("done")).toBe("\x1b[0;32mdone\x1b[0m");
  });

  test("formatInfo wraps in blue and resets", () => {
    expect(formatInfo("note")).toBe("\x1b[0;34mnote\x1b[0m");
  });

  test("formatWarning wraps in yellow and resets", () => {
    expect(formatWarning("careful")).toBe("\x1b[1;33mcareful\x1b[0m");
  });

  test("formatHeader wraps in cyan with border markers", () => {
    expect(formatHeader("Menu")).toBe("\x1b[0;36m========== Menu ==========\x1b[0m");
  });

  test("formatMenuItem numbers the item in green, label uncolored", () => {
    expect(formatMenuItem("1.", "Find a file")).toBe("\x1b[0;32m1.\x1b[0m Find a file");
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bun test src/utils/print.test.ts`
Expected: FAIL — `Cannot find module './print'`

- [ ] **Step 3: Write minimal implementation**

```typescript
// src/utils/print.ts
const RED = "\x1b[0;31m";
const GREEN = "\x1b[0;32m";
const YELLOW = "\x1b[1;33m";
const BLUE = "\x1b[0;34m";
const CYAN = "\x1b[0;36m";
const RESET = "\x1b[0m";

export function formatError(msg: string): string {
  return `${RED}${msg}${RESET}`;
}

export function formatSuccess(msg: string): string {
  return `${GREEN}${msg}${RESET}`;
}

export function formatInfo(msg: string): string {
  return `${BLUE}${msg}${RESET}`;
}

export function formatWarning(msg: string): string {
  return `${YELLOW}${msg}${RESET}`;
}

export function formatHeader(msg: string): string {
  return `${CYAN}========== ${msg} ==========${RESET}`;
}

export function formatMenuItem(num: string, label: string): string {
  return `${GREEN}${num}${RESET} ${label}`;
}

export function printError(msg: string): void {
  console.log(formatError(msg));
}

export function printSuccess(msg: string): void {
  console.log(formatSuccess(msg));
}

export function printInfo(msg: string): void {
  console.log(formatInfo(msg));
}

export function printWarning(msg: string): void {
  console.log(formatWarning(msg));
}

export function printHeader(msg: string): void {
  console.log(formatHeader(msg));
}

export function printMenuItem(num: string, label: string): void {
  console.log(formatMenuItem(num, label));
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bun test src/utils/print.test.ts`
Expected: PASS (6 tests)

- [ ] **Step 5: Commit**

```bash
git add src/utils/print.ts src/utils/print.test.ts
git commit -m "feat: add print utils (port of helper.sh print_* functions)"
```

---

### Task 4: `utils/prompt.ts`

**Files:**
- Create: `src/utils/prompt.ts`

**Interfaces:**
- Consumes: `@clack/prompts` (from Task 1's `package.json`).
- Produces: `selectPrompt<T extends string>(message: string, options: {value: T; label: string}[]): Promise<T>`, `multiselectPrompt<T extends string>(message: string, options: {value: T; label: string}[]): Promise<T[]>`, `textPrompt(message: string, opts?: {defaultValue?: string; validate?: (v: string) => string | undefined}): Promise<string>`, `confirmPrompt(message: string): Promise<boolean>`.

No test file for this task: every function is a direct pass-through to `@clack/prompts` (framework boilerplate per the testing rule's "skip trivial ... framework boilerplate") — there is no branching logic of ours to verify, only the library's own behavior.

- [ ] **Step 1: Write the wrapper module**

```typescript
// src/utils/prompt.ts
import * as clack from "@clack/prompts";

export async function selectPrompt<T extends string>(
  message: string,
  options: { value: T; label: string }[],
): Promise<T> {
  const result = await clack.select({ message, options });
  if (clack.isCancel(result)) {
    clack.cancel("Cancelled.");
    process.exit(0);
  }
  return result as T;
}

export async function multiselectPrompt<T extends string>(
  message: string,
  options: { value: T; label: string }[],
): Promise<T[]> {
  const result = await clack.multiselect({ message, options, required: false });
  if (clack.isCancel(result)) {
    clack.cancel("Cancelled.");
    process.exit(0);
  }
  return result as T[];
}

export async function textPrompt(
  message: string,
  opts?: { defaultValue?: string; validate?: (v: string) => string | undefined },
): Promise<string> {
  const result = await clack.text({
    message,
    defaultValue: opts?.defaultValue,
    validate: opts?.validate,
  });
  if (clack.isCancel(result)) {
    clack.cancel("Cancelled.");
    process.exit(0);
  }
  return result as string;
}

export async function confirmPrompt(message: string): Promise<boolean> {
  const result = await clack.confirm({ message });
  if (clack.isCancel(result)) {
    clack.cancel("Cancelled.");
    process.exit(0);
  }
  return result as boolean;
}
```

- [ ] **Step 2: Verify it compiles**

Run: `bun x tsc --noEmit`
Expected: no errors

- [ ] **Step 3: Commit**

```bash
git add src/utils/prompt.ts
git commit -m "feat: add @clack/prompts wrappers"
```

---

### Task 5: `commands/fileSync/config.ts`

**Files:**
- Create: `src/commands/fileSync/config.ts`
- Test: `src/commands/fileSync/config.test.ts`

**Interfaces:**
- Produces: `SyncPair { source: string; target: string }`, `getConfigDir(home?: string): string`, `getPairsFilePath(home?: string): string`, `parsePairsFile(content: string): SyncPair[]`, `serializePairs(pairs: SyncPair[]): string`, `readPairs(home?: string): SyncPair[]`, `writePairs(pairs: SyncPair[], home?: string): void`. Every later fileSync task imports `SyncPair` from here.

- [ ] **Step 1: Write the failing test**

```typescript
// src/commands/fileSync/config.test.ts
import { test, expect, describe, beforeEach, afterEach } from "bun:test";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  parsePairsFile,
  serializePairs,
  readPairs,
  writePairs,
  getPairsFilePath,
} from "./config";

describe("parsePairsFile", () => {
  test("parses source|target lines", () => {
    const result = parsePairsFile("/src/a|/dest/a\n/src/b|/dest/b\n");
    expect(result).toEqual([
      { source: "/src/a", target: "/dest/a" },
      { source: "/src/b", target: "/dest/b" },
    ]);
  });

  test("skips blank lines and comment lines", () => {
    const result = parsePairsFile("\n#comment\n/src/a|/dest/a\n");
    expect(result).toEqual([{ source: "/src/a", target: "/dest/a" }]);
  });
});

describe("serializePairs", () => {
  test("round-trips through parsePairsFile", () => {
    const pairs = [{ source: "/src/a", target: "/dest/a" }, { source: "/src/b", target: "/dest/b" }];
    expect(parsePairsFile(serializePairs(pairs))).toEqual(pairs);
  });
});

describe("readPairs / writePairs", () => {
  let home: string;

  beforeEach(() => {
    home = mkdtempSync(join(tmpdir(), "dev-helper-test-"));
  });

  afterEach(() => {
    rmSync(home, { recursive: true, force: true });
  });

  test("readPairs returns empty array when pairs.conf does not exist", () => {
    expect(readPairs(home)).toEqual([]);
  });

  test("writePairs then readPairs round-trips", () => {
    const pairs = [{ source: "/src/a", target: "/dest/a" }];
    writePairs(pairs, home);
    expect(readPairs(home)).toEqual(pairs);
  });

  test("getPairsFilePath resolves under .config/rsync-sync", () => {
    expect(getPairsFilePath(home)).toBe(join(home, ".config", "rsync-sync", "pairs.conf"));
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bun test src/commands/fileSync/config.test.ts`
Expected: FAIL — `Cannot find module './config'`

- [ ] **Step 3: Write minimal implementation**

```typescript
// src/commands/fileSync/config.ts
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";

export interface SyncPair {
  source: string;
  target: string;
}

export function getConfigDir(home: string = process.env.HOME!): string {
  return join(home, ".config", "rsync-sync");
}

export function getPairsFilePath(home: string = process.env.HOME!): string {
  return join(getConfigDir(home), "pairs.conf");
}

export function parsePairsFile(content: string): SyncPair[] {
  const pairs: SyncPair[] = [];
  for (const line of content.split("\n")) {
    if (!line || line.startsWith("#")) continue;
    const [source, target] = line.split("|");
    if (!source || !target) continue;
    pairs.push({ source, target });
  }
  return pairs;
}

export function serializePairs(pairs: SyncPair[]): string {
  return pairs.map((p) => `${p.source}|${p.target}`).join("\n") + (pairs.length ? "\n" : "");
}

export function readPairs(home: string = process.env.HOME!): SyncPair[] {
  const path = getPairsFilePath(home);
  if (!existsSync(path)) return [];
  return parsePairsFile(readFileSync(path, "utf-8"));
}

export function writePairs(pairs: SyncPair[], home: string = process.env.HOME!): void {
  mkdirSync(getConfigDir(home), { recursive: true });
  writeFileSync(getPairsFilePath(home), serializePairs(pairs));
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bun test src/commands/fileSync/config.test.ts`
Expected: PASS (6 tests)

- [ ] **Step 5: Commit**

```bash
git add src/commands/fileSync/config.ts src/commands/fileSync/config.test.ts
git commit -m "feat: add fileSync pairs.conf read/write"
```

---

### Task 6: `commands/fileSync/addPairs.ts`

**Files:**
- Create: `src/commands/fileSync/addPairs.ts`
- Test: `src/commands/fileSync/addPairs.test.ts`

**Interfaces:**
- Consumes: `SyncPair` from `./config` (Task 5); `multiselectPrompt`, `textPrompt`, `selectPrompt` from `../../utils/prompt` (Task 4).
- Produces: `filterUnsyncedItems(items: string[], cwd: string, existingPairs: SyncPair[]): string[]`, `buildPairsFromSelection(cwd: string, targetDir: string, selectedItems: string[]): SyncPair[]`, `addPairsFlow(existingPairs: SyncPair[]): Promise<SyncPair[]>` (interactive, undertested — see below).

- [ ] **Step 1: Write the failing test**

```typescript
// src/commands/fileSync/addPairs.test.ts
import { test, expect, describe } from "bun:test";
import { filterUnsyncedItems, buildPairsFromSelection } from "./addPairs";
import type { SyncPair } from "./config";

describe("filterUnsyncedItems", () => {
  test("removes items already present as a source in existingPairs", () => {
    const existing: SyncPair[] = [{ source: "/home/pat/plugins", target: "/dest/plugins" }];
    const items = ["plugins", "settings.json"];
    expect(filterUnsyncedItems(items, "/home/pat", existing)).toEqual(["settings.json"]);
  });

  test("keeps every item when none are already synced", () => {
    const items = ["plugins", "settings.json"];
    expect(filterUnsyncedItems(items, "/home/pat", [])).toEqual(items);
  });

  test("only matches on the resolved cwd/item path, not a same-named source elsewhere", () => {
    const existing: SyncPair[] = [{ source: "/other/dir/plugins", target: "/dest/plugins" }];
    const items = ["plugins"];
    expect(filterUnsyncedItems(items, "/home/pat", existing)).toEqual(["plugins"]);
  });
});

describe("buildPairsFromSelection", () => {
  test("builds one pair per selected item", () => {
    const result = buildPairsFromSelection("/home/pat", "/dest", ["plugins", "settings.json"]);
    expect(result).toEqual([
      { source: "/home/pat/plugins", target: "/dest/plugins" },
      { source: "/home/pat/settings.json", target: "/dest/settings.json" },
    ]);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bun test src/commands/fileSync/addPairs.test.ts`
Expected: FAIL — `Cannot find module './addPairs'`

- [ ] **Step 3: Write minimal implementation**

```typescript
// src/commands/fileSync/addPairs.ts
import { readdirSync } from "node:fs";
import { join } from "node:path";
import type { SyncPair } from "./config";
import { multiselectPrompt, textPrompt, selectPrompt } from "../../utils/prompt";
import { printWarning, printInfo, printError, printHeader } from "../../utils/print";

export function filterUnsyncedItems(items: string[], cwd: string, existingPairs: SyncPair[]): string[] {
  const syncedSources = new Set(existingPairs.map((p) => p.source));
  return items.filter((item) => !syncedSources.has(join(cwd, item)));
}

export function buildPairsFromSelection(cwd: string, targetDir: string, selectedItems: string[]): SyncPair[] {
  return selectedItems.map((item) => ({
    source: join(cwd, item),
    target: join(targetDir, item),
  }));
}

async function multiSelectFromDir(existingPairs: SyncPair[]): Promise<SyncPair[]> {
  printWarning("Make sure your terminal is cd'd into the parent folder you want to sync FROM.");
  const cwd = process.cwd();
  printInfo(`Current directory: ${cwd}`);

  const allItems = readdirSync(cwd);
  const items = filterUnsyncedItems(allItems, cwd, existingPairs);

  if (items.length === 0) {
    printError("No unsynced files or directories found in this folder.");
    return [];
  }

  const selected = await multiselectPrompt(
    "Select items to sync",
    items.map((item) => ({ value: item, label: item })),
  );

  if (selected.length === 0) {
    printError("No items selected.");
    return [];
  }

  const targetDir = await textPrompt("Enter the target directory (e.g. ~/.claude):");
  const resolvedTarget = targetDir.replace(/^~/, process.env.HOME!);

  return buildPairsFromSelection(cwd, resolvedTarget, selected);
}

async function manualEntry(): Promise<SyncPair[]> {
  const src = await textPrompt("Enter full source path:");
  const tgt = await textPrompt("Enter full target path:");
  const source = src.replace(/^~/, process.env.HOME!);
  const target = tgt.replace(/^~/, process.env.HOME!);
  if (!source || !target) {
    printError("Source and target paths cannot be empty.");
    return [];
  }
  return [{ source, target }];
}

export async function addPairsFlow(existingPairs: SyncPair[]): Promise<SyncPair[]> {
  printHeader("Add Sync Pairs");
  const mode = await selectPrompt("How would you like to select source(s)?", [
    { value: "multi", label: "Multi-select from current directory" },
    { value: "manual", label: "Enter path manually" },
  ]);

  return mode === "multi" ? multiSelectFromDir(existingPairs) : manualEntry();
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bun test src/commands/fileSync/addPairs.test.ts`
Expected: PASS (4 tests) — `addPairsFlow` itself is untested (interactive glue, same as `helper.sh`'s `_rsync_add_pairs` was never bats-tested).

- [ ] **Step 5: Commit**

```bash
git add src/commands/fileSync/addPairs.ts src/commands/fileSync/addPairs.test.ts
git commit -m "feat: add addPairs flow with multi-select dedup"
```

---

### Task 7: `commands/fileSync/viewPairs.ts`

**Files:**
- Create: `src/commands/fileSync/viewPairs.ts`
- Test: `src/commands/fileSync/viewPairs.test.ts`

**Interfaces:**
- Consumes: `SyncPair` from `./config` (Task 5).
- Produces: `formatPairsList(pairs: SyncPair[]): string[]`, `viewPairs(pairs: SyncPair[]): void`.

- [ ] **Step 1: Write the failing test**

```typescript
// src/commands/fileSync/viewPairs.test.ts
import { test, expect, describe } from "bun:test";
import { formatPairsList } from "./viewPairs";

describe("formatPairsList", () => {
  test("numbers each pair as 'N. source -> target'", () => {
    const result = formatPairsList([
      { source: "/src/a", target: "/dest/a" },
      { source: "/src/b", target: "/dest/b" },
    ]);
    expect(result).toEqual(["1. /src/a -> /dest/a", "2. /src/b -> /dest/b"]);
  });

  test("returns an empty array for no pairs", () => {
    expect(formatPairsList([])).toEqual([]);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bun test src/commands/fileSync/viewPairs.test.ts`
Expected: FAIL — `Cannot find module './viewPairs'`

- [ ] **Step 3: Write minimal implementation**

```typescript
// src/commands/fileSync/viewPairs.ts
import type { SyncPair } from "./config";
import { printHeader, printMenuItem, printWarning } from "../../utils/print";

export function formatPairsList(pairs: SyncPair[]): string[] {
  return pairs.map((p, i) => `${i + 1}. ${p.source} -> ${p.target}`);
}

export function viewPairs(pairs: SyncPair[]): void {
  if (pairs.length === 0) {
    printWarning("No sync pairs configured.");
    return;
  }
  printHeader("Current Sync Pairs");
  formatPairsList(pairs).forEach((line, i) => {
    const [num, ...rest] = line.split(". ");
    printMenuItem(`${num}.`, rest.join(". "));
  });
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bun test src/commands/fileSync/viewPairs.test.ts`
Expected: PASS (2 tests)

- [ ] **Step 5: Commit**

```bash
git add src/commands/fileSync/viewPairs.ts src/commands/fileSync/viewPairs.test.ts
git commit -m "feat: add viewPairs"
```

---

### Task 8: `commands/fileSync/removePair.ts`

**Files:**
- Create: `src/commands/fileSync/removePair.ts`
- Test: `src/commands/fileSync/removePair.test.ts`

**Interfaces:**
- Consumes: `SyncPair` from `./config` (Task 5); `confirmPrompt`, `selectPrompt` from `../../utils/prompt` (Task 4); `viewPairs` from `./viewPairs` (Task 7).
- Produces: `removePairAt(pairs: SyncPair[], index: number): SyncPair[]`, `removePairFlow(pairs: SyncPair[]): Promise<SyncPair[]>`.

- [ ] **Step 1: Write the failing test**

```typescript
// src/commands/fileSync/removePair.test.ts
import { test, expect, describe } from "bun:test";
import { removePairAt } from "./removePair";
import type { SyncPair } from "./config";

const pairs: SyncPair[] = [
  { source: "/src/a", target: "/dest/a" },
  { source: "/src/b", target: "/dest/b" },
];

describe("removePairAt", () => {
  test("removes the pair at the given 1-based index", () => {
    expect(removePairAt(pairs, 1)).toEqual([{ source: "/src/b", target: "/dest/b" }]);
  });

  test("returns the array unchanged for an out-of-range index", () => {
    expect(removePairAt(pairs, 99)).toEqual(pairs);
  });

  test("returns the array unchanged for index 0", () => {
    expect(removePairAt(pairs, 0)).toEqual(pairs);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bun test src/commands/fileSync/removePair.test.ts`
Expected: FAIL — `Cannot find module './removePair'`

- [ ] **Step 3: Write minimal implementation**

```typescript
// src/commands/fileSync/removePair.ts
import type { SyncPair } from "./config";
import { confirmPrompt, selectPrompt } from "../../utils/prompt";
import { printWarning, printSuccess, printError } from "../../utils/print";
import { viewPairs, formatPairsList } from "./viewPairs";

export function removePairAt(pairs: SyncPair[], index: number): SyncPair[] {
  if (index < 1 || index > pairs.length) return pairs;
  return pairs.filter((_, i) => i !== index - 1);
}

export async function removePairFlow(pairs: SyncPair[]): Promise<SyncPair[]> {
  if (pairs.length === 0) {
    printWarning("No sync pairs configured.");
    return pairs;
  }

  viewPairs(pairs);
  const lines = formatPairsList(pairs);
  const choice = await selectPrompt(
    "Select the pair to remove",
    lines.map((line, i) => ({ value: String(i + 1), label: line })),
  );

  const index = Number(choice);
  const target = pairs[index - 1]!;
  const confirmed = await confirmPrompt(`Remove ${target.source} -> ${target.target}?`);
  if (!confirmed) return pairs;

  const updated = removePairAt(pairs, index);
  printSuccess("Pair removed.");
  if (updated.length === 0) {
    printWarning("All pairs removed. Consider stopping the service.");
  }
  return updated;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bun test src/commands/fileSync/removePair.test.ts`
Expected: PASS (3 tests)

- [ ] **Step 5: Commit**

```bash
git add src/commands/fileSync/removePair.ts src/commands/fileSync/removePair.test.ts
git commit -m "feat: add removePair flow"
```

---

### Task 9: `commands/fileSync/watcher.ts`

**Files:**
- Create: `src/commands/fileSync/watcher.ts`
- Test: `src/commands/fileSync/watcher.test.ts`

**Interfaces:**
- Consumes: `commandExists` from `../../utils/commandExists` (Task 2).
- Produces: `generateSyncScriptContent(): string`, `generateWatchScriptContent(): string`, `generateWatchServiceContent(): string`, `generateFallbackServiceContent(): string`, `generateFallbackTimerContent(): string`, `isInotifyToolsInstalled(): boolean`, `INOTIFY_INSTALL_COMMAND: string`.

- [ ] **Step 1: Write the failing test**

```typescript
// src/commands/fileSync/watcher.test.ts
import { test, expect, describe } from "bun:test";
import {
  generateSyncScriptContent,
  generateWatchScriptContent,
  generateWatchServiceContent,
  generateFallbackServiceContent,
  generateFallbackTimerContent,
  INOTIFY_INSTALL_COMMAND,
} from "./watcher";

describe("generateSyncScriptContent", () => {
  test("uses rsync -a --delete for directories", () => {
    expect(generateSyncScriptContent()).toContain("rsync -a --delete");
  });

  test("uses rsync -a for files", () => {
    expect(generateSyncScriptContent()).toContain('rsync -a "$source"');
  });

  test("reads pairs.conf", () => {
    expect(generateSyncScriptContent()).toContain("pairs.conf");
  });
});

describe("generateWatchScriptContent", () => {
  test("watches with inotifywait in recursive modify/create/delete/move mode", () => {
    const content = generateWatchScriptContent();
    expect(content).toContain("inotifywait -m -r -e modify,create,delete,move");
  });

  test("debounces before re-running sync.sh", () => {
    expect(generateWatchScriptContent()).toContain("read -r -t 0.3");
  });

  test("calls sync.sh after a change", () => {
    expect(generateWatchScriptContent()).toContain("sync.sh");
  });
});

describe("generateWatchServiceContent", () => {
  test("is a long-running Type=simple unit pointing at watch.sh", () => {
    const content = generateWatchServiceContent();
    expect(content).toContain("Type=simple");
    expect(content).toContain("%h/.config/rsync-sync/watch.sh");
  });
});

describe("generateFallbackServiceContent / generateFallbackTimerContent", () => {
  test("fallback service runs sync.sh as a oneshot", () => {
    const content = generateFallbackServiceContent();
    expect(content).toContain("Type=oneshot");
    expect(content).toContain("%h/.config/rsync-sync/sync.sh");
  });

  test("fallback timer fires every 5 minutes", () => {
    expect(generateFallbackTimerContent()).toContain("OnUnitActiveSec=5min");
  });
});

test("INOTIFY_INSTALL_COMMAND names the inotify-tools package", () => {
  expect(INOTIFY_INSTALL_COMMAND).toContain("inotify-tools");
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bun test src/commands/fileSync/watcher.test.ts`
Expected: FAIL — `Cannot find module './watcher'`

- [ ] **Step 3: Write minimal implementation**

```typescript
// src/commands/fileSync/watcher.ts
import { commandExists } from "../../utils/commandExists";

export const INOTIFY_INSTALL_COMMAND = "sudo apt-get update && sudo apt-get install -y inotify-tools";

export function isInotifyToolsInstalled(): boolean {
  return commandExists("inotifywait");
}

export function generateSyncScriptContent(): string {
  return `#!/bin/bash
PAIRS_FILE="$HOME/.config/rsync-sync/pairs.conf"
LOG_FILE="$HOME/.config/rsync-sync/sync.log"
mkdir -p "$(dirname "$LOG_FILE")"
while IFS='|' read -r source target; do
    [[ -z "$source" || "$source" == \\#* ]] && continue
    if [[ ! -e "$source" ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S'): source not found: $source" >> "$LOG_FILE"
        continue
    fi
    if [[ -d "$source" ]]; then
        mkdir -p "$target"
        rsync -a --delete "\${source}/" "\${target}/" 2>>"$LOG_FILE" \\
            || echo "$(date '+%Y-%m-%d %H:%M:%S'): rsync failed: $source -> $target" >> "$LOG_FILE"
    else
        mkdir -p "$(dirname "$target")"
        rsync -a "$source" "$target" 2>>"$LOG_FILE" \\
            || echo "$(date '+%Y-%m-%d %H:%M:%S'): rsync failed: $source -> $target" >> "$LOG_FILE"
    fi
done < "$PAIRS_FILE"
`;
}

export function generateWatchScriptContent(): string {
  return `#!/bin/bash
PAIRS_FILE="$HOME/.config/rsync-sync/pairs.conf"
SYNC_SCRIPT="$HOME/.config/rsync-sync/sync.sh"
LOG_FILE="$HOME/.config/rsync-sync/sync.log"
mkdir -p "$(dirname "$LOG_FILE")"

sources=()
while IFS='|' read -r source target; do
    [[ -z "$source" || "$source" == \\#* ]] && continue
    [[ -e "$source" ]] && sources+=("$source")
done < "$PAIRS_FILE"

if [[ \${#sources[@]} -eq 0 ]]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S'): no sources to watch, exiting" >> "$LOG_FILE"
    exit 0
fi

inotifywait -m -r -e modify,create,delete,move "\${sources[@]}" | while read -r _; do
    # Perf: drain any additional events for 300ms before syncing — collapses a
    # save's burst of modify/create/delete events into a single rsync run.
    while read -r -t 0.3 _; do :; done
    "$SYNC_SCRIPT"
done
`;
}

export function generateWatchServiceContent(): string {
  return `[Unit]
Description=rsync file sync watcher
After=network.target

[Service]
Type=simple
ExecStart=%h/.config/rsync-sync/watch.sh
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
`;
}

export function generateFallbackServiceContent(): string {
  return `[Unit]
Description=rsync file sync fallback reconciliation
After=network.target

[Service]
Type=oneshot
ExecStart=%h/.config/rsync-sync/sync.sh
`;
}

export function generateFallbackTimerContent(): string {
  return `[Unit]
Description=rsync file sync fallback timer

[Timer]
OnBootSec=1min
OnUnitActiveSec=5min
AccuracySec=5s

[Install]
WantedBy=timers.target
`;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bun test src/commands/fileSync/watcher.test.ts`
Expected: PASS (9 tests)

- [ ] **Step 5: Commit**

```bash
git add src/commands/fileSync/watcher.ts src/commands/fileSync/watcher.test.ts
git commit -m "feat: add inotify watcher + fallback unit generation"
```

---

### Task 10: `commands/fileSync/service.ts`

**Files:**
- Create: `src/commands/fileSync/service.ts`
- Test: `src/commands/fileSync/service.test.ts`

**Interfaces:**
- Consumes: `commandExists` from `../../utils/commandExists` (Task 2); the `generate*Content` functions and `isInotifyToolsInstalled`/`INOTIFY_INSTALL_COMMAND` from `./watcher` (Task 9).
- Produces: `isSystemdAvailable(): boolean`, `writeServiceFiles(home?: string): void`, `installCommands(): string[][]` (the pure list of argv arrays `installService()` runs — this is the testable seam), `installService(): { ok: true } | { ok: false; error: string }`, `serviceControlArgs(action: "start" | "stop" | "restart" | "status"): string[]`, `restartWatcher(): void`.

- [ ] **Step 1: Write the failing test**

```typescript
// src/commands/fileSync/service.test.ts
import { test, expect, describe, beforeEach, afterEach } from "bun:test";
import { mkdtempSync, rmSync, readFileSync, existsSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { writeServiceFiles, installCommands, serviceControlArgs } from "./service";

describe("writeServiceFiles", () => {
  let home: string;

  beforeEach(() => {
    home = mkdtempSync(join(tmpdir(), "dev-helper-test-"));
  });

  afterEach(() => {
    rmSync(home, { recursive: true, force: true });
  });

  test("writes sync.sh, watch.sh, and all four unit files", () => {
    writeServiceFiles(home);
    const systemdDir = join(home, ".config", "systemd", "user");
    const configDir = join(home, ".config", "rsync-sync");
    expect(existsSync(join(configDir, "sync.sh"))).toBe(true);
    expect(existsSync(join(configDir, "watch.sh"))).toBe(true);
    expect(existsSync(join(systemdDir, "rsync-sync-watch.service"))).toBe(true);
    expect(existsSync(join(systemdDir, "rsync-sync-fallback.service"))).toBe(true);
    expect(existsSync(join(systemdDir, "rsync-sync-fallback.timer"))).toBe(true);
  });

  test("sync.sh and watch.sh are executable", () => {
    writeServiceFiles(home);
    const configDir = join(home, ".config", "rsync-sync");
    const syncMode = require("node:fs").statSync(join(configDir, "sync.sh")).mode;
    const watchMode = require("node:fs").statSync(join(configDir, "watch.sh")).mode;
    expect(syncMode & 0o111).not.toBe(0);
    expect(watchMode & 0o111).not.toBe(0);
  });
});

describe("installCommands", () => {
  test("disables any legacy rsync-sync.timer, then enables the watch service and fallback timer", () => {
    const commands = installCommands();
    expect(commands).toContainEqual(["systemctl", "--user", "disable", "--now", "rsync-sync.timer"]);
    expect(commands).toContainEqual(["systemctl", "--user", "daemon-reload"]);
    expect(commands).toContainEqual(["systemctl", "--user", "enable", "--now", "rsync-sync-watch.service"]);
    expect(commands).toContainEqual(["systemctl", "--user", "enable", "--now", "rsync-sync-fallback.timer"]);
  });
});

describe("serviceControlArgs", () => {
  test("start targets the watch service", () => {
    expect(serviceControlArgs("start")).toEqual(["--user", "start", "rsync-sync-watch.service"]);
  });

  test("status targets the watch service", () => {
    expect(serviceControlArgs("status")).toEqual(["--user", "status", "rsync-sync-watch.service"]);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bun test src/commands/fileSync/service.test.ts`
Expected: FAIL — `Cannot find module './service'`

- [ ] **Step 3: Write minimal implementation**

```typescript
// src/commands/fileSync/service.ts
import { chmodSync, mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { commandExists } from "../../utils/commandExists";
import {
  generateSyncScriptContent,
  generateWatchScriptContent,
  generateWatchServiceContent,
  generateFallbackServiceContent,
  generateFallbackTimerContent,
} from "./watcher";
import { getConfigDir } from "./config";

export function isSystemdAvailable(): boolean {
  return commandExists("systemctl");
}

function getSystemdUserDir(home: string): string {
  return join(home, ".config", "systemd", "user");
}

export function writeServiceFiles(home: string = process.env.HOME!): void {
  const configDir = getConfigDir(home);
  const systemdDir = getSystemdUserDir(home);
  mkdirSync(configDir, { recursive: true });
  mkdirSync(systemdDir, { recursive: true });

  const syncScriptPath = join(configDir, "sync.sh");
  const watchScriptPath = join(configDir, "watch.sh");

  writeFileSync(syncScriptPath, generateSyncScriptContent());
  chmodSync(syncScriptPath, 0o755);

  writeFileSync(watchScriptPath, generateWatchScriptContent());
  chmodSync(watchScriptPath, 0o755);

  writeFileSync(join(systemdDir, "rsync-sync-watch.service"), generateWatchServiceContent());
  writeFileSync(join(systemdDir, "rsync-sync-fallback.service"), generateFallbackServiceContent());
  writeFileSync(join(systemdDir, "rsync-sync-fallback.timer"), generateFallbackTimerContent());
}

/**
 * The exact argv sequence installService() runs, in order. Split out as pure
 * data so it's testable without actually invoking systemctl.
 */
export function installCommands(): string[][] {
  return [
    ["loginctl", "enable-linger", process.env.USER ?? ""],
    // Legacy cleanup: earlier versions of this tool installed a 30s polling
    // timer under this name — disable it so it doesn't keep running
    // alongside the new watcher and double-sync.
    ["systemctl", "--user", "disable", "--now", "rsync-sync.timer"],
    ["systemctl", "--user", "daemon-reload"],
    ["systemctl", "--user", "enable", "--now", "rsync-sync-watch.service"],
    ["systemctl", "--user", "enable", "--now", "rsync-sync-fallback.timer"],
  ];
}

export function installService(): { ok: true } | { ok: false; error: string } {
  for (const [cmd, ...args] of installCommands()) {
    const result = Bun.spawnSync([cmd!, ...args]);
    // The legacy-timer disable is allowed to fail (it may not exist); every
    // other step is load-bearing.
    if (result.exitCode !== 0 && !args.includes("rsync-sync.timer")) {
      return { ok: false, error: `${cmd} ${args.join(" ")} failed` };
    }
  }
  return { ok: true };
}

export function serviceControlArgs(action: "start" | "stop" | "restart" | "status"): string[] {
  return ["--user", action, "rsync-sync-watch.service"];
}

export function restartWatcher(): void {
  Bun.spawnSync(["systemctl", ...serviceControlArgs("restart")]);
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bun test src/commands/fileSync/service.test.ts`
Expected: PASS (5 tests)

- [ ] **Step 5: Commit**

```bash
git add src/commands/fileSync/service.ts src/commands/fileSync/service.test.ts
git commit -m "feat: add systemd service install/control for the watcher"
```

---

### Task 11: `commands/fileSync/index.ts` — `setupFileSync()` orchestrator

**Files:**
- Create: `src/commands/fileSync/index.ts`

**Interfaces:**
- Consumes: everything from Tasks 5–10 (`config`, `addPairs`, `viewPairs`, `removePair`, `watcher`, `service`); `selectPrompt` from `../../utils/prompt`.
- Produces: `setupFileSync(): Promise<void>` — this is `src/index.ts`'s menu item 8.

No test file: this is the interactive top-level orchestrator, equivalent to `helper.sh`'s `setup_file_sync()`, which the original bats suite never tested directly either (it tested the `_rsync_*` primitives this task composes).

- [ ] **Step 1: Write the orchestrator**

```typescript
// src/commands/fileSync/index.ts
import { commandExists } from "../../utils/commandExists";
import { printError, printWarning, printHeader, printSuccess, printInfo } from "../../utils/print";
import { selectPrompt } from "../../utils/prompt";
import { readPairs, writePairs } from "./config";
import { addPairsFlow } from "./addPairs";
import { viewPairs } from "./viewPairs";
import { removePairFlow } from "./removePair";
import { isInotifyToolsInstalled, INOTIFY_INSTALL_COMMAND } from "./watcher";
import { isSystemdAvailable, writeServiceFiles, installService, restartWatcher, serviceControlArgs } from "./service";

async function manageService(): Promise<void> {
  const action = await selectPrompt("Service Control", [
    { value: "start", label: "Start" },
    { value: "stop", label: "Stop" },
    { value: "restart", label: "Restart" },
    { value: "status", label: "Status" },
  ]);
  const result = Bun.spawnSync(["systemctl", ...serviceControlArgs(action as "start" | "stop" | "restart" | "status")]);
  if (result.exitCode === 0) {
    printSuccess(`${action} succeeded.`);
  } else {
    printError(`Failed to ${action} the watcher service.`);
  }
}

export async function setupFileSync(): Promise<void> {
  if (!commandExists("rsync")) {
    printError("rsync is not installed.");
    printWarning("Install it with: sudo apt-get install -y rsync");
    return;
  }

  if (!isInotifyToolsInstalled()) {
    printError("inotify-tools is not installed (needed for instant sync).");
    printWarning(`Install it with: ${INOTIFY_INSTALL_COMMAND}`);
    return;
  }

  let pairs = readPairs();

  if (pairs.length === 0) {
    printHeader("File Sync Setup");
    printInfo("No existing configuration found. Let's set one up.");
    const newPairs = await addPairsFlow(pairs);
    if (newPairs.length === 0) {
      printError("No pairs added. Exiting.");
      return;
    }
    writePairs(newPairs);
    writeServiceFiles();
    const installed = installService();
    if (!installed.ok) {
      printError(`Watcher could not be enabled: ${installed.error}`);
      printWarning("Config was saved. Use 'Set up file sync' -> Service Control -> Start to retry.");
      return;
    }
    printSuccess("Sync configured! Active pairs:");
    viewPairs(newPairs);
    return;
  }

  while (true) {
    printHeader("File Sync Manager");
    const choice = await selectPrompt("Your choice", [
      { value: "add", label: "Add sync pairs" },
      { value: "view", label: "View existing pairs" },
      { value: "remove", label: "Remove a sync pair" },
      { value: "service", label: "Start / Stop / Restart / Status watcher" },
      { value: "exit", label: "Exit" },
    ]);

    if (choice === "add") {
      const added = await addPairsFlow(pairs);
      if (added.length > 0) {
        pairs = [...pairs, ...added];
        writePairs(pairs);
        restartWatcher();
        printSuccess("Pairs added.");
      }
    } else if (choice === "view") {
      viewPairs(pairs);
    } else if (choice === "remove") {
      pairs = await removePairFlow(pairs);
      writePairs(pairs);
      restartWatcher();
    } else if (choice === "service") {
      await manageService();
    } else {
      return;
    }
  }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `bun x tsc --noEmit`
Expected: no errors

- [ ] **Step 3: Commit**

```bash
git add src/commands/fileSync/index.ts
git commit -m "feat: wire fileSync subsystem into setupFileSync orchestrator"
```

---

### Task 12: `commands/searchText.ts`

**Files:**
- Create: `src/commands/searchText.ts`
- Test: `src/commands/searchText.test.ts`

**Interfaces:**
- Produces: `SearchTextOptions { searchPath: string; searchText: string; excludeDirs: string[] }`, `buildGrepArgs(opts: SearchTextOptions): string[]`, `searchTextInFiles(): Promise<void>`.

- [ ] **Step 1: Write the failing test**

```typescript
// src/commands/searchText.test.ts
import { test, expect, describe } from "bun:test";
import { buildGrepArgs } from "./searchText";

describe("buildGrepArgs", () => {
  test("builds a recursive grep with no excludes", () => {
    expect(buildGrepArgs({ searchPath: ".", searchText: "TODO", excludeDirs: [] })).toEqual([
      "-r",
      "TODO",
      ".",
    ]);
  });

  test("adds one --exclude-dir per excluded directory", () => {
    expect(
      buildGrepArgs({ searchPath: "src", searchText: "foo", excludeDirs: ["node_modules", "dist"] }),
    ).toEqual(["-r", "--exclude-dir=node_modules", "--exclude-dir=dist", "foo", "src"]);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bun test src/commands/searchText.test.ts`
Expected: FAIL — `Cannot find module './searchText'`

- [ ] **Step 3: Write minimal implementation**

```typescript
// src/commands/searchText.ts
import { textPrompt } from "../utils/prompt";
import { printInfo, printSuccess } from "../utils/print";

export interface SearchTextOptions {
  searchPath: string;
  searchText: string;
  excludeDirs: string[];
}

export function buildGrepArgs(opts: SearchTextOptions): string[] {
  const excludeArgs = opts.excludeDirs.map((dir) => `--exclude-dir=${dir}`);
  return ["-r", ...excludeArgs, opts.searchText, opts.searchPath];
}

export async function searchTextInFiles(): Promise<void> {
  const searchPath = await textPrompt("Enter the path to search in:", { defaultValue: "." });
  const searchText = await textPrompt("Enter the text to search for:");
  const excludeInput = await textPrompt("Enter directories to exclude (comma-separated):", {
    defaultValue: "",
  });
  const excludeDirs = excludeInput ? excludeInput.split(",").map((d) => d.trim()) : [];

  printInfo(`Searching for '${searchText}' in ${searchPath}...`);
  const args = buildGrepArgs({ searchPath, searchText, excludeDirs });
  const result = Bun.spawnSync(["grep", ...args], { stdout: "inherit", stderr: "inherit" });
  if (result.exitCode === 0) printSuccess("Search complete.");
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bun test src/commands/searchText.test.ts`
Expected: PASS (2 tests)

- [ ] **Step 5: Commit**

```bash
git add src/commands/searchText.ts src/commands/searchText.test.ts
git commit -m "feat: port search-text-in-files command"
```

---

### Task 13: `commands/findFiles.ts`

**Files:**
- Create: `src/commands/findFiles.ts`
- Test: `src/commands/findFiles.test.ts`

**Interfaces:**
- Produces: `FindFilesOptions { searchPath: string; filePattern: string; excludeDirs: string[] }`, `buildFindArgs(opts: FindFilesOptions): string[]`, `findFilesByName(): Promise<void>`.

- [ ] **Step 1: Write the failing test**

```typescript
// src/commands/findFiles.test.ts
import { test, expect, describe } from "bun:test";
import { buildFindArgs } from "./findFiles";

describe("buildFindArgs", () => {
  test("builds a find command with no excludes", () => {
    expect(buildFindArgs({ searchPath: "~/", filePattern: "*.js", excludeDirs: [] })).toEqual([
      "~/",
      "-type",
      "f",
      "-name",
      "*.js",
    ]);
  });

  test("adds -not -path per excluded directory", () => {
    expect(
      buildFindArgs({ searchPath: ".", filePattern: "config.*", excludeDirs: ["node_modules"] }),
    ).toEqual([".", "-type", "f", "-name", "config.*", "-not", "-path", "*/node_modules/*"]);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bun test src/commands/findFiles.test.ts`
Expected: FAIL — `Cannot find module './findFiles'`

- [ ] **Step 3: Write minimal implementation**

```typescript
// src/commands/findFiles.ts
import { textPrompt } from "../utils/prompt";
import { printInfo } from "../utils/print";

export interface FindFilesOptions {
  searchPath: string;
  filePattern: string;
  excludeDirs: string[];
}

export function buildFindArgs(opts: FindFilesOptions): string[] {
  const args = [opts.searchPath, "-type", "f", "-name", opts.filePattern];
  for (const dir of opts.excludeDirs) {
    args.push("-not", "-path", `*/${dir}/*`);
  }
  return args;
}

export async function findFilesByName(): Promise<void> {
  const searchPath = await textPrompt("Enter the path to search in:", { defaultValue: "~/" });
  const filePattern = await textPrompt("Enter the file name pattern (e.g. '*.js'):");
  const excludeInput = await textPrompt("Enter directories to exclude (comma-separated):", {
    defaultValue: "",
  });
  const excludeDirs = excludeInput ? excludeInput.split(",").map((d) => d.trim()) : [];

  printInfo(`Searching for files matching '${filePattern}' in ${searchPath}...`);
  const args = buildFindArgs({ searchPath, filePattern, excludeDirs });
  Bun.spawnSync(["find", ...args], { stdout: "inherit", stderr: "inherit" });
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bun test src/commands/findFiles.test.ts`
Expected: PASS (2 tests)

- [ ] **Step 5: Commit**

```bash
git add src/commands/findFiles.ts src/commands/findFiles.test.ts
git commit -m "feat: port find-files-by-name command"
```

---

### Task 14: `commands/diskUsage.ts`

**Files:**
- Create: `src/commands/diskUsage.ts`

**Interfaces:**
- Consumes: `commandExists` from `../utils/commandExists` (Task 2).
- Produces: `showDiskUsage(): Promise<void>`.

No test file: this command is 100% glue (checking two binaries exist, then shelling out to `df`/`du` and printing their output) — there is no branching or parsing logic of ours to assert on, matching how `helper.sh`'s `show_disk_usage` was never bats-tested.

- [ ] **Step 1: Write the implementation**

```typescript
// src/commands/diskUsage.ts
import { commandExists } from "../utils/commandExists";
import { printError, printWarning, printHeader, printSuccess } from "../utils/print";

export async function showDiskUsage(): Promise<void> {
  if (!commandExists("du") || !commandExists("df")) {
    printError("Error: Required commands 'du' or 'df' are missing.");
    printWarning("Please install them using: sudo apt-get update && sudo apt-get install -y coreutils");
    return;
  }

  printHeader("Disk Usage Information");
  printSuccess("Overall disk usage:");
  Bun.spawnSync(["df", "-h"], { stdout: "inherit" });

  const home = process.env.HOME!;
  printSuccess(`Largest directories in ${home}:`);
  const du = Bun.spawnSync(["du", "-h", "--max-depth=1", home]);
  const sort = Bun.spawnSync(["sh", "-c", "sort -hr | head -n 5"], { stdin: du.stdout });
  console.log(sort.stdout.toString());
}
```

- [ ] **Step 2: Verify it compiles**

Run: `bun x tsc --noEmit`
Expected: no errors

- [ ] **Step 3: Commit**

```bash
git add src/commands/diskUsage.ts
git commit -m "feat: port show-disk-usage command"
```

---

### Task 15: `commands/network.ts`

**Files:**
- Create: `src/commands/network.ts`
- Test: `src/commands/network.test.ts`

**Interfaces:**
- Consumes: `commandExists` from `../utils/commandExists` (Task 2).
- Produces: `buildSsArgs(showAll: boolean, proto: "tcp" | "udp"): string[]`, `showNetworkConnections(): Promise<void>`.

- [ ] **Step 1: Write the failing test**

```typescript
// src/commands/network.test.ts
import { test, expect, describe } from "bun:test";
import { buildSsArgs } from "./network";

describe("buildSsArgs", () => {
  test("tcp, listening only", () => {
    expect(buildSsArgs(false, "tcp")).toEqual(["-tln"]);
  });

  test("udp, listening only", () => {
    expect(buildSsArgs(false, "udp")).toEqual(["-uln"]);
  });

  test("tcp, show all connections", () => {
    expect(buildSsArgs(true, "tcp")).toEqual(["-tun"]);
  });

  test("udp, show all connections", () => {
    expect(buildSsArgs(true, "udp")).toEqual(["-un"]);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bun test src/commands/network.test.ts`
Expected: FAIL — `Cannot find module './network'`

- [ ] **Step 3: Write minimal implementation**

```typescript
// src/commands/network.ts
import { commandExists } from "../utils/commandExists";
import { confirmPrompt } from "../utils/prompt";
import { printError, printWarning, printHeader, printSuccess } from "../utils/print";

export function buildSsArgs(showAll: boolean, proto: "tcp" | "udp"): string[] {
  const protoFlag = proto === "tcp" ? "t" : "u";
  return showAll ? [`-${protoFlag}un`] : [`-${protoFlag}ln`];
}

export async function showNetworkConnections(): Promise<void> {
  if (!commandExists("ss")) {
    printError("Error: 'ss' command is missing.");
    printWarning("Please install it using: sudo apt-get update && sudo apt-get install -y iproute2");
    return;
  }

  const showAll = await confirmPrompt("Show all connections? (default: listening only)");

  printHeader("Network Connections");
  if (showAll) {
    printSuccess("Showing all network connections...");
  } else {
    printSuccess("Showing only listening connections...");
  }

  printSuccess("TCP connections:");
  Bun.spawnSync(["ss", ...buildSsArgs(showAll, "tcp")], { stdout: "inherit" });
  printSuccess("UDP connections:");
  Bun.spawnSync(["ss", ...buildSsArgs(showAll, "udp")], { stdout: "inherit" });
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bun test src/commands/network.test.ts`
Expected: PASS (4 tests)

- [ ] **Step 5: Commit**

```bash
git add src/commands/network.ts src/commands/network.test.ts
git commit -m "feat: port show-network-connections command"
```

---

### Task 16: `commands/systemInfo.ts`

**Files:**
- Create: `src/commands/systemInfo.ts`
- Test: `src/commands/systemInfo.test.ts`

**Interfaces:**
- Produces: `formatSystemInfo(info: { os: string; cpu: string; memory: string; disk: string; uptime: string }): string[]`, `showSystemInfo(): Promise<void>`.

- [ ] **Step 1: Write the failing test**

```typescript
// src/commands/systemInfo.test.ts
import { test, expect, describe } from "bun:test";
import { formatSystemInfo } from "./systemInfo";

describe("formatSystemInfo", () => {
  test("formats each field with its label", () => {
    const result = formatSystemInfo({
      os: "Linux 6.6.0",
      cpu: "AMD Ryzen 9",
      memory: "32G total",
      disk: "512G total",
      uptime: "up 3 days",
    });
    expect(result).toEqual([
      "OS: Linux 6.6.0",
      "CPU: AMD Ryzen 9",
      "Memory: 32G total",
      "Disk: 512G total",
      "Uptime: up 3 days",
    ]);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bun test src/commands/systemInfo.test.ts`
Expected: FAIL — `Cannot find module './systemInfo'`

- [ ] **Step 3: Write minimal implementation**

```typescript
// src/commands/systemInfo.ts
import { commandExists } from "../utils/commandExists";
import { printError, printWarning, printHeader, printSuccess } from "../utils/print";

export function formatSystemInfo(info: {
  os: string;
  cpu: string;
  memory: string;
  disk: string;
  uptime: string;
}): string[] {
  return [
    `OS: ${info.os}`,
    `CPU: ${info.cpu}`,
    `Memory: ${info.memory}`,
    `Disk: ${info.disk}`,
    `Uptime: ${info.uptime}`,
  ];
}

function run(cmd: string[]): string {
  return Bun.spawnSync(cmd).stdout.toString().trim();
}

export async function showSystemInfo(): Promise<void> {
  if (!commandExists("lscpu") || !commandExists("free")) {
    printError("Error: Required commands 'lscpu' or 'free' are missing.");
    printWarning("Please install them using: sudo apt-get update && sudo apt-get install -y procps lscpu");
    return;
  }

  const os = run(["uname", "-a"]);
  const cpu = run(["sh", "-c", "lscpu | grep 'Model name' | cut -d: -f2 | sed 's/^[ \\t]*//'"]);
  const memory = `${run(["sh", "-c", "free -h | grep Mem | awk '{print $2}'"])} total`;
  const disk = `${run(["sh", "-c", "df -h / | tail -1 | awk '{print $2}'"])} total`;
  const uptime = run(["uptime", "-p"]);

  printHeader("System Information");
  formatSystemInfo({ os, cpu, memory, disk, uptime }).forEach((line) => printSuccess(line));
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bun test src/commands/systemInfo.test.ts`
Expected: PASS (1 test)

- [ ] **Step 5: Commit**

```bash
git add src/commands/systemInfo.ts src/commands/systemInfo.test.ts
git commit -m "feat: port show-system-info command"
```

---

### Task 17: `commands/portUsage.ts`

**Files:**
- Create: `src/commands/portUsage.ts`
- Test: `src/commands/portUsage.test.ts`

**Interfaces:**
- Produces: `isValidPortNumber(input: string): boolean`, `findPortUsage(): Promise<void>`.

- [ ] **Step 1: Write the failing test**

```typescript
// src/commands/portUsage.test.ts
import { test, expect, describe } from "bun:test";
import { isValidPortNumber } from "./portUsage";

describe("isValidPortNumber", () => {
  test("accepts a plain numeric string", () => {
    expect(isValidPortNumber("8080")).toBe(true);
  });

  test("rejects a non-numeric string", () => {
    expect(isValidPortNumber("abc")).toBe(false);
  });

  test("rejects an empty string", () => {
    expect(isValidPortNumber("")).toBe(false);
  });

  test("rejects a negative number", () => {
    expect(isValidPortNumber("-1")).toBe(false);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bun test src/commands/portUsage.test.ts`
Expected: FAIL — `Cannot find module './portUsage'`

- [ ] **Step 3: Write minimal implementation**

```typescript
// src/commands/portUsage.ts
import { commandExists } from "../utils/commandExists";
import { textPrompt } from "../utils/prompt";
import { printError, printWarning, printHeader, printSuccess } from "../utils/print";

export function isValidPortNumber(input: string): boolean {
  return /^[0-9]+$/.test(input);
}

export async function findPortUsage(): Promise<void> {
  if (!commandExists("ss")) {
    printError("Error: 'ss' command is missing.");
    printWarning("Please install it using: sudo apt-get update && sudo apt-get install -y iproute2");
    return;
  }

  const portNumber = await textPrompt("Enter the port number to search for:", {
    validate: (v) => (isValidPortNumber(v) ? undefined : "Please enter a valid port number."),
  });

  printSuccess(`Searching for port ${portNumber}...`);
  printHeader("Port Usage Information");

  printSuccess("TCP connections:");
  const tcp = Bun.spawnSync(["sh", "-c", `sudo ss -tulnp | grep ":${portNumber}"`]);
  if (tcp.stdout.toString().trim()) {
    console.log(tcp.stdout.toString());
  } else {
    printWarning(`No TCP connections found on port ${portNumber}`);
  }

  printSuccess("UDP connections:");
  const udp = Bun.spawnSync(["sh", "-c", `sudo ss -ulnp | grep ":${portNumber}"`]);
  if (udp.stdout.toString().trim()) {
    console.log(udp.stdout.toString());
  } else {
    printWarning(`No UDP connections found on port ${portNumber}`);
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bun test src/commands/portUsage.test.ts`
Expected: PASS (4 tests)

- [ ] **Step 5: Commit**

```bash
git add src/commands/portUsage.ts src/commands/portUsage.test.ts
git commit -m "feat: port find-port-usage command"
```

---

### Task 18: `commands/gitDiff.ts`

**Files:**
- Create: `src/commands/gitDiff.ts`
- Test: `src/commands/gitDiff.test.ts`

**Interfaces:**
- Produces: `extractDiffFilenames(diffOutput: string): string[]`, `compareGitBranches(): Promise<void>`.

- [ ] **Step 1: Write the failing test**

```typescript
// src/commands/gitDiff.test.ts
import { test, expect, describe } from "bun:test";
import { extractDiffFilenames } from "./gitDiff";

describe("extractDiffFilenames", () => {
  test("extracts filenames from 'Only in' lines", () => {
    const output = "Only in /tmp/base/src: extra.ts\n";
    expect(extractDiffFilenames(output)).toEqual(["src/extra.ts"]);
  });

  test("extracts filenames from 'diff -r' lines and dedups base/target", () => {
    const output = [
      "diff -r /tmp/base/src/app.ts /tmp/target/src/app.ts",
      "1c1",
      "< old",
      "---",
      "> new",
    ].join("\n");
    expect(extractDiffFilenames(output)).toEqual(["src/app.ts"]);
  });

  test("returns an empty array when there are no differences", () => {
    expect(extractDiffFilenames("")).toEqual([]);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bun test src/commands/gitDiff.test.ts`
Expected: FAIL — `Cannot find module './gitDiff'`

- [ ] **Step 3: Write minimal implementation**

```typescript
// src/commands/gitDiff.ts
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { commandExists } from "../utils/commandExists";
import { textPrompt } from "../utils/prompt";
import { printError, printWarning, printHeader, printSuccess } from "../utils/print";

export function extractDiffFilenames(diffOutput: string): string[] {
  const names = new Set<string>();
  for (const line of diffOutput.split("\n")) {
    const onlyIn = line.match(/^Only in (.+): (.+)$/);
    if (onlyIn) {
      const dir = onlyIn[1]!.replace(/^\/tmp\/(base|target)\/?/, "");
      const file = onlyIn[2]!;
      names.add(dir ? `${dir}/${file}` : file);
      continue;
    }
    const diffLine = line.match(/^diff -r .*\/base\/(\S+) .*\/target\/\S+$/);
    if (diffLine) {
      names.add(diffLine[1]!);
    }
  }
  return [...names].sort();
}

export async function compareGitBranches(): Promise<void> {
  const inRepo = Bun.spawnSync(["git", "rev-parse", "--is-inside-work-tree"]);
  if (inRepo.exitCode !== 0) {
    printError("Error: Not in a git repository.");
    return;
  }

  if (!commandExists("colordiff")) {
    printError("Error: 'colordiff' command is missing.");
    printWarning("Please install it using: sudo apt-get update && sudo apt-get install -y colordiff");
    return;
  }

  const baseBranch = Bun.spawnSync(["git", "rev-parse", "--abbrev-ref", "HEAD"]).stdout.toString().trim();
  const targetBranch = await textPrompt("Enter the target branch name:", { defaultValue: "main" });

  const workDir = mkdtempSync(join(tmpdir(), "dev-helper-gitdiff-"));
  const baseDir = join(workDir, "base");
  const targetDir = join(workDir, "target");

  try {
    for (const [ref, dir] of [[baseBranch, baseDir], [targetBranch, targetDir]] as const) {
      const archive = Bun.spawnSync(["git", "archive", ref]);
      Bun.spawnSync(["mkdir", "-p", dir]);
      Bun.spawnSync(["tar", "-x", "-C", dir], { stdin: archive.stdout });
    }

    const diff = Bun.spawnSync(["diff", "-r", "-w", "-B", "-b", baseDir, targetDir]);
    const diffOutput = diff.stdout.toString();
    Bun.spawnSync(["colordiff"], { stdin: new Response(diffOutput).body!, stdout: "inherit" });

    const filenames = extractDiffFilenames(diffOutput);
    if (filenames.length > 0) {
      printHeader("Files that differ:");
      filenames.forEach((f) => console.log(f));
    } else {
      printWarning("No file differences found");
    }
    printHeader("Number of files in the diff:");
    printSuccess(String(filenames.length));
  } finally {
    rmSync(workDir, { recursive: true, force: true });
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bun test src/commands/gitDiff.test.ts`
Expected: PASS (3 tests)

- [ ] **Step 5: Commit**

```bash
git add src/commands/gitDiff.ts src/commands/gitDiff.test.ts
git commit -m "feat: port compare-git-branches-without-commit-history command"
```

---

### Task 19: `src/index.ts` — main menu, and retire `helper.sh`

**Files:**
- Create: `src/index.ts`
- Modify: `~/development/scripts/helper.sh` (delete)
- Modify: `~/development/scripts/tests/test_file_sync.bats` (delete)

**Interfaces:**
- Consumes: every `commands/*` module's public entry function (`searchTextInFiles`, `findFilesByName`, `showDiskUsage`, `showNetworkConnections`, `showSystemInfo`, `findPortUsage`, `compareGitBranches`, `setupFileSync`); `selectPrompt` from `./utils/prompt`; `printHeader` from `./utils/print`.

- [ ] **Step 1: Write `src/index.ts`**

```typescript
// src/index.ts
import { selectPrompt } from "./utils/prompt";
import { printHeader } from "./utils/print";
import { searchTextInFiles } from "./commands/searchText";
import { findFilesByName } from "./commands/findFiles";
import { showDiskUsage } from "./commands/diskUsage";
import { showNetworkConnections } from "./commands/network";
import { showSystemInfo } from "./commands/systemInfo";
import { findPortUsage } from "./commands/portUsage";
import { compareGitBranches } from "./commands/gitDiff";
import { setupFileSync } from "./commands/fileSync";

const menuActions = {
  searchText: { label: "Find a file with text in it", run: searchTextInFiles },
  findFiles: { label: "Find files by name", run: findFilesByName },
  diskUsage: { label: "Show disk usage", run: showDiskUsage },
  network: { label: "Show network connections", run: showNetworkConnections },
  systemInfo: { label: "Show system info", run: showSystemInfo },
  portUsage: { label: "Find port usage", run: findPortUsage },
  gitDiff: { label: "Compare git branches without commit history", run: compareGitBranches },
  fileSync: { label: "Set up file sync", run: setupFileSync },
} as const;

async function main(): Promise<void> {
  while (true) {
    printHeader("Development Helper Menu");
    const choice = await selectPrompt(
      "Choose an action (or Ctrl+C to exit):",
      Object.entries(menuActions).map(([value, { label }]) => ({ value, label })),
    );
    await menuActions[choice as keyof typeof menuActions].run();
  }
}

main();
```

- [ ] **Step 2: Run the full test suite**

Run: `bun test`
Expected: PASS (all tests from Tasks 2–3, 5–10, 12–13, 15–18)

- [ ] **Step 3: Smoke-test the menu loop via Docker**

Run: `./run.sh`
Expected: the interactive menu renders with all 8 items, arrow keys move the selection, Ctrl+C exits cleanly.

- [ ] **Step 4: Delete `helper.sh` and its bats tests**

```bash
cd ~/development/scripts
git rm helper.sh tests/test_file_sync.bats
```

- [ ] **Step 5: Commit both repos**

```bash
cd ~/development/scripts/projects/dev-helper
git add src/index.ts
git commit -m "feat: add main menu loop, dev-helper CLI is now complete"

cd ~/development/scripts
git commit -m "chore: retire helper.sh, replaced by dev-helper CLI

dev-helper (~/development/scripts/projects/dev-helper) now owns every menu item
this script had, plus instant inotify-based file sync and multi-select
dedup. See docs/superpowers/specs/2026-07-02-dev-helper-cli-rewrite-design.md."
```

---

## Self-Review Notes

- **Spec coverage:** Bun/Docker (Task 1), `utils` naming (throughout), `~/development/scripts/projects/dev-helper` path (Task 1), per-command file split (Tasks 12–18), fileSync split into config/addPairs/viewPairs/removePair/watcher/service (Tasks 5–10), inotify watcher + 5-minute fallback (Task 9), host-native systemd service (Task 10), `inotifywait` install-check (Task 9's `isInotifyToolsInstalled`/`INOTIFY_INSTALL_COMMAND`, wired into the error path in Task 11), multi-select dedup (Task 6's `filterUnsyncedItems`), full replacement of `helper.sh` (Task 19) — every design section maps to a task.
- **Type consistency verified:** `SyncPair` is defined once in `config.ts` (Task 5) and imported by name in every later fileSync task (6–11) without redefinition. `serviceControlArgs`/`installCommands` (Task 10) are consumed as-is by Task 11's `manageService`/`installService` calls — argument shapes match.
- **Legacy-timer migration:** Task 10's `installCommands()` explicitly disables the old `rsync-sync.timer` unit name from the 2026-06-26 design before enabling the new watcher, so upgrading an existing install doesn't leave two sync mechanisms running against the same `pairs.conf`.
