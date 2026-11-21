{ pkgs, inputs, ... }:
let
  system = pkgs.stdenv.hostPlatform.system;
  runtime = pkgs.runCommandCC "flow-heap-profile-fixture" {} ''
    mkdir -p "$out/bin"
    $CC -g -O0 -fno-omit-frame-pointer ${./fixture.c} -o "$out/bin/flow-nexus-daemon"
  '';
  fixtureInputs = inputs // {
    flow-0550.packages.${system} = { default = runtime; nexus-configure = runtime; };
  };
  configuration = (inputs.home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
    extraSpecialArgs = {
      inputs = fixtureInputs;
      user = { name = "heap-profile-test"; size = "Min"; capabilities = [ "AgentStack" ]; };
    };
    modules = [
      ../../modules/home/profiles/min/nexus-places.nix
      ../../modules/home/profiles/min/flow-0550.nix
      {
        home.username = "heap-profile-test";
        home.homeDirectory = "/home/heap-profile-test";
        home.stateVersion = "26.05";
        criomosHome.flow0550.heapProfile.directory = "./profile";
      }
    ];
  }).config;
  service = configuration.systemd.user.services.flow-nexus-0550;
  launcher = builtins.head service.Service.ExecStart;
in
assert service.Service.Type == "notify";
assert service.Service.NotifyAccess == "all";
assert service.Service.MemoryMax == "3G";
assert service.Service.MemorySwapMax == "0";
assert service.Service.UMask == "0077";
assert service.Unit.X-SwitchMethod == "keep-old";
pkgs.runCommand "flow-heap-profile-contract" {
  nativeBuildInputs = [ pkgs.python3 pkgs.heaptrack ];
} ''
  cd "$TMPDIR"
  python3 ${./verify.py} ${launcher} ${pkgs.heaptrack}/bin/heaptrack_print
  mkdir -p "$out"
  cp -a profile "$out/"
''
