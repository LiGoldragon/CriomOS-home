{ inputs, pkgs, ... }:
let
  homeConfiguration = inputs.home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
    extraSpecialArgs = {
      inherit inputs;
      user = {
        size = "Min";
        useColemak = false;
        hasPublicKey = false;
        gitSigningKey = "";
        matrixId = "";
        isMultimediaDev = false;
        emailAddress = "herdr-toast-check@example.invalid";
        githubId = "herdr-toast-check";
        name = "herdr-toast-check";
        publicKeys = [ ];
      };
      horizon.node = {
        name = "herdr-toast-check";
        machine.architecture = "x86_64";
      };
      hexis = inputs.hexis.packages.${pkgs.stdenv.hostPlatform.system}.default;
      rustToolchain = pkgs.rustc;
    };
    modules = [
      inputs.stylix.homeModules.stylix
      inputs.niri-flake.homeModules.config
      inputs.noctalia.homeModules.default
      # The Home deployment supplies criomos.corePackages and the Codex-next
      # client; this standalone fixture imports the same modules so herdr.nix
      # can resolve both Codex executables.
      ../../modules/home/core-packages.nix
      ../../modules/home/profiles/min/codex-next.nix
      ../../modules/home/profiles/min/default.nix
      {
        home = {
          username = "herdr-toast-check";
          homeDirectory = "/home/herdr-toast-check";
          stateVersion = "26.11";
        };
        criomosHome.herdr.predecessorGeneration.homeFiles = toString priorHomeManagerFiles;
      }
    ];
  };
  untrustedHomeConfiguration = inputs.home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
    extraSpecialArgs = {
      inherit inputs;
      user = {
        size = "Min";
        useColemak = false;
        hasPublicKey = false;
        gitSigningKey = "";
        matrixId = "";
        isMultimediaDev = false;
        emailAddress = "herdr-toast-check@example.invalid";
        githubId = "herdr-toast-check";
        name = "herdr-toast-check";
        publicKeys = [ ];
      };
      horizon.node = {
        name = "herdr-toast-check";
        machine.architecture = "x86_64";
      };
      hexis = inputs.hexis.packages.${pkgs.stdenv.hostPlatform.system}.default;
      rustToolchain = pkgs.rustc;
    };
    modules = [
      inputs.stylix.homeModules.stylix
      inputs.niri-flake.homeModules.config
      inputs.noctalia.homeModules.default
      ../../modules/home/core-packages.nix
      ../../modules/home/profiles/min/codex-next.nix
      ../../modules/home/profiles/min/default.nix
      {
        home = {
          username = "herdr-toast-check";
          homeDirectory = "/home/herdr-toast-check";
          stateVersion = "26.11";
        };
      }
    ];
  };
  rotationHomeConfiguration = homeConfiguration.extendModules {
    modules = [
      {
        criomosHome.herdr.predecessorGeneration.homeFiles = pkgs.lib.mkForce (toString rotationPriorHomeManagerFiles);
      }
    ];
  };
  recordedDanglingKvantumTarget = "recorded-$(touch \"$TMPDIR/kvantum-literal-executed\")-target";
  recordedDanglingKvantumHomeConfiguration = homeConfiguration.extendModules {
    modules = [
      {
        criomosHome.herdr.kvantumDanglingLink.literalTarget = recordedDanglingKvantumTarget;
      }
    ];
  };
  configToml = builtins.readFile homeConfiguration.config.xdg.configFile."herdr/config.toml".source;
  legacyConfigToml = ''
    [ui.toast]
    delivery = "terminal"

    [ui]
    agent_panel_sort = "spaces"
  '';
  legacyConfig = pkgs.writeText "herdr-legacy-config.toml" legacyConfigToml;
  predecessorManagedConfigToml = ''
    [theme]
    auto_switch = true
    dark_name = "catppuccin"
    light_name = "catppuccin-latte"

    [ui.toast]
    delivery = "terminal"

    [ui]
    agent_panel_sort = "spaces"
  '';
  predecessorManagedConfig = pkgs.writeText "herdr-predecessor-managed-config.toml" predecessorManagedConfigToml;
  priorHomeManagerFiles = pkgs.runCommand "home-manager-files" { } ''
    mkdir -p "$out/.config/herdr" "$out/.config/Kvantum/Base16Kvantum"
    cp ${predecessorManagedConfig} "$out/.config/herdr/config.toml"
    printf '%s\n' '[General]' 'theme=Base16Kvantum' \
      > "$out/.config/Kvantum/Base16Kvantum/Base16Kvantum.kvconfig"
  '';
  rotationPredecessorManagedConfigToml = ''
    [agents]
    codex_executables = [
      "/nix/store/0s199vn7jivakb7kqkcc2znxw4klv840-codex-stable-flow-client/bin/codex-stable-flow-client",
      "/nix/store/x74szg3cbsn5s41nan43kfs6wb4xww61-codex-next-flow-client/bin/codex-next-flow-client",
    ]

    [theme]
    auto_switch = true
    dark_name = "catppuccin"
    light_name = "catppuccin-latte"

    [ui.toast]
    delivery = "terminal"

    [ui]
    agent_panel_sort = "spaces"
  '';
  rotationPredecessorManagedConfig = pkgs.writeText "herdr-rotation-predecessor-config.toml" rotationPredecessorManagedConfigToml;
  rotationPriorHomeManagerFiles = pkgs.runCommand "rotation-home-manager-files" { } ''
    mkdir -p "$out/.config/herdr"
    cp ${rotationPredecessorManagedConfig} "$out/.config/herdr/config.toml"
  '';
  # The managed config names store paths (the Codex clients); parsing only
  # inspects keys, so the string context is dropped before fromTOML.
  parsedConfigToml = builtins.fromTOML (builtins.unsafeDiscardStringContext configToml);
  herdrAdoption = homeConfiguration.config.home.activation.adoptHerdrConfig.data;
  herdrAdoptionScript = pkgs.writeText "herdr-adoption" herdrAdoption;
  rotationHerdrAdoption = rotationHomeConfiguration.config.home.activation.adoptHerdrConfig.data;
  rotationHerdrAdoptionScript = pkgs.writeText "rotation-herdr-adoption" rotationHerdrAdoption;
  untrustedHerdrAdoption = untrustedHomeConfiguration.config.home.activation.adoptHerdrConfig.data;
  untrustedHerdrAdoptionScript = pkgs.writeText "untrusted-herdr-adoption" untrustedHerdrAdoption;
  kvantumAdoption = homeConfiguration.config.home.activation.adoptManagedKvantumDirectory.data;
  kvantumAdoptionScript = pkgs.writeText "kvantum-adoption" kvantumAdoption;
  recordedDanglingKvantumAdoption =
    recordedDanglingKvantumHomeConfiguration.config.home.activation.adoptManagedKvantumDirectory.data;
  recordedDanglingKvantumAdoptionScript =
    pkgs.writeText "recorded-dangling-kvantum-adoption" recordedDanglingKvantumAdoption;
  untrustedKvantumAdoption = untrustedHomeConfiguration.config.home.activation.adoptManagedKvantumDirectory.data;
  untrustedKvantumAdoptionScript = pkgs.writeText "untrusted-kvantum-adoption" untrustedKvantumAdoption;
  checkLinkTargets = homeConfiguration.config.home.activation.checkLinkTargets.data;
  checkLinkTargetsScript = pkgs.writeText "herdr-check-link-targets" checkLinkTargets;
  activationPackage = homeConfiguration.activationPackage;
