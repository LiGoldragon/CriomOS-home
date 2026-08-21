{ inputs, pkgs, ... }:
let
  defaultOpenerModule = ../../modules/home/profiles/min/default-opener.nix;
  minProfileImports =
    (import ../../modules/home/profiles/min/default.nix {
      lib = pkgs.lib;
      inherit pkgs;
      criomos-lib = null;
      user.size.min = true;
      horizon = null;
      config = { };
      inputs = { };
      hexis = null;
      rustToolchain = null;
    }).imports;
  openerConfiguration = inputs.home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
    extraSpecialArgs.user.size.min = true;
    modules = [
      defaultOpenerModule
      {
        home = {
          username = "default-opener-check";
          homeDirectory = "/tmp/default-opener-check";
          stateVersion = "26.05";
        };
      }
    ];
  };
  opener = openerConfiguration.config.home.file.".local/bin/xdg-open".source;
  graphicalEnvironment = openerConfiguration.config.xdg.configFile."uwsm/env".source;
  sessionEnvironment = "${openerConfiguration.config.home.sessionVariablesPackage}/etc/profile.d/hm-session-vars.sh";
  defaultApplications = openerConfiguration.config.xdg.mimeApps.defaultApplications;
  mimeapps = pkgs.writeText "default-opener-mimeapps.list" ''
    [Default Applications]
    text/html=${builtins.head defaultApplications."text/html"};
    x-scheme-handler/http=${builtins.head defaultApplications."x-scheme-handler/http"};
    x-scheme-handler/https=${builtins.head defaultApplications."x-scheme-handler/https"};
  '';
in
assert builtins.any (module: toString module == toString defaultOpenerModule) minProfileImports;
assert defaultApplications."text/html" == [ "google-chrome.desktop" ];
assert defaultApplications."x-scheme-handler/http" == [ "google-chrome.desktop" ];
assert defaultApplications."x-scheme-handler/https" == [ "google-chrome.desktop" ];
pkgs.runCommand "default-opener"
  {
    nativeBuildInputs = [
      pkgs.coreutils
      pkgs.handlr-regex
    ];
  }
  ''
    set -eu

    assert_first_path_component() {
      if [ "''${PATH%%:*}" != "$home/.local/bin" ]; then
        printf 'expected first PATH component %s, got %s\n' "$home/.local/bin" "''${PATH%%:*}" >&2
        return 1
      fi
    }

    assert_wrapper_wins() {
      resolved="$(command -v xdg-open)"
      if [ "$resolved" != "$home/.local/bin/xdg-open" ]; then
        printf 'expected wrapper %s, got %s\n' "$home/.local/bin/xdg-open" "$resolved" >&2
        return 1
      fi
    }

    home=/tmp/default-opener-check
    system_bin="$TMPDIR/system-bin"
    mkdir -p "$home/.local/bin" "$home/.config" "$home/.local/share/applications" "$system_bin"
    ln -s ${opener} "$home/.local/bin/xdg-open"
    cat > "$system_bin/xdg-open" <<EOF
    #!${pkgs.runtimeShell}
    exit 1
    EOF
    chmod +x "$system_bin/xdg-open"
    cp ${mimeapps} "$home/.config/mimeapps.list"
    cat > "$home/.local/share/applications/google-chrome.desktop" <<EOF
    [Desktop Entry]
    Type=Application
    Name=Google Chrome
    Exec=${pkgs.coreutils}/bin/true %U
    MimeType=text/html;x-scheme-handler/http;x-scheme-handler/https;
    EOF

    export HOME="$home"
    export XDG_CONFIG_HOME="$home/.config"
    export XDG_DATA_HOME="$home/.local/share"
    export XDG_DATA_DIRS="$home/.local/share"
    export XDG_RUNTIME_DIR="$TMPDIR/runtime"
    PATH="$system_bin:${pkgs.coreutils}/bin:${pkgs.handlr-regex}/bin"
    . ${sessionEnvironment}
    assert_first_path_component
    assert_wrapper_wins

    PATH="$system_bin:${pkgs.coreutils}/bin:${pkgs.handlr-regex}/bin"
    . ${graphicalEnvironment}
    assert_first_path_component
    assert_wrapper_wins
    handler="$(handlr get x-scheme-handler/https --json)"
    case "$handler" in
      *'"handler":"google-chrome.desktop"'*) ;;
      *)
        printf 'handlr did not select google-chrome.desktop: %s\n' "$handler" >&2
        exit 1
        ;;
    esac
    xdg-open https://example.invalid/default-opener
    mime="$(handlr mime https://example.invalid/default-opener --json)"
    case "$mime" in
      *x-scheme-handler/https*) ;;
      *)
        printf 'handlr did not classify HTTPS URL as x-scheme-handler/https: %s\n' "$mime" >&2
        exit 1
        ;;
    esac
    touch "$out"
  ''
