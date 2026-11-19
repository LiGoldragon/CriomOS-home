# Owned read session

`playwright-chrome read-session` takes one JSON object on standard input:
`readCode` is the reader's fixed, internally generated Playwright function;
`limits` contains positive integer `navigation_ms`, `action_ms`, `command_ms`,
`cleanup_ms` and `output_bytes`. The reader's public request remains Datom;
this JSON boundary is between the two packaged components.

The terminal JSON is `{ "result": "<serialized read return>" }`, or
`{ "isError": true, "phase": "<phase>" }`. Phases are `SessionAttach`,
`SessionRun`, `SessionCleanup`, `ArtifactSetup`, `ArtifactCleanup` and
`Interrupted`. Native diagnostics, snapshots and daemon identities remain
inside the wrapper. The private guarded CLI lives in `libexec`; the public
wrapper accepts the owned session capability rather than bare attach,
run-code or detach invocations.

The wrapper creates a private artifact tree and transient user scope. A
worker reports its cgroup before it receives permission to acquire a token
or invoke the CLI. The controller opens that exact scope's cgroup-events
file before granting execution. During this startup phase only the launcher
and an ungranted worker exist, in the launcher's process group.

The worker uses the reviewed token guard and private CLI configuration,
daemon directory, output directory and temporary root. Inherited Playwright
configuration and Node injection variables are removed. A supplied nonempty
token bypasses GoPass, an explicitly empty token refuses, and an unset token
requires successful nonempty configured GoPass output. The reader's fixed
function retains the connected owned-Page close/isClosed obligation.

On any terminal worker outcome the controller stops the scope, observes
launcher exit and cgroup emptiness, then removes its artifact tree before
replying. Detached daemon descendants remain members of the scope. A cleanup
deadline is a grace limit, not proof of exit: if it elapses the wrapper
retains custody, waits for completion events and returns SessionCleanup
only after the owned scope is empty. RuntimeMaxSec also bounds the scope's
normal lifetime if its controller disappears. Abrupt external termination
of the controller cannot promise execution of Python artifact cleanup.

Synthetic fixtures model the manager and cgroup-events source; they run real
fixture processes, including a setsid daemon, and require them gone before
a terminal reply. They establish protocol and ordering, not an independently
executed real user-manager/cgroup integration. No browser, account or real
credential is used by those fixtures.
