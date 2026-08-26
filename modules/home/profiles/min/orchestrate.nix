{
  pkgs,
  inputs,
  ...
}:
let
  system = pkgs.stdenv.hostPlatform.system;
  orchestratePackage = inputs.orchestrate.packages.${system}.default;

  orchestrateProfilePackage =
    pkgs.runCommand "${orchestratePackage.name}-profile" { nativeBuildInputs = [ pkgs.makeWrapper ]; }
      ''
        mkdir -p $out/bin
        makeWrapper ${orchestratePackage}/bin/orchestrate $out/bin/orchestrate \
          --run 'export ORCHESTRATE_SOCKET="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/orchestrate-nexus/orchestrate.sock"'
        makeWrapper ${orchestratePackage}/bin/meta-orchestrate $out/bin/meta-orchestrate \
          --run 'export ORCHESTRATE_META_SOCKET="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/orchestrate-nexus/meta-orchestrate.sock"'
      '';
in
{
  home.packages = [ orchestrateProfilePackage ];

  systemd.user.services.orchestrate-nexus = {
    Unit = {
      Description = "Orchestrate Nexus path-reservation service";
      StartLimitIntervalSec = 60;
      StartLimitBurst = 5;
    };

    Service = {
      StateDirectory = "orchestrate-nexus";
      StateDirectoryMode = "0700";
      RuntimeDirectory = "orchestrate-nexus";
      RuntimeDirectoryMode = "0700";
      ExecStart = "${orchestratePackage}/bin/orchestrate-nexus";
      Restart = "on-failure";
      RestartSec = "2s";
    };

    Install.WantedBy = [ "default.target" ];
  };
}
