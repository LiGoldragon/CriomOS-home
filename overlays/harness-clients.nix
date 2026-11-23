final: _: {
  gemini-cli = final.callPackage ../packages/gemini-cli { };
  opencode = final.callPackage ../packages/opencode { };
  orca-ide = final.callPackage ../packages/orca-ide { };
}
