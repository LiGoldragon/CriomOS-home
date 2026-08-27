{
  pkgs,
}:

let
  inherit (pkgs)
    lib
    stdenv
    fetchFromGitHub
    makeSetupHook
    binutils
    xxd
    strace
    ;
  buildPackages = pkgs.buildPackages;
  version = "1.0.0";
  src = fetchFromGitHub {
    owner = "Mic92";
    repo = "wrap-buddy";
    rev = "ba5ab56ddc572482c26b2cf08414befc5f66ad40";
    hash = "sha256-NlBlJbQsFKDgUtawzAEGF0iIO/xON2LXGw/axFOU4g8=";
  };
  dynamicLinker = stdenv.cc.bintools.dynamicLinker;
  libcLib = "${stdenv.cc.libc}/lib";
  cxxForBuild = "${buildPackages.stdenv.cc}/bin/c++";
  wrapBuddy = stdenv.mkDerivation {
    pname = "wrap-buddy";
    inherit version src;
    depsBuildBuild = [ buildPackages.stdenv.cc ];
    nativeBuildInputs = [
      binutils
      xxd
    ];
    makeFlags = [
      "CXX_FOR_BUILD=${cxxForBuild}"
      "BINDIR=$(out)/bin"
      "LIBDIR=$(out)/lib/wrap-buddy"
      "INTERP=${dynamicLinker}"
      "LIBC_LIB=${libcLib}"
    ]
    ++ lib.optional stdenv.hostPlatform.isx86_64 "BUILD_32BIT=1";
    nativeInstallCheckInputs = [ strace ];
    doInstallCheck = true;
    installCheckTarget = "check";
    enableParallelBuilding = true;
    meta = {
      description = "Patch ELF binaries with a stub loader for NixOS compatibility";
      homepage = "https://github.com/Mic92/wrap-buddy";
      mainProgram = "wrap-buddy";
      license = lib.licenses.mit;
      maintainers = [ lib.maintainers.mic92 ];
      platforms = [
        "x86_64-linux"
        "i686-linux"
        "aarch64-linux"
      ];
    };
  };
in
makeSetupHook {
  name = "wrap-buddy-hook";
  propagatedBuildInputs = [ wrapBuddy ];
  passthru.hideFromDocs = true;
  meta = {
    description = "Setup hook that patches ELF binaries with a stub loader";
    license = lib.licenses.mit;
    maintainers = [ lib.maintainers.mic92 ];
    platforms = lib.platforms.linux;
  };
} "${src}/nix/wrap-buddy-hook.sh"
