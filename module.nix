{ options, config, lib, pkgs, ... }:

let
  cfg = config.preservation;

  inherit (import ./lib.nix { inherit lib; })
    mkRegularMountUnits
    mkInitrdMountUnits
    mkRegularTmpfilesRules
    mkInitrdTmpfilesRules
    mkInitrdTmpfilesService
    mkRegularTmpfilesService
    ;

  escapeArgument = lib.strings.escapeC [
    "\t"
    "\n"
    "\r"
    " "
    "\\"
  ];

  settingsEntryToRule = path: entry: ''
    '${entry.type}' '${path}' '${entry.mode}' '${entry.user}' '${entry.group}' '${entry.age}' ${escapeArgument entry.argument}
  '';

  pathsToRules = lib.mapAttrsToList (
    path: types: lib.concatStrings (lib.mapAttrsToList (_type: settingsEntryToRule path) types)
  );

  mkRuleFileContent =
    paths:
    let
      evalPaths =
        paths:
        (lib.evalModules {
          modules = [
            {
              options.settings = lib.mkOption {
                inherit (options.systemd.tmpfiles.settings) type;
                default = { };
              };
            }
            { settings.preservation = lib.mkMerge (paths ++ lib.singleton (lib.mkDefault { })); }
          ];
        }).config.settings.preservation;
    in
    lib.concatStrings (pathsToRules (evalPaths paths));

  configPathSuffix = "preservation.conf";
  configPath = "/etc/${configPathSuffix}";

  persistentStoragePaths = lib.mapAttrsToList (_: pcfg: pcfg.persistentStoragePath) cfg.preserveAt;
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
      contents."${configPath}".source = pkgs.writeText "preservation.conf" (
        mkRuleFileContent (lib.flatten (lib.mapAttrsToList mkInitrdTmpfilesRules cfg.preserveAt))
      );
      mounts = lib.flatten (lib.mapAttrsToList mkInitrdMountUnits cfg.preserveAt);
      services.systemd-tmpfiles-setup-preservation = mkInitrdTmpfilesService configPath persistentStoragePaths;
    };

    systemd = {
      targets.preservation = {
        description = "Preservation Mounts";
        before = [ "sysinit.target" ];
        wantedBy = [ "sysinit.target" ];
      };
      mounts = lib.flatten (lib.mapAttrsToList mkRegularMountUnits cfg.preserveAt);
      services = {
        systemd-tmpfiles-setup-preservation =
          mkRegularTmpfilesService true configPath persistentStoragePaths
            "";
        systemd-tmpfiles-resetup-preservation =
          mkRegularTmpfilesService false configPath persistentStoragePaths
            config.environment.etc."${configPathSuffix}".source;
      };
    };

    environment.etc."${configPathSuffix}".source = pkgs.writeText "preservation.conf" (
      mkRuleFileContent (lib.flatten (lib.mapAttrsToList mkRegularTmpfilesRules cfg.preserveAt))
    );
  };
}
