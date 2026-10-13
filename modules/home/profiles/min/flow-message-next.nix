{ config, lib, ... }:
{
  # Retained option lets old callers fail explicitly; the duplicate Flow/Message
  # preview deployment is retired. Its stores and history are never removed.
  options.criomosHome.flowMessageNext.enable = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = "Retired duplicate Flow/Message preview deployment.";
  };
  config.assertions = [
    {
      assertion = !config.criomosHome.flowMessageNext.enable;
      message = "Flow has one declared Home deployment; the preview pair is retired";
    }
  ];
}