in
assert parsedConfigToml.ui.toast.delivery == "terminal";
assert parsedConfigToml.theme.auto_switch;
assert parsedConfigToml.theme.dark_name == "catppuccin";
assert parsedConfigToml.theme.light_name == "catppuccin-latte";
assert parsedConfigToml.ui.agent_panel_sort == "spaces";
assert configToml != legacyConfigToml;
pkgs.runCommand "herdr-toast-delivery" {
  nativeBuildInputs = [ pkgs.coreutils ];
  inherit activationPackage;
} ''
  set -eu

  exact_home="$TMPDIR/exact-home"
  mkdir -p "$exact_home/.config/herdr"
  cp ${legacyConfig} "$exact_home/.config/herdr/config.toml"
  HOME="$exact_home" ${pkgs.bash}/bin/bash ${herdrAdoptionScript}
  test ! -e "$exact_home/.config/herdr/config.toml"
  cmp ${legacyConfig} \
    "$exact_home/.local/state/criomos/herdr-adoption/config.toml.pre-home-manager"
  sha256sum --check --status \
    "$exact_home/.local/state/criomos/herdr-adoption/config.toml.pre-home-manager.sha256"

  # A trusted managed predecessor is a multi-hop transition: its exact
  # home-files member may be replaced without inventing a legacy backup.
  predecessor_link_home="$TMPDIR/predecessor-link-home"
  mkdir -p "$predecessor_link_home/.config/herdr"
  ln -s ${priorHomeManagerFiles}/.config/herdr/config.toml \
    "$predecessor_link_home/.config/herdr/config.toml"
  HOME="$predecessor_link_home" ${pkgs.bash}/bin/bash ${herdrAdoptionScript}
  test ! -e "$predecessor_link_home/.config/herdr/config.toml"
  test ! -e "$predecessor_link_home/.local/state/criomos/herdr-adoption/config.toml.pre-home-manager"

  # The witnessed former managed configuration carries the old two-client
  # routing tuple. It is admitted only with the legacy backup, so no local
  # configuration is overwritten by this migration.
  rotation_predecessor_home="$TMPDIR/rotation-predecessor-home"
  mkdir -p "$rotation_predecessor_home/.config/herdr" \
    "$rotation_predecessor_home/.local/state/criomos/herdr-adoption"
  cp ${legacyConfig} \
    "$rotation_predecessor_home/.local/state/criomos/herdr-adoption/config.toml.pre-home-manager"
  ln -s ${rotationPriorHomeManagerFiles}/.config/herdr/config.toml \
    "$rotation_predecessor_home/.config/herdr/config.toml"
  HOME="$rotation_predecessor_home" ${pkgs.bash}/bin/bash ${rotationHerdrAdoptionScript}
  test ! -e "$rotation_predecessor_home/.config/herdr/config.toml"
  cmp ${legacyConfig} \
    "$rotation_predecessor_home/.local/state/criomos/herdr-adoption/config.toml.pre-home-manager"

  untrusted_link_home="$TMPDIR/untrusted-link-home"
  mkdir -p "$untrusted_link_home/.config/herdr"
  ln -s ${priorHomeManagerFiles}/.config/herdr/config.toml \
    "$untrusted_link_home/.config/herdr/config.toml"
  if HOME="$untrusted_link_home" ${pkgs.bash}/bin/bash ${untrustedHerdrAdoptionScript}; then
    echo "Herdr adoption accepted a managed link without a trusted predecessor generation" >&2
    exit 1
  fi
  test -L "$untrusted_link_home/.config/herdr/config.toml"

  unrelated_link_home="$TMPDIR/unrelated-link-home"
  mkdir -p "$unrelated_link_home/.config/herdr"
  ln -s ${legacyConfig} "$unrelated_link_home/.config/herdr/config.toml"
  if HOME="$unrelated_link_home" ${pkgs.bash}/bin/bash ${herdrAdoptionScript}; then
    echo "Herdr adoption accepted an unrelated legacy-content symlink" >&2
    exit 1
  fi
  test -L "$unrelated_link_home/.config/herdr/config.toml"

  mismatch_home="$TMPDIR/mismatch-home"
  mkdir -p "$mismatch_home/.config/herdr"
  printf '%s\n' '[ui.toast]' 'delivery = "desktop"' > "$mismatch_home/.config/herdr/config.toml"
  if HOME="$mismatch_home" ${pkgs.bash}/bin/bash ${herdrAdoptionScript}; then
    echo "Herdr adoption accepted a mismatched configuration" >&2
    exit 1
  fi
  printf '%s\n' '[ui.toast]' 'delivery = "desktop"' > "$TMPDIR/mismatched-config.toml"
  cmp "$TMPDIR/mismatched-config.toml" "$mismatch_home/.config/herdr/config.toml"

  missing_home="$TMPDIR/missing-home"
  mkdir -p "$missing_home"
  HOME="$missing_home" ${pkgs.bash}/bin/bash ${herdrAdoptionScript}
  test ! -e "$missing_home/.config"
  test ! -e "$missing_home/.config/herdr/config.toml"
  test ! -e "$missing_home/.local/state/criomos/herdr-adoption/config.toml.pre-home-manager"
  test ! -e "$missing_home/.local/state/criomos/herdr-adoption/config.toml.pre-home-manager.sha256"

  # First activation has no target to adopt.  Home Manager then creates its
  # declared managed link.  Re-running the same generated activation must
  # keep that link, and the later normal link-target phase must still accept
  # it.  This covers the persistent service's ordinary repeat path without
  # resetting any user state.
  managed_repeat_home="$TMPDIR/managed-repeat-home"
  mkdir -p "$managed_repeat_home/.config/herdr"
  HOME="$managed_repeat_home" ${pkgs.bash}/bin/bash ${herdrAdoptionScript}
  ln -s "$activationPackage/home-files/.config/herdr/config.toml" \
    "$managed_repeat_home/.config/herdr/config.toml"
  HOME="$managed_repeat_home" ${pkgs.bash}/bin/bash ${herdrAdoptionScript}
  test -L "$managed_repeat_home/.config/herdr/config.toml"
  test "$(readlink -f "$managed_repeat_home/.config/herdr/config.toml")" = \
    ${homeConfiguration.config.xdg.configFile."herdr/config.toml".source}
  HOME="$managed_repeat_home" ${pkgs.bash}/bin/bash ${herdrAdoptionScript}
  HOME="$managed_repeat_home" newGenPath="$activationPackage" \
    ${pkgs.bash}/bin/bash ${checkLinkTargetsScript}
  test -L "$managed_repeat_home/.config/herdr/config.toml"

  directory_home="$TMPDIR/directory-home"
  mkdir -p "$directory_home/.config/herdr/config.toml"
  if HOME="$directory_home" ${pkgs.bash}/bin/bash ${herdrAdoptionScript}; then
    echo "Herdr adoption accepted a directory target" >&2
    exit 1
  fi
  test -d "$directory_home/.config/herdr/config.toml"

  # Home Manager now creates child links in this directory. Preserve the old
  # exact predecessor directory link by rename before those children exist.
  kvantum_transition_home="$TMPDIR/kvantum-transition-home"
  mkdir -p "$kvantum_transition_home/.config/Kvantum"
  ln -s ${priorHomeManagerFiles}/.config/Kvantum/Base16Kvantum \
    "$kvantum_transition_home/.config/Kvantum/Base16Kvantum"
  HOME="$kvantum_transition_home" ${pkgs.bash}/bin/bash ${kvantumAdoptionScript}
  test ! -e "$kvantum_transition_home/.config/Kvantum/Base16Kvantum"
  test -L "$kvantum_transition_home/.local/state/criomos/kvantum-adoption/Base16Kvantum.pre-home-manager"
  test "$(readlink "$kvantum_transition_home/.local/state/criomos/kvantum-adoption/Base16Kvantum.pre-home-manager")" = \
    ${priorHomeManagerFiles}/.config/Kvantum/Base16Kvantum
  mkdir -p "$kvantum_transition_home/.config/Kvantum/Base16Kvantum"
  ln -s ${priorHomeManagerFiles}/.config/Kvantum/Base16Kvantum/Base16Kvantum.kvconfig \
    "$kvantum_transition_home/.config/Kvantum/Base16Kvantum/Base16Kvantum.kvconfig"

  foreign_kvantum_home="$TMPDIR/foreign-kvantum-home"
  mkdir -p "$foreign_kvantum_home/.config/Kvantum"
  ln -s ${priorHomeManagerFiles}/.config/herdr \
    "$foreign_kvantum_home/.config/Kvantum/Base16Kvantum"
  if HOME="$foreign_kvantum_home" ${pkgs.bash}/bin/bash ${kvantumAdoptionScript}; then
    echo "Kvantum transition accepted a foreign directory symlink" >&2
    exit 1
  fi
  test -L "$foreign_kvantum_home/.config/Kvantum/Base16Kvantum"

  untrusted_kvantum_home="$TMPDIR/untrusted-kvantum-home"
  mkdir -p "$untrusted_kvantum_home/.config/Kvantum"
  ln -s ${priorHomeManagerFiles}/.config/Kvantum/Base16Kvantum \
    "$untrusted_kvantum_home/.config/Kvantum/Base16Kvantum"
  if HOME="$untrusted_kvantum_home" ${pkgs.bash}/bin/bash ${untrustedKvantumAdoptionScript}; then
    echo "Kvantum transition accepted a directory without a trusted predecessor generation" >&2
    exit 1
  fi
  test -L "$untrusted_kvantum_home/.config/Kvantum/Base16Kvantum"

  dangling_kvantum_home="$TMPDIR/dangling-kvantum-home"
  mkdir -p "$dangling_kvantum_home/.config/Kvantum"
  ln -s "$TMPDIR/missing-Base16Kvantum" \
    "$dangling_kvantum_home/.config/Kvantum/Base16Kvantum"
  if HOME="$dangling_kvantum_home" ${pkgs.bash}/bin/bash ${kvantumAdoptionScript}; then
    echo "Kvantum transition accepted a dangling directory symlink" >&2
    exit 1
  fi
  test -L "$dangling_kvantum_home/.config/Kvantum/Base16Kvantum"

  mismatched_recorded_target_home="$TMPDIR/mismatched-recorded-target-home"
  mkdir -p "$mismatched_recorded_target_home/.config/Kvantum"
  ln -s "different-dangling-target" \
    "$mismatched_recorded_target_home/.config/Kvantum/Base16Kvantum"
  if HOME="$mismatched_recorded_target_home" \
    ${pkgs.bash}/bin/bash ${recordedDanglingKvantumAdoptionScript}; then
    echo "Kvantum transition accepted a mismatched recorded target" >&2
    exit 1
  fi
  test -L "$mismatched_recorded_target_home/.config/Kvantum/Base16Kvantum"
  test ! -e "$mismatched_recorded_target_home/.local/state/criomos/kvantum-adoption/Base16Kvantum.pre-home-manager"

  recorded_dangling_kvantum_home="$TMPDIR/recorded-dangling-kvantum-home"
  mkdir -p "$recorded_dangling_kvantum_home/.config/Kvantum"
  ln -s ${pkgs.lib.escapeShellArg recordedDanglingKvantumTarget} \
    "$recorded_dangling_kvantum_home/.config/Kvantum/Base16Kvantum"
  HOME="$recorded_dangling_kvantum_home" \
    ${pkgs.bash}/bin/bash ${recordedDanglingKvantumAdoptionScript}
  test ! -e "$recorded_dangling_kvantum_home/.config/Kvantum/Base16Kvantum"
  test -L "$recorded_dangling_kvantum_home/.local/state/criomos/kvantum-adoption/Base16Kvantum.pre-home-manager"
  test "$(readlink "$recorded_dangling_kvantum_home/.local/state/criomos/kvantum-adoption/Base16Kvantum.pre-home-manager")" = \
    ${pkgs.lib.escapeShellArg recordedDanglingKvantumTarget}
  test ! -e "$TMPDIR/kvantum-literal-executed"
  mkdir -p "$recorded_dangling_kvantum_home/.config/Kvantum/Base16Kvantum"
  ln -s ${priorHomeManagerFiles}/.config/Kvantum/Base16Kvantum/Base16Kvantum.kvconfig \
    "$recorded_dangling_kvantum_home/.config/Kvantum/Base16Kvantum/Base16Kvantum.kvconfig"

  extant_recorded_target_home="$TMPDIR/extant-recorded-target-home"
  mkdir -p "$extant_recorded_target_home/.config/Kvantum"/${pkgs.lib.escapeShellArg recordedDanglingKvantumTarget}
  ln -s ${pkgs.lib.escapeShellArg recordedDanglingKvantumTarget} \
    "$extant_recorded_target_home/.config/Kvantum/Base16Kvantum"
  if HOME="$extant_recorded_target_home" \
    ${pkgs.bash}/bin/bash ${recordedDanglingKvantumAdoptionScript}; then
    echo "Kvantum transition accepted an extant recorded target" >&2
    exit 1
  fi
  test -L "$extant_recorded_target_home/.config/Kvantum/Base16Kvantum"
  test ! -e "$extant_recorded_target_home/.local/state/criomos/kvantum-adoption/Base16Kvantum.pre-home-manager"

  occupied_kvantum_recovery_home="$TMPDIR/occupied-kvantum-recovery-home"
  mkdir -p "$occupied_kvantum_recovery_home/.config/Kvantum" \
    "$occupied_kvantum_recovery_home/.local/state/criomos/kvantum-adoption"
  ln -s ${pkgs.lib.escapeShellArg recordedDanglingKvantumTarget} \
    "$occupied_kvantum_recovery_home/.config/Kvantum/Base16Kvantum"
  : > "$occupied_kvantum_recovery_home/.local/state/criomos/kvantum-adoption/Base16Kvantum.pre-home-manager"
  if HOME="$occupied_kvantum_recovery_home" \
    ${pkgs.bash}/bin/bash ${recordedDanglingKvantumAdoptionScript}; then
    echo "Kvantum transition overwrote an occupied recovery path" >&2
    exit 1
  fi
  test -L "$occupied_kvantum_recovery_home/.config/Kvantum/Base16Kvantum"
  test -f "$occupied_kvantum_recovery_home/.local/state/criomos/kvantum-adoption/Base16Kvantum.pre-home-manager"

  touch "$out"
''
