# CLAUDE.md

Operating rules for AI agents (and humans) working in this repository.
These rules are **mandatory**. When any rule conflicts with a request, stop and
ask the user (in Japanese) before proceeding.

## Language

- **All documentation and source code MUST be written in English.** This
  includes code, comments, commit messages, docs, and GitHub Issue/PR content.
- **All prompts to the user — questions, confirmations, "waiting for
  instruction" messages — MUST be written in Japanese (指示待ちは日本語).**

## 1. No Ticket, No Do

- **Do not perform any work without a tracking GitHub Issue.** Every change maps
  to an Issue.
- If a task has no Issue, stop and ask the user to create one (or ask for
  permission to create it) **before** touching code or docs.

## 2. Always plan first

- **Before starting any task, produce a Plan** and share it. No implementation
  begins before the Plan is agreed.
- The Plan must reference the Issue it addresses.

## 3. Never guess the spec

- **Guessing or inferring requirements is strictly forbidden.**
- When anything is ambiguous or underspecified, **STOP and ask the user**
  (in Japanese). Do not proceed on assumptions.

## 4. Documentation is updated before AND after

- **Before** starting work: update the relevant docs / Issue to reflect the
  intended change.
- **After** finishing work: update the docs / Issue again to reflect what was
  actually done.
- Documentation updates are not optional and are part of "done".

## 5. GitHub is external memory

- **Use GitHub Issues as the project's external memory.**
- Append progress notes, decisions, findings, and status to the relevant Issue
  **in English**, as work proceeds — not just at the end.
- Anyone (or any agent) should be able to reconstruct current state by reading
  the Issue thread.

## 6. Test-Driven Development is enforced

- **TDD is mandatory.** Write the failing test first, then the implementation,
  then refactor (red → green → refactor).
- **Coverage target: 90% or higher (recommended).** Do not let coverage regress.
- No feature is "done" without tests that were written test-first.

## 7. No stubs / mocks in real code

- **Stubs and mocks are forbidden in production (real) code.**
- Exception: a **preceding / foundational task** may temporarily require a stub —
  but this **must be avoided** whenever possible.
- If task ordering makes a stub unavoidable, **you MUST ask the user first**
  (in Japanese) before creating it. Never introduce a stub silently.
- (Mocks/stubs in *test* code are fine — this rule is about shipping code.)

## Definition of Done

A task is complete only when ALL of the following hold:

1. It was tracked by a GitHub Issue (Rule 1).
2. A Plan was made and agreed before starting (Rule 2).
3. No spec was guessed; open questions were asked and answered (Rule 3).
4. Docs were updated before and after the work (Rule 4).
5. Progress was recorded on the Issue in English (Rule 5).
6. Tests were written test-first and coverage is ≥ 90% (Rule 6).
7. No stubs/mocks exist in production code, or an explicitly approved exception
   is documented on the Issue (Rule 7).
8. All code and docs are in English (Language rule).
