{
  lib,
  pkgs,
  horizon,
  user,
  ...
}:
let
  inherit (horizon.node) behavesAs;
  inherit (user) size;

  bridge = pkgs.writeShellApplication {
    name = "criomos-capture-card-virtual-camera-bridge";
    text = ''
      exec ${pkgs.ffmpeg-full}/bin/ffmpeg \
        -hide_banner \
        -nostdin \
        -loglevel info \
        -f v4l2 \
        -input_format mjpeg \
        -video_size 1920x1080 \
        -framerate 30 \
        -i /dev/video4 \
        -an \
        -vf scale=1920:1080:flags=bicubic,fps=30,format=yuyv422 \
        -f v4l2 \
        -pix_fmt yuyv422 \
        -r 30 \
        /dev/video1
    '';
  };
in
{
  config = lib.mkIf (size.large && behavesAs.edge) {
    home.packages = [ bridge ];

    systemd.user.services.capture-card-virtual-camera = {
      Unit = {
        Description = "Fixed-format capture-card virtual camera bridge";
        PartOf = [ "graphical-session.target" ];
        After = [ "graphical-session-pre.target" ];
      };

      Service = {
        ExecStart = "${bridge}/bin/criomos-capture-card-virtual-camera-bridge";
        Restart = "on-failure";
        RestartSec = "2s";
      };

      Install.WantedBy = [ "graphical-session.target" ];
    };
  };
}
