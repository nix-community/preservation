# adds ./home-manager-module.nix to every Home Manager user and forwards
# their preservation to preservation.preserveAt.<path>.users.<user>
{
  config,
  lib,
  options,
  ...
}:

let
  # one Home Manager user's preservation.preserveAt
  forwardUser =
    name: hmConfig:
    lib.mapAttrs (
      path: preserveAt:
      let
        # labelled with their Home Manager option, so errors point there
        fromHomeManager =
          option: value:
          lib.mkDefinition {
            file = "home-manager.users.${name}.preservation.preserveAt.${path}.${option}";
            inherit value;
          };
      in
      {
        users.${hmConfig.home.username} = {
          home = lib.mkDefinition {
            file = "home-manager.users.${name}.home.homeDirectory";
            value = hmConfig.home.homeDirectory;
          };
        }
        // lib.mapAttrs fromHomeManager {
          inherit (preserveAt) directories files commonMountOptions;
        };
      }
    ) hmConfig.preservation.preserveAt;
in
{
  config = lib.optionalAttrs (options ? home-manager.users) {
    home-manager.sharedModules = [ ./home-manager-module.nix ];

    preservation.preserveAt = lib.mkMerge (lib.mapAttrsToList forwardUser config.home-manager.users);
  };
}
