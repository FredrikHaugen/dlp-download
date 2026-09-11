# Harbor Agent Context

This directory holds repository-specific working context. Start at [AGENTS.md](../AGENTS.md), then read [PROJECT.md](PROJECT.md) and the guides relevant to the current task. Use [STATUS.md](STATUS.md) when assessing readiness or picking up unfinished work.

## Find the Right Guide

| Task | Read |
| --- | --- |
| Understand scope and user-visible defaults | [Project](PROJECT.md) |
| Change coordination, routing, engines, or persistence | [Architecture](ARCHITECTURE.md), [decisions](DECISIONS.md) |
| Build, edit, or prepare a PR | [Workflow](WORKFLOW.md) |
| Choose checks or investigate failures | [Testing](TESTING.md), [Harbor validation skill](../.agents/skills/harbor-validate/SKILL.md) |
| Change a screen or interaction | [UI](UI.md) |
| Touch browser access, subprocesses, files, or updates | [Security](SECURITY.md) |
| Update bundled dependencies or prepare release artifacts | [Engine maintenance skill](../.agents/skills/harbor-engine-maintenance/SKILL.md), [release procedures](../docs/RELEASING.md) |
| Assess remaining work and evidence | [Status](STATUS.md), [validation record](../docs/VALIDATION.md) |

## Discovery

Root `AGENTS.md` is the contributor entry point. These Markdown guides are linked references; placing them in `.codex` does not make every file load automatically. Repository skills live in `.agents/skills`, where Codex discovers their names and descriptions and loads matching instructions as needed. They can also be invoked as `$harbor-validate` and `$harbor-engine-maintenance`. See the official [AGENTS.md guidance](https://learn.chatgpt.com/docs/agent-configuration/agents-md) and [skill documentation](https://learn.chatgpt.com/docs/build-skills).

## Keep Context Current

Update the relevant guide alongside changes to commands, architecture, or accepted product behavior. Keep detailed release procedures in `docs/RELEASING.md` and dated test evidence in `docs/VALIDATION.md`; link to those records instead of copying changing counts or dependency versions. Record decision changes with a date and rationale. Distinguish observed implementation, verified behavior, and future work.

Use relative links and check them after moves. Current source and configuration determine implementation facts; reconcile stale documentation explicitly. These files do not change Codex settings or grant permission for external actions.
