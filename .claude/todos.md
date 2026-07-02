# Todos: scripts

## Current Goal

Fix git-commit.sh hanging on GPG signing + add debugging to prevent future hangs

## Active Phases

### Phase 1: Unblock Current Hang ⏳

- **Agent**: Self
- **Tasks**:
  - [ ] Kill zombie pinentry (PID 2949256) to unblock GPG agent
  - [ ] Verify GPG signing works after cleanup

### Phase 2: Add GPG Health Checks to git-commit.sh ⏳

- **Agent**: Self
- **Tasks**:
  - [ ] Add pre-commit GPG signing check to `create_commit()`
  - [ ] Add timeout wrapper around `git commit` to prevent infinite hangs
  - [ ] Add debug logging for commit creation flow
  - [ ] Test the improved error handling

## Future (Not Yet Planned)

- General debugging improvements to other parts of the script

## Completed

- [2026-02-23] Root cause analysis - zombie pinentry from Feb 21 blocking GPG
