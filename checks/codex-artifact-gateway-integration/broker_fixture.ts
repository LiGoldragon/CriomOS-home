import { join } from "node:path";

const [sourceRoot, socketPath] = process.argv.slice(2);
if (!sourceRoot || !socketPath) throw new Error("usage: broker_fixture.ts SOURCE_ROOT SOCKET_PATH");

const capabilityHistory = await import(
  join(sourceRoot, "packages/capability-history/index.ts")
);
const bytes = new TextEncoder().encode("synthetic broker artifact");
const broker = new capabilityHistory.CapabilityHistoryBroker({
  source: {
    async read(id: string) {
      return id === "artifact-1"
        ? {
            bytes,
            revision: "r1",
            digest: "sha256:synthetic",
            observedAt: "2026-09-09T12:00:00.000Z",
          }
        : null;
    },
  },
  now: () => new Date("2026-09-09T12:00:00.000Z"),
  randomBytes: () => new Uint8Array(32).fill(7),
});
broker.registerFlow({ id: "flow", createdAt: "2026-09-09T12:00:00.000Z" });
broker.registerArtifact({
  id: "artifact-1",
  flowId: "flow",
  kind: "transcript",
  contentType: "text/plain",
  expectedRevision: "r1",
});
const token = broker.issue({
  issuerIdentity: "authority",
  subjectIdentity: "gateway",
  audience: "desktop",
  anchorFlowId: "flow",
  scopes: ["artifact:read"],
  artifactKinds: ["transcript"],
  pastDepth: 0,
  futureDepth: 0,
  expiresAt: "2026-09-09T13:00:00.000Z",
});
const running = await capabilityHistory.startCapabilityHistoryUnixServer({
  mode: "synthetic",
  socketPath,
  broker,
  principal: { identity: "gateway", audience: "desktop" },
});

console.log(token);
await new Promise<void>((resolve) => {
  process.on("SIGTERM", resolve);
  process.on("SIGINT", resolve);
});
await running.close();
