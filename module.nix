{ config, lib, ... }:

let
  cfg = config.preservation;

  inherit (import ./lib.nix { inherit lib; })
    mkRegularMountUnits
    mkInitrdMountUnits
    mkRegularTmpfilesRules
    mkRegularTmpfilesRulesExtra
    mkInitrdTmpfilesRules
    ;
in
{
  imports = [
    ./options.nix
  ];

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.boot.initrd.systemd.enable;
        message = "This module cannot be used with scripted initrd.";
      }
    ];

    boot.initrd.systemd = {
      targets.initrd-preservation = {
        description = "Initrd Preservation Mounts";
        before = [ "initrd.target" ];
        wantedBy = [ "initrd.target" ];
      };
      tmpfiles.settings.preservation = lib.mkMerge (
        lib.flatten (lib.mapAttrsToList mkInitrdTmpfilesRules cfg.preserveAt)
      );
      mounts = lib.flatten (lib.mapAttrsToList mkInitrdMountUnits cfg.preserveAt);
    };

    systemd = {
      targets.preservation = {
        description = "Preservation Mounts";
        before = [ "sysinit.target" ];
        wantedBy = [ "sysinit.target" ];
      };
      tmpfiles.settings.preservation = lib.mkMerge (
        lib.flatten (lib.mapAttrsToList mkRegularTmpfilesRules cfg.preserveAt)
      );
      # use a separate, lower priority file for extra tmpfiles rules
      tmpfiles.settings.preservationExtra = lib.mkMerge (
        lib.flatten (lib.mapAttrsToList mkRegularTmpfilesRulesExtra cfg.preserveAt)
      );
      mounts = lib.flatten (lib.mapAttrsToList mkRegularMountUnits cfg.preserveAt);
    };

  };
}
