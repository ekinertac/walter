# Agent operating restrictions

These restrictions apply to all agent work in this repository, including operations performed through tools, scripts, subprocesses, APIs, or delegated agents. Do not bypass them through an alternative interface.

## No write-style Git operations

Use Git only for read-only inspection, such as `git status`, `git diff`, `git log`, and `git show`.

Do not perform Git operations that modify the working tree, index, repository metadata, refs, configuration, or remote state. This includes staging, committing, amending, switching or creating branches, checking out files, resetting, cleaning, stashing, merging, rebasing, cherry-picking, reverting, tagging, fetching, pulling, pushing, initializing repositories, and modifying Git configuration or worktrees. Do not modify Git internals directly or use another tool to perform these operations.

Ordinary source-file edits are allowed; this restriction prohibits write-style Git operations, not the coding task itself.

## No GitHub CLI

Do not invoke the `gh` CLI for any purpose, including read-only queries, authentication, or commands wrapped in scripts or aliases.

## No automated or headless processes

Do not start automated or headless processes, including background jobs, daemons, services, development servers, watchers, scheduled jobs, browser automation, headless browsers, automated test runners, or unattended workflows. Do not trigger these processes remotely or through another tool.

Compiling code is allowed. A compilation or build command must run in the foreground, terminate when complete, and must not start any prohibited process or publish artifacts as a side effect. Ordinary foreground inspection and editing commands are allowed.

## No publishing artifacts

Do not publish, upload, deploy, release, or otherwise distribute artifacts anywhere, whether publicly or privately. This includes package registries, container registries, release assets, hosting services, cloud storage, remote artifact stores, and local publishing destinations. Do not trigger a workflow or use another tool to publish on your behalf.

Creating local build outputs as part of an allowed compilation is permitted; publishing or distributing those outputs is not.

## Stop and ask

If a task requires any prohibited operation, or it is unclear whether a command would perform one, stop before executing it. Explain the required operation and why it is needed, then ask the user to perform it themselves or explicitly authorize a narrowly scoped exception. Do not treat the original task request, tool availability, or a suggested command as authorization. Continue only with work that does not require the prohibited operation while awaiting the user's response.
