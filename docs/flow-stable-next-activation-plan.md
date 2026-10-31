# Flow stable and next declaration activation plan

## Gate

This change prepares declarations only. It does not activate, stop, restart,
rebind, migrate, or configure a running Nexus. Activation waits for Psyche's
explicit go after this plan and the immutable build receipts are reviewed.

## Declared services

The stable slot declares:

- `flow-nexus-04012.service`, Flow `f3c59c4b15bb208ec4455f208d7ba0b103c65cd5`
  (`0.40.12`), ordinary socket `%t/flow/flow.sock`, meta socket
  `%t/flow/flow-meta.sock`, and Memory
  `%h/.local/state/flow-040/flow.sema`;
- its required `curriculum-nexus-040.service`, Curriculum
  `b112a87174d33efae2f3b29871478bd188e87f36`, with
  `XDG_RUNTIME_DIR=%t/flow40-rt`, hence socket
  `%t/flow40-rt/curriculum/curriculum.sock`;
- the existing context roots under
  `%h/.local/state/curriculum-context`, the existing three HTTPS origins,
  records under `%h/primary/flows`, and the authored `roles.datom` projected by
  Home at `%h/.local/state/curriculum-040/roles.datom`.

The independent next slot declares `flow-nexus-next-0420.service`, Flow
`806511305246f968d9164b4fd77bed46a7eef1ab` (`0.42.0`), ordinary and meta
sockets under `%t/flow-042-next`, and its own Memory at
`%h/.local/state/flow-042-next/flow.sema`. It has no declared paired Nexus.

`lib/stable-next-service.nix` carries the slot data as
`{ unitName, package, ordinarySocket, metaSocket, memory,
pairedNexusEndpoints }`. The Flow module alone projects those values into the
binary's existing one-argument typed Start datom. It runs no configuration
initializer against either existing Memory.

## Source and build evidence

The running stable Flow output is
`/nix/store/f57pwba7slywj0294rha3qqxg0xxym5x-flow-0.40.12`, derived by
`/nix/store/9yi75jpdb0hbmww0syg53jnla7l9q5qh-flow-0.40.12.drv` from
`/nix/store/kz1hknp7nik2iqyk1gjikg5kswypx529-source`. The declared stable
package evaluates to that same output.
Its output NAR is
`sha256-sxhV37vRY6dIIajiZfq1sMA15joq2L1s7cYrz2YQjzE=` (size `22096104`),
and the locked source NAR for `f3c59c4` is
`sha256-SnWtOoacILCR2WRvkukZ58l9Ipiib3ROuITBjLK1Zks=`.

The running paired Curriculum output is
`/nix/store/839vymlb5xj6ijd4yz3xdhq6w1dq4ymc-curriculum-0.1.0`, derived by
`/nix/store/xpi5sdxahfk5p0hvfgjzz9a8bivm5gvy-curriculum-0.1.0.drv` from
`/nix/store/jfjwc5v5lybvikg6qnxfc5fp32pp3r0m-source`. The declared Curriculum
package evaluates to that same output.
Its output NAR is
`sha256-WQ+2wpn13swd7xVJhoHGKf56jbD+tTaYlw0YC3aRa0s=` (size `3265984`),
and the locked source NAR for `b112a87` is
`sha256-EBh0FvolYjgKpJgj7yK+5QzTBQUZAhQTvlasvsUFq30=`.

The running next output is
`/nix/store/662bs0yrwhkxv09nr9plp11bimhm7a6q-flow-0.42.0`; its reported
former deriver was
`/nix/store/gs0qxa5gyjpkn61chzw54f1qqdfx4vcd-flow-0.42.0.drv`, which is no
longer present. Evaluation of the pinned `8065113` flake currently yields
`/nix/store/7ykm10kq3ya3szdsf10zsml2jcw57r5f-flow-0.42.0.drv` from
`/nix/store/s1dgq9yld3mrd5vykvg3cd028fj0b4aj-source`, output
`/nix/store/7l3nypk6v0n7dqwp2v0q0gijmvnnag2v-flow-0.42.0`. Prometheus built it
through `ssh-ng://nix-ssh@prometheus.goldragon.criome`; its workspace tests
reported 554 Nexus tests passed, 6 witness-dependent tests ignored, and every
other crate/test passed. The focused declaration check
`/nix/store/3gqwvkdlv1pawx8r20rnc9adjc604rcf-flow-service-path.drv` also ran
on Prometheus and produced
`/nix/store/bjb32lh0qg7vvhpxjsmfkz5213kl4q83-flow-service-path`, reading
`flow-nexus 0.40.12` and `flow-nexus 0.42.0`.

