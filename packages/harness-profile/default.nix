{ pkgs, inputs, ... }:
let
  # Exact accounted Ouranos baseline. Its other applications are preserved;
  # harness names come exclusively from the current Home source inputs.
  baseline = builtins.storePath "/nix/store/k6mwx3ys3sxava5ghys588ps97lblik5-home-manager-path";
  flow = pkgs.callPackage ../flow-deployment { inherit inputs; };
  message = pkgs.callPackage ../message-deployment { inherit inputs; };
  curriculum = pkgs.callPackage ../curriculum-resolver-deployment { inherit inputs; };
  messenger = inputs.messenger-clj.packages.${pkgs.stdenv.hostPlatform.system}.default;
in
pkgs.runCommand "harness-home-profile"
  {
    passthru = {
      inherit
        flow
        message
        curriculum
        messenger
        baseline
        ;
    };
  }
  ''
    mkdir -p "$out/bin"
    for path in ${baseline}/*; do
      name=$(basename "$path")
      test "$name" = bin || ln -s "$path" "$out/$name"
    done
    for path in ${baseline}/bin/*; do
      name=$(basename "$path")
      case "$name" in
        flow|flow-meta|flow-nexus|flow-next|flow-next-meta|message|message-meta|meta-message|message-nexus|message-daemon|message-write-configuration|message-next|message-next-meta|curriculum|messenger-clj|hm-*) continue ;;
      esac
      ln -s "$path" "$out/bin/$name"
    done
    for package in ${flow} ${message} ${curriculum} ${messenger}; do
      for path in "$package/bin/"*; do
        name=$(basename "$path")
        test ! -e "$out/bin/$name"
        ln -s "$path" "$out/bin/$name"
      done
    done
  ''
