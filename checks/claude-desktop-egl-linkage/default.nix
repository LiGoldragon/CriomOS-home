{ inputs, pkgs, ... }:
let
  system = pkgs.stdenv.hostPlatform.system;
  homePkgs = pkgs.extend (pkgs.lib.composeManyExtensions (import ../../overlays { inherit inputs; }));
  claudeCodePackage = homePkgs.callPackage ../../packages/claude-code { inherit inputs; };
  claudeDesktopPackage = homePkgs.claudeDesktopWithDeclaredClaudeCode {
    claudeDesktopPackage = inputs.llm-agents.packages.${system}.claude-desktop;
    inherit claudeCodePackage;
  };
  eglLoaderSource = pkgs.writeText "claude-desktop-egl-loader.c" ''
    #define _GNU_SOURCE
    #include <dlfcn.h>
    #include <link.h>
    #include <stdio.h>
    #include <string.h>

    int main(int argc, char **argv) {
      if (argc != 2) return 64;
      void *handle = dlopen("libEGL.so.1", RTLD_NOW | RTLD_LOCAL);
      if (handle == NULL) {
        fputs(dlerror(), stderr);
        return 1;
      }
      struct link_map *map = NULL;
      if (dlinfo(handle, RTLD_DI_LINKMAP, &map) != 0 || map == NULL) return 2;
      if (strcmp(map->l_name, argv[1]) != 0) {
        fprintf(stderr, "resolved %s, expected %s\\n", map->l_name, argv[1]);
        return 3;
      }
      puts(map->l_name);
    }
  '';
in
pkgs.runCommand "claude-desktop-egl-linkage"
  {
    nativeBuildInputs = [
      pkgs.coreutils
      pkgs.patchelf
      pkgs.stdenv.cc
    ];
  }
  ''
    set -eu

    gles=${claudeDesktopPackage}/lib/claude-desktop/libGLESv2.so
    expected_egl=${pkgs.libglvnd}/lib/libEGL.so.1
    gles_rpath="$(${pkgs.patchelf}/bin/patchelf --print-rpath "$gles")"
    test -n "$gles_rpath"

    loader="$TMPDIR/egl-loader"
    ${pkgs.stdenv.cc}/bin/cc -o "$loader" ${eglLoaderSource} -ldl
    ${pkgs.patchelf}/bin/patchelf --set-rpath "$gles_rpath" "$loader"
    test "$(${pkgs.patchelf}/bin/patchelf --print-rpath "$loader")" = "$gles_rpath"

    env -u LD_LIBRARY_PATH "$loader" "$expected_egl" >/dev/null
    echo 'claude-desktop-egl-linkage: passed'
    touch "$out"
  ''