The two next output paths differ, but `nix path-info` reports the same NAR hash
`sha256-C9HgnR/atFZ5l/8cDBkFGqIssttO3ZAlSH4u8ztQHKk=` and the same NAR size
`22614832` for both. Their serialized output contents are therefore identical.
The missing former deriver means the derivation-level reason for the differing
store names remains unknown; source revision and version alone were not used as
a substitute for the NAR witness. The new output needs a declared root before
any collector can run.
The locked source NAR for `8065113` is
`sha256-fYT5MLmoOgww/zJPAYWfKR3GXWeDdlpwa5W7q6VCfhw=`.

The build used `--max-jobs 0 --option fallback false`; the log explicitly says
both the Flow derivation and focused check were built on
`ssh-ng://nix-ssh@prometheus.goldragon.criome`. Standalone evaluation used a
fixture flake whose entire output is `system = "x86_64-linux"`; its path hash
was `sha256-KW3DUTifDJ6m2JuYiTVtJz+9ieAgqjCb46wgrMqxJJU=`. This selects the
same platform but is not the full lojix-materialized Home consumer.

The Curriculum contract check
`/nix/store/dxv7k81m6jag6h84niq1nx1wcjr6jkjr-curriculum-resolver-contract.drv`
also built on Prometheus and produced
`/nix/store/sjjcyr72swlk8zxpyaixlplin8ki4zf0-curriculum-resolver-contract`.
It starts the exact
`/nix/store/839vymlb5xj6ijd4yz3xdhq6w1dq4ymc-curriculum-0.1.0` package against offline Git fixtures,
then witnesses typed startup and role composition plus the retired-path and
placement refusals. The fixtures exercise the contract without network access;
they do not stand for the live context repositories.

A whole Home generation has not been built: the repository intentionally has
no users under its stub Horizon input, and the active lojix-materialized
Horizon/system/deployment inputs were not supplied to this hand. Consequently
no complete activation script has yet been inspected. This is a gate, not a
claim that the focused checks cover activation.

## Expected activation effects

The current units are transient units under
`/run/user/1001/systemd/transient`, which precedes the Home unit directory in
the observed user unit search path. Linking Home files and running
`daemon-reload` alone therefore does not replace the loaded definitions.
Activation must use the complete built Home generation and then deliberately
converge each target unit, verifying that `FragmentPath` names the declared
unit before start.

Convergence may replace the three main PIDs. It must not promise PID
preservation. The stable socket names and stable Memory remain byte-for-byte
at their existing paths. The next socket names and next Memory likewise stay
at their existing paths. Existing Flow IDs, addresses, history, queues,
counters, profiles, native bindings, and durable admitted messages remain in
the stable Memory; the 31 existing seats and their panes are not recreated.
Clients may briefly disconnect while the stable listener changes process.

Restarting the paired Curriculum can temporarily refuse composition, launch,
or refresh while its socket is absent. It does not stop already running seats.
The next slot can be converged independently because it owns distinct sockets
and Memory.

Home also replaces the current Curriculum roles file at its existing state
path with a declarative symlink to the `b112a87` authored registry. The complete
generation review must confirm this is the intended content before activation.

## Message boundary

Flow handles SIGTERM/SIGINT by stopping acceptance, joining accepted
connections, and closing Memory cleanly. There is no separate pre-stop drain
interface. A request proved unadmitted may be retried according to its typed
operation. A request whose admission is ambiguous is not resent until its
same durable request ID and outcome are reconciled; otherwise a resend could
duplicate an effect. Launch uses its durable `LaunchRequestId`; tool sends use
the same call key and content.

## Ordered activation after the gate

1. Build the complete lojix-materialized Home generation remotely and inspect
   its activation script and unit files.
2. Preserve a declared, rooted rollback generation containing the exact
   current packages and service data. A failed or older Home generation is not
   accepted as rollback evidence.
3. Stop acceptance and converge `curriculum-nexus-040.service`; verify its
   declared `FragmentPath`, exact executable, environment, and socket.
4. Converge `flow-nexus-04012.service`; verify its declared `FragmentPath`,
   exact Start datom, executable, two listeners, unchanged Memory path, and
   current typed Configuration readback. Do not run Configure merely because
   the process restarted.
5. Converge `flow-nexus-next-0420.service` independently and verify its exact
   Start datom, executable, listeners, and unchanged next Memory path.
6. Verify all former stable seats and bindings remain, and reconcile every
   operation that crossed a listener transition by durable ID before any
   retry.

Rollback uses only the prebuilt declared rollback generation. It repeats the
same controlled convergence in reverse and verifies the old declared unit
fragments, exact executables, sockets, Memories, and typed configuration. It
never recreates transient units by hand.
