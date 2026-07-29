{ pkgs, inputs, ... }:
let
  lib = pkgs.lib;
  module = ../../modules/home/profiles/max/capture-card-virtual-camera.nix;

  mkHomeConfig =
    {
      large,
      edge,
    }:
    inputs.home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      extraSpecialArgs = {
        horizon.node.behavesAs.edge = edge;
        user.size.large = large;
      };
      modules = [
        module
        {
          home.username = "capture-card-check";
          home.homeDirectory = "/home/capture-card-check";
          home.stateVersion = "26.05";
        }
      ];
    };

  edgeLargeConfig =
    (mkHomeConfig {
      large = true;
      edge = true;
    }).config;
  nonEdgeConfig =
    (mkHomeConfig {
      large = true;
      edge = false;
    }).config;
  nonLargeConfig =
    (mkHomeConfig {
      large = false;
      edge = true;
    }).config;

  serviceName = "capture-card-virtual-camera";
  bridgeName = "criomos-capture-card-virtual-camera-bridge";
  serviceExists = builtins.hasAttr serviceName edgeLargeConfig.systemd.user.services;
  service = if serviceExists then edgeLargeConfig.systemd.user.services.${serviceName} else { };
  packageName = package: package.pname or (package.name or "");
  bridgePackages = builtins.filter (
    package: packageName package == bridgeName
  ) edgeLargeConfig.home.packages;
  bridgeExists = builtins.length bridgePackages == 1;
  bridge = if bridgeExists then builtins.head bridgePackages else null;
  bridgeBinary = if bridgeExists then "${bridge}/bin/${bridgeName}" else "";

  assertions = [
    {
      condition = serviceExists;
      message = "the capture-card virtual-camera user service must exist.";
    }
    {
      condition = bridgeExists;
      message = "the Nix-built bridge must be present exactly once in the large edge home packages.";
    }
    {
      condition = !(builtins.hasAttr serviceName nonEdgeConfig.systemd.user.services);
      message = "the service must be gated off when the node is not an edge profile.";
    }
    {
      condition = !(builtins.hasAttr serviceName nonLargeConfig.systemd.user.services);
      message = "the service must be gated off when the user is not a large profile.";
    }
    {
      condition = serviceExists && service.Unit.PartOf == [ "graphical-session.target" ];
      message = "the user service must be tied to the graphical session.";
    }
    {
      condition = serviceExists && service.Install.WantedBy == [ "graphical-session.target" ];
      message = "the user service must be wanted by the graphical session.";
    }
    {
      condition = serviceExists && bridgeExists && service.Service.ExecStart == [ bridgeBinary ];
      message = "the user service ExecStart must reference the Nix-built bridge.";
    }
  ];
  failures = builtins.filter (assertion: !assertion.condition) assertions;
in
if failures != [ ] then
  throw (lib.concatMapStringsSep "\n" (assertion: assertion.message) failures)
else
  pkgs.runCommand "capture-card-virtual-camera" { } ''
    set -eu

    test -x ${bridgeBinary}
    grep -F -- '${pkgs.ffmpeg-full}/bin/ffmpeg' ${bridgeBinary}
    grep -F -- '-f v4l2' ${bridgeBinary}
    grep -F -- '-input_format mjpeg' ${bridgeBinary}
    grep -F -- '-video_size 1920x1080' ${bridgeBinary}
    grep -F -- '-framerate 30' ${bridgeBinary}
    grep -F -- '-i /dev/video4' ${bridgeBinary}
    grep -F -- 'scale=1920:1080:flags=bicubic,fps=30,format=yuyv422' ${bridgeBinary}
    grep -F -- '-pix_fmt yuyv422' ${bridgeBinary}
    grep -F -- '-r 30' ${bridgeBinary}
    grep -F -- '/dev/video1' ${bridgeBinary}

    touch "$out"
  ''
