# OpenCode, the third harness, seized as Claude Code and Codex are: it never
# asks for a permission, its sessions report to Herdr, it reads only its own
# generated skill tree, and it runs an open-weight model.
{
  config,
  inputs,
  lib,
  pkgs,
  horizon,
  user,
  hexis,
  ...
}:
let
  sizeAtLeast = (import ../../../../lib/horizon-user.nix { inherit lib; }).sizeAtLeast user.size;
  cfg = config.criomosHome.opencode;

  # Herdr's own OpenCode integration, byte for byte from the pinned Herdr:
  # the server plugin reports each root session and its state to the pane,
  # the TUI plugin reports the session selected in the pane.
  herdrAssets = "${inputs.herdr}/src/integration/assets/opencode";
  herdrStatePlugin = pkgs.writeText "herdr-agent-state.js" (
    builtins.readFile "${herdrAssets}/herdr-agent-state.js"
  );
  herdrTuiPlugin = pkgs.writeText "herdr-tui-session.js" (
    builtins.readFile "${herdrAssets}/herdr-tui-session.js"
  );

  # A workspace's generated `.opencode/skills` is OpenCode's own projection;
  # the `.claude` and `.agents` trees beside it belong to the other harnesses
  # and carry the same skill names, so OpenCode does not read them.
  opencode = pkgs.symlinkJoin {
    name = "opencode-${pkgs.opencode.version}";
    inherit (pkgs.opencode) version;
    paths = [ pkgs.opencode ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/opencode --set OPENCODE_DISABLE_EXTERNAL_SKILLS 1
    '';
    meta.mainProgram = "opencode";
  };

  localModel = cfg.localModel;
  providerName = "criomos-local";
  modelReference = "${providerName}/${localModel.id}";

  # Qwen3.6-35B-A3B (Apache-2.0): a mixture of experts with 3B active
  # parameters, the strongest open agentic model whose weights fit a 32 GB
  # laptop beside its desktop, at the Unsloth dynamic 3-bit quantization.
  modelFile = pkgs.fetchurl {
    name = "Qwen3.6-35B-A3B-UD-Q3_K_XL.gguf";
    url = "https://huggingface.co/unsloth/Qwen3.6-35B-A3B-GGUF/resolve/a483e9e6cbd595906af30beda3187c2663a1118c/Qwen3.6-35B-A3B-UD-Q3_K_XL.gguf";
    hash = "sha256-qDK5aJkl8b0zW76YXN+wbDa/LPJo9Pj27Or6POtRVhc=";
  };

  provider = {
    npm = "@ai-sdk/openai-compatible";
    name = "CriomOS local";
    options.baseURL = "http://127.0.0.1:${toString localModel.port}/v1";
    models.${localModel.id} = {
      name = "Qwen3.6 35B-A3B (local)";
      reasoning = true;
      tool_call = true;
      limit = {
        context = localModel.contextSize;
        output = 16384;
      };
    };
  };

  declaredConfig = {
    "$schema" = "https://opencode.ai/config.json";
    permission = "allow";
    plugin = [ "${herdrStatePlugin}" ];
    autoupdate = false;
    share = "disabled";
  }
  // lib.optionalAttrs localModel.enable {
    model = modelReference;
    small_model = modelReference;
    provider.${providerName} = provider;
  };
in
{
  options.criomosHome.opencode = {
    package = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      default = opencode;
      description = "OpenCode, reading only its own generated skill tree.";
    };
    localModel = {
      enable = lib.mkOption {
        type = lib.types.bool;
        # The node the cluster gives the OpenCode testing role serves it.
        default = lib.any (capability: (capability.kind or null) == "openCodeTesting") (
          horizon.node.capabilities or [ ]
        );
        description = "Serve the local open-weight model OpenCode uses by default.";
      };
      id = lib.mkOption {
        type = lib.types.str;
        readOnly = true;
        default = "qwen3.6-35b-a3b";
        description = "The model name the local server answers to.";
      };
      port = lib.mkOption {
        type = lib.types.port;
        default = 11435;
        description = "Loopback port of the local model server.";
      };
      contextSize = lib.mkOption {
        type = lib.types.ints.positive;
        default = 65536;
        description = "Context window the local server allocates.";
      };
    };
  };

  config = lib.mkIf (sizeAtLeast "Min") (
    lib.mkMerge [
      {
        home.packages = [ opencode ];

        # Declared keys are asserted on every activation; every other key in
        # the file stays user state. The plugin lists are owned whole, which
        # also retires entries left by earlier client-local integrations.
        home.activation.mergeOpenCodeHarnessConfig = inputs.hexis.lib.mkManagedConfig {
          inherit lib pkgs hexis;
          file = "$HOME/.config/opencode/opencode.json";
          declared = declaredConfig;
          modes = {
            "/permission" = "always";
            "/plugin" = "always";
            "/autoupdate" = "always";
            "/share" = "always";
          }
          // lib.optionalAttrs localModel.enable {
            "/provider/${providerName}" = "always";
          };
        };

        home.activation.mergeOpenCodeHarnessTuiConfig = inputs.hexis.lib.mkManagedConfig {
          inherit lib pkgs hexis;
          file = "$HOME/.config/opencode/tui.json";
          declared.plugin = [ "${herdrTuiPlugin}" ];
          modes."/plugin" = "always";
        };
      }
      (lib.mkIf localModel.enable {
        # The weights are mapped only while the server is awake; it sleeps
        # after ten idle minutes and wakes on the next request.
        systemd.user.services.opencode-local-model = {
          Unit.Description = "Local open-weight model for OpenCode (llama.cpp, Vulkan)";
          Service = {
            Type = "exec";
            ExecStart = lib.escapeShellArgs [
              "${pkgs.llama-cpp-vulkan}/bin/llama-server"
              "--model"
              "${modelFile}"
              "--alias"
              localModel.id
              "--host"
              "127.0.0.1"
              "--port"
              (toString localModel.port)
              "--ctx-size"
              (toString localModel.contextSize)
              # Attention on the integrated GPU, experts on the CPU: full
              # offload loses the Vulkan device on this GPU class.
              "--n-gpu-layers"
              "99"
              "--n-cpu-moe"
              "99"
              "--jinja"
              "--parallel"
              "1"
              "--sleep-idle-seconds"
              "600"
            ];
            Restart = "on-failure";
            RestartSec = "5s";
          };
          Install.WantedBy = [ "default.target" ];
        };
      })
    ]
  );
}
