{ config, lib, ... }:

let
  mountOption = lib.types.submodule {
    options = {
      name = lib.mkOption {
        type = lib.types.str;
        description = ''
          Specify the name of the mount option.
        '';
        example = "bind";
      };
      value = lib.mkOption {
        type = with lib.types; nullOr str;
        default = null;
        description = ''
          Optionally specify a value for the mount option.
        '';
      };
    };
  };

  directoryPath =
    attrs@{ defaultOwner, ... }:
    {
      options = {
        directory = lib.mkOption {
          type = lib.types.str;
          description = ''
            Specify the path to the directory that should be preserved.
          '';
        };
        how = lib.mkOption {
          type = lib.types.enum [
            "bindmount"
            "copy"
            "symlink"
          ];
          default = "bindmount";
          description = ''
            Specify how this directory should be preserved:

            1. Either a directory is placed both on the volatile and on
            the persistent volume, with a bind mount from the former to
            the latter.

            2. Or a symlink is created on the volatile volume, pointing
            to the corresponding location on the persistent volume.

            3. Or the directory is copied onto the volatile volume on
            startup and copied from the volatile onto the persistent
            volume on shutdown. Note that this method fails to persist
            the file when the system crashes.
          '';
        };
        user = lib.mkOption {
          type = lib.types.str;
          default = defaultOwner;
          description = ''
            Specify the user that owns the directory.
          '';
        };
        group = lib.mkOption {
          type = lib.types.str;
          default = config.users.users.${defaultOwner}.group;
          defaultText = "config.users.users.\${defaultOwner}.group";
          description = ''
            Specify the group that owns the directory.
          '';
        };
        mode = lib.mkOption {
          type = lib.types.str;
          default = "0755";
          description = ''
            Specify the access mode of the directory.
            See the section `Mode` in {manpage}`tmpfiles.d(5)` for more information.
          '';
        };
        configureParent = lib.mkOption {
          type = lib.types.bool;
          default = attrs.config.how == "symlink" && attrs.config.user != "root";
          description = ''
            Specify whether the parent directory of this directory shall be configured with
            custom ownership and permissions.

            By default, missing parent directories are always created with ownership
            `root:root` and mode `0755`, as described in {manpage}`tmpfiles.d(5)`.

            Ownership and mode may be configured through the options
            {option}`parent.user`,
            {option}`parent.group`,
            {option}`parent.mode`.

            Defaults to `true` when {option}`how` is set to `symlink` and
            {option}`user` is not `root`.
          '';
        };
        parent.user = lib.mkOption {
          type = lib.types.str;
          default = defaultOwner;
          description = ''
            Specify the user that owns the parent directory of this file.
          '';
        };
        parent.group = lib.mkOption {
          type = lib.types.str;
          default = config.users.users.${defaultOwner}.group;
          defaultText = "config.users.users.\${defaultOwner}.group";
          description = ''
            Specify the group that owns the parent directory of this file.
          '';
        };
        parent.mode = lib.mkOption {
          type = lib.types.str;
          default = "0755";
          description = ''
            Specify the access mode of the parent directory of this file.
            See the section `Mode` in {manpage}`tmpfiles.d(5)` for more information.
          '';
        };
        mountOptions = lib.mkOption {
          type = with lib.types; listOf (coercedTo str (n: { name = n; }) mountOption);
          description = ''
            Specify a list of mount options that should be used for this directory.
            These options are only used when {option}`how` is set to `bindmount`.
            By default, `bind` and `X-fstrim.notrim` are added,
            use `mkForce` to override these if needed.
            See also {manpage}`fstrim(8)`.
          '';
        };
        createLinkTarget = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = ''
            Only used when {option}`how` is set to `symlink`.

            Specify whether to create an empty directory with the specified ownership
            and permissions as target of the symlink.
          '';
        };
        copyBack = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = ''
            Whether to copy the directory back to the persistent storage at
            shutdown.
          '';
        };
        inInitrd = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = ''
            Whether to prepare preservation of this directory in initrd.

            ::: {.note}
            For most directories there is no need to enable this option.
            :::

            ::: {.important}
            Note that both owner and group for this directory need to be
            available in the initrd for permissions to be set correctly.
            :::
          '';
        };
      };

      config = {
        mountOptions = [
          "bind"
          "X-fstrim.notrim" # see fstrim(8)
        ];
      };
    };

  filePath =
    attrs@{ defaultOwner, ... }:
    {
      options = {
        file = lib.mkOption {
          type = lib.types.str;
          description = ''
            Specify the path to the file that should be preserved.
          '';
        };
        how = lib.mkOption {
          type = lib.types.enum [
            "bindmount"
            "copy"
            "symlink"
          ];
          default = "bindmount";
          description = ''
            Specify how this file should be preserved:

            1. Either a file is placed both on the volatile and on the
            persistent volume, with a bind mount from the former to the
            latter.

            2. Or a symlink is created on the volatile volume, pointing
            to the corresponding location on the persistent volume.

            3. Or the file is copied onto the volatile volume on startup
            and copied from the volatile onto the persistent volume on
            shutdown. Note that this method fails to persist the file
            when the system crashes.
          '';
        };
        user = lib.mkOption {
          type = lib.types.str;
          default = defaultOwner;
          description = ''
            Specify the user that owns the file.
          '';
        };
        group = lib.mkOption {
          type = lib.types.str;
          default = config.users.users.${defaultOwner}.group;
          defaultText = "config.users.users.\${defaultOwner}.group";
          description = ''
            Specify the group that owns the file.
          '';
        };
        mode = lib.mkOption {
          type = lib.types.str;
          default = "0644";
          description = ''
            Specify the access mode of the file.
            See the section `Mode` in {manpage}`tmpfiles.d(5)` for more information.
          '';
        };
        configureParent = lib.mkOption {
          type = lib.types.bool;
          default = attrs.config.how == "symlink" && attrs.config.user != "root";
          description = ''
            Specify whether the parent directory of this file shall be configured with
            custom ownership and permissions.

            By default, missing parent directories are always created with ownership
            `root:root` and mode `0755`, as described in {manpage}`tmpfiles.d(5)`.

            Ownership and mode may be configured through the options
            {option}`parent.user`,
            {option}`parent.group`,
            {option}`parent.mode`.

            Defaults to `true` when {option}`how` is set to `symlink` and
            {option}`user` is not `root`.
          '';
        };
        parent.user = lib.mkOption {
          type = lib.types.str;
          default = defaultOwner;
          description = ''
            Specify the user that owns the parent directory of this file.
          '';
        };
        parent.group = lib.mkOption {
          type = lib.types.str;
          default = config.users.users.${attrs.defaultOwner}.group;
          defaultText = "config.users.users.\${defaultOwner}.group";
          description = ''
            Specify the group that owns the parent directory of this file.
          '';
        };
        parent.mode = lib.mkOption {
          type = lib.types.str;
          default = "0755";
          description = ''
            Specify the access mode of the parent directory of this file.
            See the section `Mode` in {manpage}`tmpfiles.d(5)` for more information.
          '';
        };
        mountOptions = lib.mkOption {
          type = with lib.types; listOf (coercedTo str (o: { name = o; }) mountOption);
          description = ''
            Specify a list of mount options that should be used for this file.
            These options are only used when {option}`how` is set to `bindmount`.
            By default, `bind` is added,
            use `mkForce` to override this if needed.
          '';
        };
        createLinkTarget = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = ''
            Only used when {option}`how` is set to `symlink`.

            Specify whether to create an empty file with the specified ownership
            and permissions as target of the symlink.
          '';
        };
        copyBack = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = ''
            Whether to copy the file back to the persistent storage at shutdown.
          '';
        };
        inInitrd = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = ''
            Whether to prepare preservation of this file in the initrd.

            ::: {.note}
            For most files there is no need to enable this option.

            {file}`/etc/machine-id` is an exception because it needs to
            be populated/read very early.
            :::

            ::: {.important}
            Note that both owner and group for this file need to be
            available in the initrd for permissions to be set correctly.
            :::
          '';
        };
      };

      config = {
        mountOptions = [
          "bind"
        ];
      };
    };

  userModule =
    attrs@{ name, ... }:
    {
      options = {
        username = lib.mkOption {
          type = with lib.types; passwdEntry str;
          default = name;
          description = ''
            Specify the user for which the {option}`directories` and {option}`files`
            should be persisted. Defaults to the name of the parent attribute set.
          '';
        };
        home = lib.mkOption {
          type = with lib.types; passwdEntry path;
          default = config.users.users.${name}.home;
          defaultText = "config.users.users.\${name}.home";
          description = ''
            Specify the path to the user's home directory.
          '';
        };
        directories = lib.mkOption {
          type =
            with lib.types;
            listOf (
              coercedTo str (d: { directory = d; }) (submodule [
                {
                  _module.args.defaultOwner = attrs.config.username;
                  mountOptions = attrs.config.commonMountOptions;
                }
                directoryPath
              ])
            );
          default = [ ];
          apply = map (d: d // { directory = "${attrs.config.home}/${d.directory}"; });
          description = ''
            Specify a list of directories that should be preserved for this user.
            The paths are interpreted relative to {option}`home`.
          '';
          example = [ ".rabbit_hole" ];
        };
        files = lib.mkOption {
          type =
            with lib.types;
            listOf (
              coercedTo str (f: { file = f; }) (submodule [
                {
                  _module.args.defaultOwner = attrs.config.username;
                  mountOptions = attrs.config.commonMountOptions;
                }
                filePath
              ])
            );
          default = [ ];
          apply = map (f: f // { file = "${attrs.config.home}/${f.file}"; });
          description = ''
            Specify a list of files that should be preserved for this user.
            The paths are interpreted relative to {option}`home`.
          '';
          example = lib.literalMD ''
            ```nix
            [
              {
                file = ".config/foo";
                mode = "0600";
              }
              "bar"
            ]
            ```
          '';
        };
        commonMountOptions = lib.mkOption {
          type = with lib.types; listOf (coercedTo str (n: { name = n; }) mountOption);
          default = [];
          example = [
            "x-gvfs-hide"
            "x-gdu.hide"
          ];
          description = ''
            Specify a list of mount options that should be added to all files and directories
            of this user, for which {option}`how` is set to `bindmount`.

            See also the top level {option}`commonMountOptions` and the invdividual
            {option}`mountOptions` that is available per file / directory.
          '';
        };
      };
    };

  preserveAtSubmodule =
    attrs@{ name, ... }:
    {
      options = {
        persistentStoragePath = lib.mkOption {
          type = lib.types.path;
          default = name;
          description = ''
            Specify the location at which the {option}`directories`, {option}`files`,
            {option}`users.directories` and {option}`users.files` should be preserved.
            Defaults to the name of the parent attribute set.
          '';
        };
        directories = lib.mkOption {
          type =
            with lib.types;
            listOf (
              coercedTo str (d: { directory = d; }) (submodule [
                {
                  _module.args.defaultOwner = "root";
                  mountOptions = attrs.config.commonMountOptions;
                }
                directoryPath
              ])
            );
          default = [ ];
          description = ''
            Specify a list of directories that should be preserved.
            The paths are interpreted as absolute paths.
          '';
          example = [ "/var/lib/someservice" ];
        };
        files = lib.mkOption {
          type =
            with lib.types;
            listOf (
              coercedTo str (f: { file = f; }) (submodule [
                {
                  _module.args.defaultOwner = "root";
                  mountOptions = attrs.config.commonMountOptions;
                }
                filePath
              ])
            );
          default = [ ];
          description = ''
            Specify a list of files that should be preserved.
            The paths are interpreted as absolute paths.
          '';
          example = lib.literalMD ''
            ```nix
            [
              {
                file = "/etc/wpa_supplicant.conf";
                how = "symlink";
              }
              {
                file = "/etc/localtime";
                how = "copy";
              }
              {
                file = "/etc/machine-id";
                inInitrd = true;
              }
            ]
            ```
          '';
        };
        users = lib.mkOption {
          type = with lib.types; attrsWith {
            placeholder = "user";
            elemType = submodule [
              { commonMountOptions = attrs.config.commonMountOptions; }
              userModule
            ];
          };
          default = { };
          description = ''
            Specify a set of users with corresponding files and directories that
            should be preserved.
          '';
          example = lib.literalMD ''
            ```nix
            {
              alice.directories = [ ".rabbit_hole" ];
              butz = {
                files = [
                  {
                    file = ".config/foo";
                    mode = "0600";
                  }
                  "bar"
                ];
                directories = [ "unshaved_yaks" ];
              };
            }
            ```
          '';
        };
        commonMountOptions = lib.mkOption {
          type = with lib.types; listOf (coercedTo str (n: { name = n; }) mountOption);
          default = [];
          example = [
            "x-gvfs-hide"
            "x-gdu.hide"
          ];
          description = ''
            Specify a list of mount options that should be added to all files and directories
            under this preservation prefix, for which {option}`how` is set to `bindmount`.

            See also {option}`commonMountOptions` under {option}`users` and the invdividual
            {option}`mountOptions` that is available per file / directory.
          '';
        };
      };
    };

in
{
  options.preservation = {
    enable = lib.mkEnableOption "the preservation module";

    preserveAt = lib.mkOption {
      type = with lib.types; attrsWith {
        placeholder = "path";
        elemType = submodule preserveAtSubmodule;
      };
      description = ''
        Specify a set of locations and the corresponding state that
        should be preserved there.
      '';
      default = { };
      example = lib.literalMD ''
        ```nix
        {
          "/state" = {
            directories = [ "/var/lib/someservice" ];
            files = [
              {
                file = "/etc/wpa_supplicant.conf";
                how = "symlink";
              }
              {
                file = "/etc/machine-id";
                inInitrd = true;
              }
            ];
            users = {
              alice.directories = [ ".rabbit_hole" ];
              butz = {
                files = [
                  {
                    file = ".config/foo";
                    mode = "0600";
                  }
                  "bar"
                ];
                directories = [ "unshaved_yaks" ];
              };
            };
          };
        }
        ```
      '';
    };
  };
}
