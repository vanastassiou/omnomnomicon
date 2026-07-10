---
title: "Sandboxing Claude Code for unattended runs"
date: 2026-07-09
excerpt: "How I configure Claude Code to run long jobs unattended: a Bash sandbox plus a permissions posture that keeps a compromised agent off the rest of the host."
---

I let Claude Code run jobs on this blog while I'm not watching: overnight recipe
validation, bulk front-matter fixes, that sort of thing. Leaving an agent
running unattended asks two things to be true at once. It should not stall
forever on a permission prompt, and a compromised or confused agent should not
be able to touch anything outside the job. This post is the setup I landed on,
written up as a runbook so I can reproduce it.

## Table of Contents
{:.no_toc}

* placeholder; replaced by the generated TOC at build time
{:toc}

## Goal

Configure Claude Code to allow long-running jobs to run unattended without
constant permission prompts, while maintaining a boundary between it and other
host resources (filesystem and network).

The setup here applies to Claude Code `2.1.205` on a Windows 11 host running
Ubuntu 24.04 in WSL2. Since the sandbox
[only isolates Bash subprocesses](https://code.claude.com/docs/en/sandboxing#scope)
and the `Read`, `Edit`, `Write`, `WebFetch`, and MCP tools run under the
permissions system, not the sandbox, both the Bash sandbox and tool use layers
need setup.

## Threat model

Sandboxing addresses
[two failure modes](https://code.claude.com/docs/en/sandboxing#security-limitations)
of a compromised agent that matter most when nobody is watching:

1. **Prompt injection:** a compromised agent modifies sensitive files like
   `~/.bashrc`, system binaries, its own settings
2. **Data exfiltration**: a compromised agent reads credentials (`~/.ssh`,
   `~/.aws/credentials`) and sends them to an attacker host.

[It's necessary to protect both the network and the filesystem](https://code.claude.com/docs/en/sandboxing#scope):

1. Network isolation prevents the agent from exfiltrating files it can read
2. Filesystem isolation prevents an agent from backdooring a resource to gain
   network access

## Layered security approach

| Layer                | What it controls                                               | Enforcement                             |
| :------------------- | :------------------------------------------------------------- | :-------------------------------------- |
| Sandbox (`/sandbox`) | What a Bash command can affect when it's run                   | Operating system (`bubblewrap` on WSL2) |
| Permission modes     | Whether a tool call runs and whether you are prompted          | Claude Code, before the call            |
| Permission rules     | Which tools and command patterns are allowed, denied, or gated | Claude Code, before the call            |

[The OS enforces the sandbox on the live process](https://code.claude.com/docs/en/sandboxing#permission-rules)
regardless of what the model chooses to run. Permission rules and modes decide
what launches in the first place.

## Prerequisites

| Component                     | Purpose                               | Why it's necessary                                                                                                                                                                                                                                                                                                                         |
| :---------------------------- | :------------------------------------ | :----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `bubblewrap` (`bwrap`)        | Filesystem isolation                  | The [unprivileged tool that enforces filesystem isolation](https://code.claude.com/docs/en/sandboxing#set-up-linux-and-wsl2) on Linux and WSL2; the sandbox's [OS-level enforcement](https://code.claude.com/docs/en/sandboxing#os-level-enforcement) is built on it, so without it nothing sandboxes.                                     |
| `ripgrep` (`rg`)              | Detects deny paths                    | Resolves the sandbox's deny-path rules; [bundled with the native Claude Code binary](https://code.claude.com/docs/en/sandboxing#set-up-linux-and-wsl2) and reported on the `/sandbox` Dependencies tab.                                                                                                                                    |
| `socat`                       | Network proxy relay                   | [Routes sandbox network traffic through the proxy](https://code.claude.com/docs/en/sandboxing#set-up-linux-and-wsl2) that enforces the [domain allowlist](https://code.claude.com/docs/en/sandboxing#network-isolation); without it, network isolation cannot start.                                                                       |
| seccomp filter                | Blocks Unix domain sockets (optional) | [Required to block Unix domain sockets](https://code.claude.com/docs/en/sandboxing#troubleshooting); [optional](https://code.claude.com/docs/en/sandboxing#set-up-linux-and-wsl2) because the sandbox runs without it, but then sandboxed commands can reach sockets such as `docker.sock`. Installed via `@anthropic-ai/sandbox-runtime`. |
| AppArmor `userns` restriction | Must be `0` or absent                 | On [Ubuntu 24.04 and later](https://code.claude.com/docs/en/sandboxing#set-up-linux-and-wsl2) the default AppArmor policy blocks `bwrap` from creating the user namespaces it needs; if `kernel.apparmor_restrict_unprivileged_userns` returns `1`, add a `bwrap` AppArmor profile. Absent on this host.                                   |
| WSL version                   | WSL2                                  | [bubblewrap requires kernel features only available in WSL2](https://code.claude.com/docs/en/sandboxing#os-level-enforcement); WSL1 and native Windows are unsupported.                                                                                                                                                                    |

## Procedure 1: install prerequisites

1. Install `socat` (Debian/Ubuntu family):

   ```bash
   sudo apt-get install socat
   ```

2. Install the seccomp helper for Unix domain socket blocking:

   ```bash
   npm install -g @anthropic-ai/sandbox-runtime
   ```

3. Restart Claude Code to run the dependency check

4. Verify all dependencies resolve:

   ```text
   /sandbox
   ```

   Expected: the
   [`/sandbox` panel](https://code.claude.com/docs/en/sandboxing#get-started)
   shows the `Mode`, `Overrides`, and `Config` tabs. If only a `Dependencies`
   tab appears, a package is still missing; the tab names which one.

## Procedure 2: enable the sandbox globally

Set the sandbox in user settings so it applies to every project.

1. In `~/.claude/settings.json`, add a `sandbox` block.

   ```json
   // Recommended lockdown posture for unattended runs
   {
     "sandbox": {
       "enabled": true, // Sandbox applied to all Bash commands
       "failIfUnavailable": true, // Blocks Claude startup if sandbox can't initialize
       "allowUnsandboxedCommands": false,
       "autoAllowBashIfSandboxed": true, // Runs sandboxed Bash without a permission prompt
       "network": {
         "allowedDomains": [
           "registry.npmjs.org",
           "rubygems.org",
           "*.rubygems.org",
           "*.github.com"
         ]
       },
       "credentials": {
         "files": [
           { "path": "~/.ssh", "mode": "deny" }, // Default read policy allows this, need explicit deny
           { "path": "~/.aws/credentials", "mode": "deny" } // Ditto
         ],
         "envVars": [
           // Unset before each sandboxed command runs
           { "name": "ANTHROPIC_API_KEY", "mode": "deny" },
           { "name": "GITHUB_TOKEN", "mode": "deny" },
           { "name": "NPM_TOKEN", "mode": "deny" }
         ]
       }
     }
   }
   ```

   - [`network.allowedDomains`](https://code.claude.com/docs/en/sandboxing#network-isolation):
     pre-allows the domains the jobs need so no network prompt appears mid-run.
     No domains are allowed by default. The list above covers npm, RubyGems
     (this is a Jekyll repo), and GitHub. Add only domains a job genuinely
     needs.
   - [`credentials`](https://code.claude.com/docs/en/sandboxing#protect-credentials):
     the default read policy still allows reading `~/.ssh` and
     `~/.aws/credentials`, so deny them explicitly. `envVars` deny entries are
     unset before each sandboxed command runs.

2. Save the file and restart Claude Code

### Balanced alternative

If strict mode blocks too much during initial rollout, allow commands that
cannot be sandboxed to
[fall back to a permission prompt](https://code.claude.com/docs/en/sandboxing#sandbox-modes):

```json
{
  "sandbox": {
    "enabled": true,
    "failIfUnavailable": false,
    "allowUnsandboxedCommands": true
  }
}
```

**Use this only while attended**. Unattended runs must use the strict
configuration outlined in the previous steps.

## Procedure 3: choose a permissions posture for unattended runs

The sandbox covers only Bash commands, so configure permission modes for the
other tools: file edits, `WebFetch`, MCP calls, and similar. Two options work
for unattended runs:

### Option A: auto mode plus sandbox auto-allow (balanced)

[Auto mode](https://code.claude.com/docs/en/permission-modes) routes each
non-Bash action through a safety classifier and auto-allows the rest. This plus
[sandbox auto-allow](https://code.claude.com/docs/en/sandboxing#sandbox-modes)
has Bash running without prompts inside the boundary while the classifier
reviews other tools.

Enable this mode with CLI flags:

```bash
claude --permission-mode auto -p "your task here"
```

The
[auto-mode classifier](https://code.claude.com/docs/en/permission-modes#eliminate-prompts-with-auto-mode)
judges each non-Bash action against three built-in rule lists: an `allow` list,
a `soft_deny` list (destructive or irreversible actions that a task's stated
intent can still clear), and a `hard_deny` list (security boundaries that intent
never clears). Tightening the classifier means overriding those lists in
`~/.claude/settings.json` so fewer actions slip through unreviewed while a job
runs unattended:

```json
{
  "autoMode": {
    "classifyAllShell": true, // Route every Bash command through the classifier, not just arbitrary-code patterns
    "soft_deny": ["$defaults"] // Keep the built-in soft-deny rules; append your own entries alongside
  }
}
```

- [`classifyAllShell`](https://code.claude.com/docs/en/settings): by default the
  classifier inspects only Bash commands matching arbitrary-code patterns, and
  your `permissions.allow` Bash rules auto-run untouched. Setting it to `true`
  suspends those allow rules and sends every shell command through the
  classifier: higher safety, at the cost of more classifier calls.
- [`soft_deny`](https://code.claude.com/docs/en/settings), and its siblings
  `allow` and `hard_deny`, are each lists you extend. The literal `"$defaults"`
  inherits Claude Code's built-in rules at that position, so
  `["$defaults", "your rule"]` adds to the defaults instead of replacing them.
  Put actions a task's intent may justify (for example a destructive command) in
  `soft_deny`, and lines intent must never cross in `hard_deny`.

### Option B: dontAsk plus sandbox (locked-down, CI-grade)

[`dontAsk` mode](https://code.claude.com/docs/en/permission-modes) runs only
pre-approved tools and denies everything else outright, with no prompt to hang
on. This is the strongest fit for a job that must never wait for input. It
requires an explicit allowlist.

1. Define the allowlist in the project's `.claude/settings.json`:

   ```json
   {
     "permissions": {
       "allow": [
         "Bash(bundle exec *)",
         "Bash(bundle install *)",
         "Bash(git add *)",
         "Bash(git commit *)",
         "Read(**)",
         "Edit(**)"
       ],
       "deny": [
         "Bash(curl *)",
         "Bash(wget *)",
         "Read(./.env)",
         "Read(./.env.*)",
         "Read(./**/secrets/**)"
       ]
     }
   }
   ```

2. Launch:

   ```bash
   claude --permission-mode dontAsk -p "your task here"
   ```

Anything outside the allowlist is denied and logged, and the run continues.
Review the transcript afterward for denied actions that a legitimate job needed,
then widen the allowlist deliberately.

### Never use `bypassPermissions` or `--dangerously-skip-permissions` outside a container

[`bypassPermissions` and `--dangerously-skip-permissions`](https://code.claude.com/docs/en/permission-modes)
skip permission checks and protected-path checks entirely. This host runs Claude
Code directly in your WSL2 user session, not wrapped in a container, so they are
the wrong tool here whether or not the Bash sandbox from Procedure 2 is enabled:

- The flag is
  [blocked when running as root](https://code.claude.com/docs/en/sandboxing#troubleshooting)
  or via `sudo` on Linux, because root plus no permission prompts can modify any
  file or service on the system, leaving no blast-radius limit at all. The check
  is skipped only inside a recognized sandbox, meaning a container or VM that
  wraps the whole Claude Code process (Procedure 6). The Bash sandbox from
  Procedure 2 does not count here: it isolates Bash subprocesses, not the Claude
  Code process, so it neither lifts this block nor contains the other tools the
  flag would unleash.
- Reserve it for a disposable container or VM where the blast radius is the
  container itself. See Procedure 6

## Procedure 4: prevent silent hangs on questions

If a job triggers `AskUserQuestion` with nobody present, it waits forever by
default. Set an [idle timeout](https://code.claude.com/docs/en/settings) so the
run auto-continues instead of stalling. Requires Claude Code `2.1.200` or later;
this host runs `2.1.205`.

1. Open `~/.claude/settings.json`.
2. Set the timeout:

   ```json
   { "askUserQuestionTimeout": "5m" }
   ```

   Accepts `"60s"`, `"5m"`, `"10m"`, or `"never"` (the default).

## Procedure 5: notify and monitor

Two [hooks](https://code.claude.com/docs/en/hooks) cover both moments you care
about while away: `Notification` fires when Claude needs input or permission,
and `Stop` fires when a run finishes. Add them to `~/.claude/settings.json`
under a `hooks` key (as a sibling of existing keys):

```json
{
  "hooks": {
    "Notification": [
      // Fires when Claude needs input or permission — the "needs attention" signal
      {
        "matcher": "", // Empty matcher = every notification
        "hooks": [
          {
            "type": "command",
            // .message is the notification text from the hook's stdin JSON; || true so a notify failure never disrupts the run
            "command": "msg=$(jq -r '.message // \"Claude Code needs attention\"'); notify-send \"Claude Code\" \"$msg\" || true"
          }
        ]
      }
    ],
    "Stop": [
      // Fires when Claude finishes a turn — the "run finished" signal
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "notify-send \"Claude Code\" \"Run finished\" || true"
          }
        ]
      }
    ]
  }
}
```

This host has WSLg (`DISPLAY=:0`, `/mnt/wslg` present), so `notify-send` routes
to the Windows notification tray from the unsandboxed hook context. One gotcha:
running `notify-send` from a _sandboxed_ Bash command returns
`Unable to create socket: Operation not permitted`, because
[the sandbox blocks the Unix socket WSL uses to reach Windows](https://code.claude.com/docs/en/sandboxing#set-up-linux-and-wsl2).
Hooks run outside the sandbox, so they are unaffected. To reach a phone or
another machine instead, swap the command for an `ntfy` or webhook `curl` (which
must run outside the sandbox or target an allowed domain).

## Procedure 6: full-process isolation for the highest-risk jobs

The built-in sandbox isolates Bash subprocesses, not the Claude Code process
itself. For a job that must run with `--dangerously-skip-permissions`,
[wrap the entire process instead](https://code.claude.com/docs/en/sandbox-environments).
Two options:

1. [Dev container](https://code.claude.com/docs/en/devcontainer): run Claude
   Code as a non-root user inside a container. `--dangerously-skip-permissions`
   is permitted there because the container is the boundary.
2. `@anthropic-ai/sandbox-runtime` (`srt`): installed in Procedure 1. It wraps
   an arbitrary command in the same `bubblewrap` primitives. Configure
   `~/.srt-settings.json`, then run `srt <command>`.

Use these when the task is untrusted or the allowlist cannot be enumerated in
advance.

## Verification

Run these after Procedures 1 and 2. Each has an expected result.

1. Confirm dependencies resolve:

   ```text
   /sandbox
   ```

   Expected: `Mode`, `Overrides`, and `Config` tabs appear, not a lone
   `Dependencies` tab.

2. Confirm
   [filesystem isolation](https://code.claude.com/docs/en/sandboxing#filesystem-isolation)
   blocks writes outside the working directory. Ask Claude to run:

   ```bash
   touch ~/sandbox-escape-test
   ```

   Expected: the command fails inside the sandbox, and `~/sandbox-escape-test`
   does not exist. Verify with `ls ~/sandbox-escape-test`, which should report
   `No such file or directory`.

3. Confirm credential reads are denied. Ask Claude to run:

   ```bash
   cat ~/.ssh/id_ed25519
   ```

   Expected: permission denied inside the sandbox. If no such key exists,
   substitute any file under `~/.ssh`.

4. Confirm
   [network isolation](https://code.claude.com/docs/en/sandboxing#network-isolation)
   blocks non-allowed domains. Ask Claude to run:

   ```bash
   curl -sSf https://example.com
   ```

   Expected: the request is blocked or prompts, because `example.com` is not in
   `allowedDomains`. A domain from the allowlist, such as
   `https://registry.npmjs.org`, should succeed.

5. Confirm strict mode gives no silent escape. With `allowUnsandboxedCommands`
   set to `false`, ask Claude to run a command that cannot be sandboxed and
   confirm it fails rather than running outside the boundary.

## Rollback

1. Open `~/.claude/settings.json`.
2. Set `sandbox.enabled` to `false`, or remove the `sandbox` block.
3. Restart Claude Code.
4. Verify: `/sandbox` reports the sandbox is disabled, and a write outside the
   working directory now succeeds.

## Settings reference

Keys used in this runbook, all in
[`settings.json`](https://code.claude.com/docs/en/settings#sandbox-settings):

| Key                                         | Type    | Effect                                                       |
| :------------------------------------------ | :------ | :----------------------------------------------------------- |
| `sandbox.enabled`                           | boolean | Turns the Bash sandbox on                                    |
| `sandbox.autoAllowBashIfSandboxed`          | boolean | Runs sandboxed Bash without a permission prompt              |
| `sandbox.failIfUnavailable`                 | boolean | Blocks startup if the sandbox cannot initialize              |
| `sandbox.allowUnsandboxedCommands`          | boolean | `false` ignores the `dangerouslyDisableSandbox` escape hatch |
| `sandbox.filesystem.allowWrite`             | array   | Extra paths sandboxed commands may write                     |
| `sandbox.filesystem.denyRead` / `denyWrite` | array   | Paths blocked inside the sandbox                             |
| `sandbox.filesystem.allowRead`              | array   | Re-allows reads within a `denyRead` region                   |
| `sandbox.network.allowedDomains`            | array   | Domains Bash may reach; empty by default                     |
| `sandbox.network.deniedDomains`             | array   | Domains blocked even under a broader allow wildcard          |
| `sandbox.credentials.files`                 | array   | File paths denied for reads (`"mode": "deny"`)               |
| `sandbox.credentials.envVars`               | array   | Environment variables to `deny` (unset) or `mask`            |
| `sandbox.excludedCommands`                  | array   | Commands that run outside the sandbox                        |
| `permissions.allow` / `deny` / `ask`        | array   | Tool and command rules evaluated before a call               |
| `autoMode.classifyAllShell`                 | boolean | Routes all Bash through the auto-mode classifier             |
| `askUserQuestionTimeout`                    | string  | Idle time before `AskUserQuestion` auto-continues            |
| `hooks.Notification` / `hooks.Stop`         | array   | Run a command when Claude needs input or a run finishes      |

[Path prefixes](https://code.claude.com/docs/en/sandboxing#configure-sandboxing)
for `sandbox.filesystem.*` and `sandbox.credentials.files`: `/` is absolute,
`~/` is home-relative, and `./` or no prefix is relative to the project root for
project settings or to `~/.claude` for user settings.

## Known limitations

- Network filtering
  [does not inspect TLS by default](https://code.claude.com/docs/en/sandboxing#security-limitations),
  so a broad domain such as `*.github.com` can create an exfiltration path via
  domain fronting. Keep `allowedDomains` narrow.
- Allowing a Unix socket such as `/var/run/docker.sock`
  [grants host access and defeats the sandbox](https://code.claude.com/docs/en/sandboxing#security-limitations).
  Do not add it.
- On WSL2, sandboxed commands
  [cannot launch Windows binaries under `/mnt/c/`](https://code.claude.com/docs/en/sandboxing#set-up-linux-and-wsl2)
  (for example `cmd.exe`), because WSL relays those over a Unix socket the
  sandbox blocks. Add such commands to `sandbox.excludedCommands` if a job needs
  them.
- The sandbox
  [denies writes to Claude Code's own `settings.json`](https://code.claude.com/docs/en/sandboxing#security-limitations)
  at every scope, so a sandboxed command cannot rewrite its own policy.
- [`docker` and `watchman`-backed tools](https://code.claude.com/docs/en/sandboxing#troubleshooting)
  (for example `jest`) are incompatible with the sandbox. Run
  `jest --no-watchman`, and add `docker *` to `excludedCommands` if needed.

## Gaps

The controls here are host-level containment. The areas below are out of scope;
close them separately if your risk tolerance requires it.

- **No audit trail.** This setup records nothing about what an unattended run
  did: the notification hooks are ephemeral desktop alerts, not a log. The
  [NIST AI RMF](https://www.nist.gov/itl/ai-risk-management-framework) Measure
  function and the
  [CISA and NSA deployment guidance](https://www.cisa.gov/news-events/alerts/2024/04/15/joint-guidance-deploying-ai-systems-securely)
  call for continuous monitoring. Close it with a `PreToolUse` or `PostToolUse`
  logging hook, or an OpenTelemetry export.
- **No supply-chain controls.** Nothing vets the npm packages, Ruby gems, or MCP
  servers an unattended job pulls in, and a poisoned MCP tool runs under the
  permission system rather than the sandbox. This is
  [OWASP LLM03 Supply Chain](https://genai.owasp.org/llm-top-10/). Close it by
  pinning and lock-filing dependencies and by restricting MCP servers with
  `enabledMcpjsonServers` or `allowedMcpServers`.
- **Rollback is not incident response.** The Rollback section only disables the
  sandbox; it does not cover detecting or recovering from a run that already
  exfiltrated data or tampered with a resource. The
  [CISA and UK NCSC secure-operation guidance](https://www.ncsc.gov.uk/collection/guidelines-secure-ai-system-development)
  expects a response plan: credential rotation, blast-radius review, and
  restoring from a known-good checkpoint.
- **No patch cadence.** Nothing here keeps Claude Code,
  `@anthropic-ai/sandbox-runtime`, `socat`, or `bubblewrap` current, yet the
  sandbox's guarantees depend on them. Track updates as part of secure
  operation; managed fleets can pin a floor with `requiredMinimumVersion`.
- **Credential coverage is a hand-picked list.** Only `~/.ssh`,
  `~/.aws/credentials`, and the three environment variables named in Procedure 2
  are denied, which leaves other secrets readable
  ([OWASP LLM02](https://genai.owasp.org/llm-top-10/)). Broaden it with more
  `credentials.files` or `denyRead` entries, or set
  `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB`.

## Sources

Assertions throughout this post link inline to their source. The primary
references are:

- [Configure the sandboxed Bash tool](https://code.claude.com/docs/en/sandboxing)
- [Settings reference](https://code.claude.com/docs/en/settings)
- [Permission modes](https://code.claude.com/docs/en/permission-modes)
- [Automate actions with hooks](https://code.claude.com/docs/en/hooks)
- [Sandbox environments](https://code.claude.com/docs/en/sandbox-environments)

## Additional reading

These sources place the choices here in the broader security landscape. Each
note records which of the source's principles this setup already applies.

### AI and agent security frameworks

- [OWASP Top 10 for LLM Applications (2025)](https://genai.owasp.org/llm-top-10/):
  the Threat model targets LLM01 Prompt Injection and LLM06 Excessive Agency;
  the credential denies and `.env`/secrets deny rules address LLM02 Sensitive
  Information Disclosure.
- [OWASP Top 10 for Agentic Applications (2026)](https://genai.owasp.org/resource/owasp-top-10-for-agentic-applications-for-2026/):
  least-privilege tool allowlists, human oversight through the notification
  hooks, and refusing a blanket permission bypass follow its agent-autonomy
  controls.
- [MITRE ATLAS](https://atlas.mitre.org/): the `allowedDomains` egress control
  counters exfiltration techniques, and the credential denies counter
  credential-access techniques.
- [NIST AI Risk Management Framework](https://www.nist.gov/itl/ai-risk-management-framework)
  and its
  [Generative AI Profile (NIST AI 600-1)](https://nvlpubs.nist.gov/nistpubs/ai/NIST.AI.600-1.pdf):
  the setup walks the Map (Threat model), Manage (Procedures, Rollback), and
  Measure (Verification) functions for the Information Security risk category.
- [CISA and UK NCSC, Guidelines for Secure AI System Development](https://www.ncsc.gov.uk/collection/guidelines-secure-ai-system-development)
  and the
  [CISA and NSA Joint Guidance on Deploying AI Systems Securely](https://www.cisa.gov/news-events/alerts/2024/04/15/joint-guidance-deploying-ai-systems-securely):
  the fail-closed defaults, layered enforcement, and monitoring hooks apply
  their secure-by-default and secure-operation principles.

### Anthropic first-party guidance

- [Claude Code security](https://code.claude.com/docs/en/security): the security
  overview this setup operationalizes.
- [Making Claude Code more secure and autonomous with sandboxing](https://www.anthropic.com/engineering/claude-code-sandboxing):
  the rationale for isolating both filesystem and network, which Procedure 2
  applies.
- [How we contain Claude across products](https://www.anthropic.com/engineering/how-we-contain-claude):
  containment through sandboxes, VMs, and egress controls, mirrored in the
  layered approach and Procedure 6.
- [Our framework for developing safe and trustworthy agents](https://www.anthropic.com/news/our-framework-for-developing-safe-and-trustworthy-agents):
  the human-control and security principles behind the notification hooks and
  permission gating.
- [Securely deploying AI agents (Agent SDK)](https://platform.claude.com/docs/en/agent-sdk/secure-deployment):
  deployment-side controls for the same posture.
- [Model Context Protocol specification](https://modelcontextprotocol.io/specification/2025-11-25):
  MCP tools run under the permission system, not the sandbox (see Goal); the
  spec's OAuth 2.1 model governs remote MCP servers.

### Operating-system and container isolation

- [NIST SP 800-190, Application Container Security Guide](https://csrc.nist.gov/pubs/sp/800/190/final):
  the run-as-non-root, container-as-boundary model behind Procedure 6's dev
  container.
- [bubblewrap](https://github.com/containers/bubblewrap) and the Linux
  `seccomp`, user-namespace, and AppArmor primitives it builds on: the
  enforcement mechanism named in Prerequisites.
- [gVisor](https://gvisor.dev/) and
  [Firecracker](https://firecracker-microvm.github.io/): kernel-level and
  VM-level isolation for the highest-risk jobs, a stronger extension of
  Procedure 6.
