{
  pkgs,
  inputs ? null,
  codexVersionData ? builtins.fromJSON (builtins.readFile ./hashes.json),
  version ? codexVersionData.version,
  hash ? codexVersionData.hash,
  sourceRoot ? "source/codex-rs",
  cargoVendor ? {
    cargoHash = codexVersionData.cargoHash;
  },
  preBuild ? ''
    # Keep rustc's peak RSS bounded on the configured ARM builder.
    substituteInPlace Cargo.toml \
      --replace-fail 'codegen-units = 4' 'codegen-units = 16'
  '',
  doInstallCheck ? true,
}:

let
  inherit (pkgs)
    lib
    stdenv
    fetchurl
    installShellFiles
    makeWrapper
    rustPlatform
    pkg-config
    openssl
    bubblewrap
    libcap
    versionCheckHook
    ;
  mkRustyV8Archive = import ../../lib/rusty-v8.nix {
    inherit lib stdenv;
    inherit fetchurl;
  };
  actualSrc = fetchurl {
    url = "https://github.com/openai/codex/archive/refs/tags/rust-v${version}.tar.gz";
    inherit hash;
  };
  librustyV8Package = mkRustyV8Archive codexVersionData.librusty_v8;
in
rustPlatform.buildRustPackage (
  {
    pname = "codex";
    inherit version sourceRoot;
    src = actualSrc;
    unpackPhase = ''
      runHook preUnpack
      mkdir source
      tar --extract --file "$src" --gzip --strip-components=1 --directory source
      runHook postUnpack
    '';

    cargoBuildFlags = [
      "--package"
      "codex-cli"
      "--package"
      "codex-code-mode-host"
    ];

    nativeBuildInputs = [
      installShellFiles
      makeWrapper
      pkg-config
    ]
    ++ lib.optionals stdenv.hostPlatform.isDarwin [ rustPlatform.bindgenHook ];
    buildInputs = [ openssl ] ++ lib.optionals stdenv.hostPlatform.isLinux [ libcap ];
    env = {
      RUSTY_V8_ARCHIVE = librustyV8Package;
    }
    // lib.optionalAttrs (librustyV8Package ? srcBinding) {
      RUSTY_V8_SRC_BINDING_PATH = librustyV8Package.srcBinding;
    }
    // {
      CARGO_BUILD_JOBS = "2";
      CARGO_PROFILE_RELEASE_DEBUG = "false";
      CARGO_PROFILE_RELEASE_STRIP = "symbols";
    };
    inherit preBuild;
    postFixup = lib.optionalString stdenv.hostPlatform.isLinux ''
      mkdir -p $out/codex-resources
      ln -s ${lib.getExe bubblewrap} $out/codex-resources/bwrap
      wrapProgram $out/bin/codex --prefix PATH : ${lib.makeBinPath [ bubblewrap ]}
    '';
    doCheck = false;
    postInstall =
      lib.optionalString (doInstallCheck && stdenv.buildPlatform.canExecute stdenv.hostPlatform)
        ''
          installShellCompletion --cmd codex \
            --bash <($out/bin/codex completion bash) \
            --fish <($out/bin/codex completion fish) \
            --zsh <($out/bin/codex completion zsh)
        '';
    inherit doInstallCheck;
    nativeInstallCheckInputs = [ versionCheckHook ];
    passthru = {
      category = "AI Coding Agents";
      updater = {
        kind = "github-source";
        purl = "pkg:github/openai/codex";
        depHashKey = "cargoHash";
        script = ./update.py;
      };
      updateScript = [
        (lib.getExe pkgs.python3)
        ./update.py
      ];
    };
    meta = {
      description = "OpenAI Codex CLI - a coding agent that runs locally on your computer";
      homepage = "https://github.com/openai/codex";
      changelog = "https://github.com/openai/codex/releases/tag/rust-v${version}";
      sourceProvenance = with lib.sourceTypes; [
        fromSource
        binaryNativeCode
      ];
      license = lib.licenses.asl20;
      mainProgram = "codex";
      platforms = lib.platforms.unix;
    };
  }
  // cargoVendor
)
