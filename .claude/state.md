# Session State: scripts

**Last Updated**: 2026-02-23

---

## Critical Rules (synced from ~/.claude/CLAUDE.md)

1. **Push back FIRST**: Challenge bad ideas before helping.
2. **Personality (TOP PRIORITY)**: Be Cortana - snarky battle buddy, not corporate.
3. **Agent delegation (PROACTIVE)**: Delegate WITHOUT being asked. Fast=search/lint, Default=features, Strong=security.
4. **CLAUDE.md after compaction**: Re-read rules + personality.
5. **Plans & TODOs**: Multi-step plans → immediately write `.claude/todos.md`. Suggest /plan before non-trivial work.
6. **Speculation**: Default to novel approaches. Mark speculation clearly.
7. **Decision tracking**: NEW → append to Active Decisions (with WHY).

---

## Current Context (REPLACE each update)

**Goal**: Fix git-commit.sh hanging + add better debugging
**Immediate Task**: Kill zombie pinentry (PID 2949256), then add GPG health checks to script

**Root Cause Found**: `commit.gpgsign=true` in global git config. A previous Claude Code session did a commit, GPG asked for passphrase in non-interactive context, `pinentry` (PID 2949256) has been zombied since Feb 21. It blocks ALL subsequent GPG signing attempts, causing `git commit` to hang indefinitely.

**In Progress**:

- Kill zombie pinentry process
- Add GPG signing detection/debugging to git-commit.sh

**Recently Completed**:

- Identified root cause: zombie pinentry from Feb 21 blocking GPG signing
- Found hanging processes: pinentry PID 2949256, current commit script PID 3861820

---

## Environment & Commands (CRITICAL - often lost after compaction)

**Package Manager**: bun

**Key Files**:

- Script: `/home/patrick/development/scripts/git-commit.sh`
- `create_commit()` at line 1185 — where `git commit -F` runs (line 1218)
- `_validate_commit_message()` at line 1149
- `_commit_single_group()` at line ~1288

**GPG Config**:

- Global: `commit.gpgsign=true`, key `950C14E3AE98DDB5`
- Zombie pinentry PID: 2949256 (since Feb 21)

---

## Active Decisions (append with reasoning)

- [2026-02-23] **Add GPG health check to git-commit.sh**: Script should detect hung pinentry/gpg-agent issues before attempting commit, and provide clear error messages instead of silently hanging.

---

## Superseded/Archived

- (none yet)

---

## Remember for This Project

- git-commit.sh is standalone — calls Claude API directly, not Claude Code
- User's global git config has GPG signing enabled
- Script runs from any project directory via alias
