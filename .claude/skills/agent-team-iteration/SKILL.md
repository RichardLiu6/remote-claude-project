---
name: agent-team-iteration
description: |
  Multi-version product iteration using parallel agent teams. Use when: (1) building
  a feature that needs multiple iterations (iOS app, input system, UI component),
  (2) user wants engineer + user + PM review cycle, (3) need to dispatch 3-person
  teams per version with feedback flowing into next version. Pattern: engineer builds
  on worktree/branch, user evaluates UX with scoring, PM does RICE analysis and
  roadmap. Each version's feedback injects into next version's engineer prompt.
author: Claude Code
version: 1.0.0
date: 2026-03-07
---

# Agent Team Iteration

## Problem
Complex features need multiple iterations with diverse perspectives (engineering,
user experience, product strategy) to converge on quality. Sequential single-agent
work misses cross-cutting concerns.

## Context / Trigger Conditions
- User says "iterate N versions" or "keep improving"
- Feature needs both implementation AND evaluation
- User mentions "customer", "PM", "product manager" roles
- Multi-version development on isolated branches

## Solution

### Team Composition (per version)
1. **Engineer agent** — implements features, writes tests, commits to branch
   - Use `isolation: "worktree"` for branch work
   - Mode: `bypassPermissions` for speed
2. **User agent** — scores 10 dimensions (1-10), writes review doc
   - Persona: opinionated daily user, specific scenarios
   - Output: `docs/{feature}-user-review-vN.md`
3. **PM agent** — RICE analysis, competitive research, roadmap
   - Includes WebSearch for competitor analysis
   - Output: `docs/{feature}-pm-assessment-vN.md`

### Dispatch Pattern
```
v(N) engineer completes
  → dispatch in parallel:
    - v(N) user review
    - v(N) PM assessment
    - v(N+1) engineer (prompt includes v(N) user + PM feedback summaries)
```

### Feedback Loop
Each engineer prompt MUST include:
- Previous version's user top-5 complaints
- Previous version's PM priority recommendations
- Specific items to address from reviews

### File Conflicts
- Engineer: works on feature branch/worktree (no conflict)
- User + PM: write to separate docs/ files (no conflict)
- Never dispatch two engineers on same branch simultaneously

## Verification
- Each version: xcodebuild/build passes
- User score trending upward across versions
- PM priorities shifting from P0→P1→P2 across versions

## Example
```
iOS App iteration:
  v1: scaffold → v2: core features → v3: bug fixes
  v4: polish → v5: advanced → v6: final

Each version: engineer + user(score) + PM(RICE)
Total: 18 agents across 6 versions
```

## Notes
- Run engineer in background, user+PM can start on previous version's code
- Maximum practical parallel agents: ~7 (context + rate limits)
- Always update second-brain TODO.md at milestones
