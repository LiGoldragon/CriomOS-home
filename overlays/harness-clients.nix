final: _: {
  gemini-cli = import ../packages/gemini-cli { pkgs = final; };
  opencode = import ../packages/opencode { pkgs = final; };
  orca-ide = import ../packages/orca-ide { pkgs = final; };
}
