const assert = require("node:assert/strict");
const { once } = require("node:events");
const { mkdtemp, readFile, readdir, rm } = require("node:fs/promises");
const { createConnection } = require("node:net");
const { tmpdir } = require("node:os");
const { join } = require("node:path");
const { createJiti } = require(process.env.PI_JITI_MODULE);

class LiveThemeControlFixture {
  constructor() {
    this.handlers = new Map();
    this.liveThemes = [];
    this.persistedThemes = [];
    this.statuses = [];
    this.notifications = [];
    this.pi = {
      on: (event, handler) => this.handlers.set(event, handler),
    };
    this.context = {
      ui: {
        getTheme: (name) => ({ name }),
        setTheme: (theme) => {
          this.liveThemes.push(theme.name);
          return { success: true };
        },
        setStatus: (name, value) => this.statuses.push({ name, value }),
        notify: (message, level) => this.notifications.push({ message, level }),
      },
      setTheme: (name) => this.persistedThemes.push(name),
    };
  }

  async start() {
    await this.handlers.get("session_start")({}, this.context);
  }

  async sendMode(registryDirectory, mode) {
    const entry = (await readdir(registryDirectory)).find((name) => name.endsWith(".path"));
    assert.ok(entry, "theme control registers one Pi-only socket path");
    const socketPath = (await readFile(join(registryDirectory, entry), "utf8")).trim();
    const connection = createConnection(socketPath);
    await once(connection, "connect");
    connection.end(`${mode}\n`);
    await once(connection, "close");
  }

  async shutdown() {
    await this.handlers.get("session_shutdown")({});
  }
}

async function main() {
  const registryDirectory = await mkdtemp(join(tmpdir(), "live-theme-control-"));
  process.env.PI_LIVE_THEME_CONTROL_REGISTRY_DIRECTORY = registryDirectory;
  const extension = await createJiti(__filename, { interopDefault: true }).import(process.argv[2], { default: true });
  const fixture = new LiveThemeControlFixture();
  extension(fixture.pi);
  await fixture.start();
  await fixture.sendMode(registryDirectory, "dark");
  await fixture.sendMode(registryDirectory, "light");

  assert.deepEqual(fixture.liveThemes, ["criomos-dark", "criomos-light"], "live Pi UI updates for both Chroma modes");
  assert.deepEqual(
    fixture.persistedThemes,
    ["criomos-dark", "criomos-light"],
    "theme persistence remains delegated to the extension context",
  );
  assert.deepEqual(fixture.statuses, [], "live theme events leave no persistent status");
  assert.deepEqual(fixture.notifications, [], "successful live theme events stay silent");

  await fixture.shutdown();
  await rm(registryDirectory, { recursive: true, force: true });
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
