# Home Manager module, added to every Home Manager user by ./home-manager.nix
{
  config,
  lib,
  ...
}@args:

let
  inherit (config.home) homeDirectory;

  # path relative to the home directory, given relative to or absolute below it
  relativeToHome =
    path:
    let
      isBelowHome = !lib.hasPrefix "/" path || lib.hasPrefix "${homeDirectory}/" path;
    in
    assert lib.assertMsg isBelowHome "preservation: `${path}` is not below `${homeDirectory}`";
    lib.removePrefix "${homeDirectory}/" path;

  # a path, or an attribute set of the NixOS module's per-entry options
  entry =
    pathOption:
    with lib.types;
    coercedTo str (path: { ${pathOption} = path; }) (submodule {
      freeformType = attrsOf anything;
      options.${pathOption} = lib.mkOption {
        type = str;
        apply = relativeToHome;
        description = ''
          Specify the path, relative to or absolute below {option}`home.homeDirectory`.
        '';
      };
    });

  preserveAtSubmodule = {
    options = {
      directories = lib.mkOption {
        type = lib.types.listOf (entry "directory");
        default = [ ];
        description = ''
          Specify a list of directories that should be preserved for this user.
          The paths are interpreted relative to {option}`home.homeDirectory`,
          absolute paths must lie below it.

          Entries take the same options as
          {option}`preservation.preserveAt.<path>.users.<user>.directories`
          of the NixOS module.
        '';
        example = lib.literalExpression ''
          [
            ".rabbit_hole"
            "''${config.xdg.dataHome}/someapp"
            {
              directory = ".ssh";
              mode = "0700";
            }
          ]
        '';
      };
      files = lib.mkOption {
        type = lib.types.listOf (entry "file");
        default = [ ];
        description = ''
          Specify a list of files that should be preserved for this user.
          The paths are interpreted relative to {option}`home.homeDirectory`,
          absolute paths must lie below it.

          Entries take the same options as
          {option}`preservation.preserveAt.<path>.users.<user>.files`
          of the NixOS module.
        '';
        example = lib.literalExpression ''
          [
            {
              file = "''${config.xdg.configHome}/foo";
              mode = "0600";
            }
            "bar"
          ]
        '';
      };
      commonMountOptions = lib.mkOption {
        type = with lib.types; listOf (either str (attrsOf anything));
        default = [ ];
        description = ''
          Specify a list of mount options that should be added to all files and
          directories of this user, for which {option}`how` is set to `bindmount`.

          Same as {option}`preservation.preserveAt.<path>.users.<user>.commonMountOptions`
          of the NixOS module.
        '';
        example = [ "x-gvfs-hide" ];
      };
    };
  };
in
{
  options.preservation = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = args.osConfig.preservation.enable or false;
      defaultText = lib.literalExpression "osConfig.preservation.enable or false";
      readOnly = true;
      description = ''
        Whether the NixOS module applies this user's preservation.
      '';
    };

    preserveAt = lib.mkOption {
      type =
        with lib.types;
        attrsWith {
          placeholder = "path";
          elemType = submodule preserveAtSubmodule;
        };
      default = { };
      description = ''
        Specify this user's part of the NixOS option
        {option}`preservation.preserveAt.<path>.users.<user>`.
      '';
      example = lib.literalExpression ''
        {
          "/persistent" = {
            directories = [ ".rabbit_hole" ];
            files = [
              {
                file = "''${config.xdg.configHome}/foo";
                mode = "0600";
              }
            ];
          };
        }
      '';
    };
  };
}
