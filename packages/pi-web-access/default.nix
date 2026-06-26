{ inputs, pkgs, ... }:

let
  dependencies = [
    {
      name = "@mixmark-io/domino";
      src = inputs.pi-web-access-mixmark-io-domino-src;
    }
    {
      name = "@mozilla/readability";
      src = inputs.pi-web-access-mozilla-readability-src;
    }
    {
      name = "boolbase";
      src = inputs.pi-web-access-boolbase-src;
    }
    {
      name = "css-select";
      src = inputs.pi-web-access-css-select-src;
    }
    {
      name = "css-what";
      src = inputs.pi-web-access-css-what-src;
    }
    {
      name = "cssom";
      src = inputs.pi-web-access-cssom-src;
    }
    {
      name = "dom-serializer";
      src = inputs.pi-web-access-dom-serializer-src;
    }
    {
      name = "domelementtype";
      src = inputs.pi-web-access-domelementtype-src;
    }
    {
      name = "domhandler";
      src = inputs.pi-web-access-domhandler-src;
    }
    {
      name = "domutils";
      src = inputs.pi-web-access-domutils-src;
    }
    {
      name = "entities";
      src = inputs.pi-web-access-entities-src;
    }
    {
      name = "html-escaper";
      src = inputs.pi-web-access-html-escaper-src;
    }
    {
      name = "htmlparser2";
      src = inputs.pi-web-access-htmlparser2-src;
    }
    {
      name = "linkedom";
      src = inputs.pi-web-access-linkedom-src;
    }
    {
      name = "nth-check";
      src = inputs.pi-web-access-nth-check-src;
    }
    {
      name = "p-limit";
      src = inputs.pi-web-access-p-limit-src;
    }
    {
      name = "turndown";
      src = inputs.pi-web-access-turndown-src;
    }
    {
      name = "uhyphen";
      src = inputs.pi-web-access-uhyphen-src;
    }
    {
      name = "unpdf";
      src = inputs.pi-web-access-unpdf-src;
    }
    {
      name = "yocto-queue";
      src = inputs.pi-web-access-yocto-queue-src;
    }
  ];

  installDependencyCommands = pkgs.lib.concatMapStringsSep "\n" (dependency: ''
    mkdir -p "$nodeModules/${dependency.name}"
    tar -xzf ${dependency.src} -C "$nodeModules/${dependency.name}" --strip-components=1
  '') dependencies;
in
pkgs.stdenvNoCC.mkDerivation {
  pname = "pi-web-access";
  version = "0.13.0";

  dontUnpack = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    packageRoot=$out/share/pi-packages/pi-web-access
    nodeModules=$packageRoot/node_modules
    mkdir -p "$packageRoot" "$nodeModules"

    tar -xzf ${inputs.pi-web-access-src} -C "$packageRoot" --strip-components=1
    ${installDependencyCommands}

    runHook postInstall
  '';

  meta = {
    description = "Pi extension for web search, content fetching, GitHub cloning, and video/PDF extraction";
    homepage = "https://github.com/nicobailon/pi-web-access";
    license = pkgs.lib.licenses.mit;
  };
}
