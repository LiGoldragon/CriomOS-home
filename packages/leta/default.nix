{ pkgs, ... }:

pkgs.rustPlatform.buildRustPackage rec {
  pname = "leta";
  version = "0.13.0";

  src = pkgs.fetchurl {
    name = "${pname}-${version}.tar.gz";
    url = "https://crates.io/api/v1/crates/${pname}/${version}/download";
    hash = "sha256-gZymMbcoJzuu6kAAfvmazbsFYB3TrfapUZRLBFy5gk0=";
  };

  cargoHash = "sha256-HKO+07EhQzD8bTaZ63vxo5Q1xAy3o9gI7FjgjCEzQ/Q=";

  meta = {
    description = "LSP Enabled Tools for Agents";
    homepage = "https://github.com/andreasjansson/leta";
    license = pkgs.lib.licenses.mit;
    mainProgram = "leta";
  };
}
