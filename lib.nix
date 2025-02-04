{ lib, ... }:

rec {
  # converts a list of `mountOption` to a comma-separated string that is passed to the mount unit
  toOptionsString =
    mountOptions:
    builtins.concatStringsSep "," (
      map (
        option: if option.value == null then option.name else "${option.name}=${option.value}"
      ) mountOptions
    );

  # concatenates two paths
  # inserts a "/" in between if there is none, removes one if there are two
  concatTwoPaths =
    parent: child:
    with lib.strings;
    if hasSuffix "/" parent then
      if
        hasPrefix "/" child
      # "/parent/" "/child"
      then
        parent + (removePrefix "/" child)
      # "/parent/" "child"
      else
        parent + child
    else if
      hasPrefix "/" child
    # "/parent" "/child"
    then
      parent + child
    # "/parent" "child"
    else
      parent + "/" + child;

  # concatenates a list of paths using `concatTwoPaths`
  concatPaths = builtins.foldl' concatTwoPaths "";

  # get the parent directory of an absolute path
  parentDirectory =
    path:
    with lib.strings;
    assert "/" == (builtins.substring 0 1 path);
    let
      parts = splitString "/" (removeSuffix "/" path);
      len = builtins.length parts;
    in
    if len < 1 then "/" else concatPaths ([ "/" ] ++ (lib.lists.sublist 0 (len - 1) parts));

  # get the parent directories of an absolute path, except for the root directory
  parentDirectories =
    path:
    with lib.strings;
    assert "/" == (builtins.substring 0 1 path);
    let
      parts = builtins.filter (s: builtins.isString s && s != "") (builtins.split "/" path);
      len = builtins.length parts;
      paths = builtins.genList (n: concatPaths ([ "/" ] ++ (lib.lists.take (n + 1) parts))) (len - 1);
    in
    builtins.filter (p: p != "") paths;

  # retrieves all directories configured in a `preserveAtSubmodule`
  getAllDirectories =
    stateConfig:
    stateConfig.directories ++ (builtins.concatLists (getUserDirectories stateConfig.users));
  # retrieves all files configured in a `preserveAtSubmodule`
  getAllFiles =
    stateConfig: stateConfig.files ++ (builtins.concatLists (getUserFiles stateConfig.users));
  # retrieves the list of directories for all users in a `preserveAtSubmodule`
  getUserDirectories = lib.mapAttrsToList (_: userConfig: userConfig.directories);
  # retrieves the list of files for all users in a `preserveAtSubmodule`
  getUserFiles = lib.mapAttrsToList (_: userConfig: userConfig.files);
  # creates a list of parent directories for all users in a `preserveAtSubmodule`
  withUserParentDirs = lib.mapAttrs (
    _: userConfig:
    userConfig
    // {
      parentDirs =
        map (d: parentDirectories d.directory) userConfig.directories
        ++ map (d: parentDirectories d.file) userConfig.files;
    }
  );
  # filters a list of files or directories, returns only bindmounts
  onlyBindMounts =
    forInitrd: builtins.filter (conf: conf.how == "bindmount" && conf.inInitrd == forInitrd);
  # filters a list of files or directories, returns only symlinks
  onlySymLinks =
    forInitrd: builtins.filter (conf: conf.how == "symlink" && conf.inInitrd == forInitrd);

  # creates tmpfiles.d rules for the `settings` option of the tmpfiles module from a `preserveAtSubmodule`
  mkTmpfilesRules =
    forInitrd: preserveAt: stateConfig:
    let
      allDirectories = getAllDirectories stateConfig;
      allFiles = getAllFiles stateConfig;
      mountedDirectories = onlyBindMounts forInitrd allDirectories;
      mountedFiles = onlyBindMounts forInitrd allFiles;
      symlinkedDirectories = onlySymLinks forInitrd allDirectories;
      symlinkedFiles = onlySymLinks forInitrd allFiles;

      prefix = if forInitrd then "/sysroot" else "/";

      mountedDirRules = map (
        dirConfig:
        let
          persistentDirPath = concatPaths [
            prefix
            stateConfig.persistentStoragePath
            dirConfig.directory
          ];
          volatileDirPath = concatPaths [
            prefix
            dirConfig.directory
          ];
        in
        {
          # directory on persistent storage
          "${persistentDirPath}".d = {
            inherit (dirConfig) user group mode;
          };
          # directory on volatile storage
          "${volatileDirPath}".d = {
            inherit (dirConfig) user group mode;
          };
        }
        // lib.optionalAttrs dirConfig.configureParent {
          # parent directory of directory on persistent storage
          "${parentDirectory persistentDirPath}".d = {
            inherit (dirConfig.parent) user group mode;
          };
          # parent directory of symlink on volatile storage
          "${parentDirectory volatileDirPath}".d = {
            inherit (dirConfig.parent) user group mode;
          };
        }
      ) mountedDirectories;

      mountedFileRules = map (
        fileConfig:
        let
          persistentFilePath = concatPaths [
            prefix
            stateConfig.persistentStoragePath
            fileConfig.file
          ];
          volatileFilePath = concatPaths [
            prefix
            fileConfig.file
          ];
        in
        {
          # file on persistent storage
          "${concatPaths [
            prefix
            stateConfig.persistentStoragePath
            fileConfig.file
          ]}".f = {
            inherit (fileConfig) user group mode;
          };
          # file on volatile storage
          "${concatPaths [
            prefix
            fileConfig.file
          ]}".f = {
            inherit (fileConfig) user group mode;
          };
        }
        // lib.optionalAttrs fileConfig.configureParent {
          # parent directory of file on persistent storage
          "${parentDirectory persistentFilePath}".d = {
            inherit (fileConfig.parent) user group mode;
          };
          # parent directory of symlink on volatile storage
          "${parentDirectory volatileFilePath}".d = {
            inherit (fileConfig.parent) user group mode;
          };
        }
      ) mountedFiles;

      symlinkedDirRules = map (
        dirConfig:
        let
          persistentDirPath = concatPaths [
            prefix
            stateConfig.persistentStoragePath
            dirConfig.directory
          ];
          volatileDirPath = concatPaths [
            prefix
            dirConfig.directory
          ];
        in
        {
          # symlink on volatile storage
          "${volatileDirPath}".L = {
            inherit (dirConfig) user group mode;
            argument = concatPaths [
              stateConfig.persistentStoragePath
              dirConfig.directory
            ];
          };
        }
        // lib.optionalAttrs dirConfig.createLinkTarget {
          # directory on persistent storage
          "${persistentDirPath}".d = {
            inherit (dirConfig) user group mode;
          };
        }
        // lib.optionalAttrs dirConfig.configureParent {
          # parent directory of directory on persistent storage
          "${parentDirectory persistentDirPath}".d = {
            inherit (dirConfig.parent) user group mode;
          };
          # parent directory of symlink on volatile storage
          "${parentDirectory volatileDirPath}".d = {
            inherit (dirConfig.parent) user group mode;
          };
        }
      ) symlinkedDirectories;

      symlinkedFileRules = map (
        fileConfig:
        let
          persistentFilePath = concatPaths [
            prefix
            stateConfig.persistentStoragePath
            fileConfig.file
          ];
          volatileFilePath = concatPaths [
            prefix
            fileConfig.file
          ];
        in
        {
          # symlink on volatile storage
          "${volatileFilePath}".L = {
            inherit (fileConfig) user group mode;
            argument = concatPaths [
              stateConfig.persistentStoragePath
              fileConfig.file
            ];
          };
        }
        // lib.optionalAttrs fileConfig.createLinkTarget {
          # file on persistent storage
          "${persistentFilePath}".f = {
            inherit (fileConfig) user group mode;
          };
        }
        // lib.optionalAttrs fileConfig.configureParent {
          # parent directory of file on persistent storage
          "${parentDirectory persistentFilePath}".d = {
            inherit (fileConfig.parent) user group mode;
          };
          # parent directory of symlink on volatile storage
          "${parentDirectory volatileFilePath}".d = {
            inherit (fileConfig.parent) user group mode;
          };
        }
      ) symlinkedFiles;

      rules = mountedDirRules ++ symlinkedDirRules ++ mountedFileRules ++ symlinkedFileRules;
    in
    rules;

  # creates extra tmpfiles.d rules for parent directories for all users in a `preserveAtSubmodule`
  mkTmpfilesRulesExtra =
    preserveAt: stateConfig:
    lib.foldlAttrs (
      state: _: userConfig:
      let
        homeDir = userConfig.home;
        persistentHomeDir = concatPaths [
          stateConfig.persistentStoragePath
          homeDir
        ];
        excludedDirs = (parentDirectories homeDir) ++ [ homeDir ];
        user = userConfig.username;
        group = userConfig._group;
        mode = userConfig._dirMode;
      in
      state
      ++ [
        {
          # home directory on persistent storage
          "${persistentHomeDir}".d = {
            inherit user group;
            mode = userConfig._homeMode;
          };
          # home directory on volatile storage is set by system.activationScripts.users
          # or systemd.tmpfiles.settings.home-directories (when sysusers/userborn is enabled)
        }
      ]
      ++ map (
        dirs:
        lib.foldl' (
          state: dir:
          let
            persistentDirPath = concatPaths [
              stateConfig.persistentStoragePath
              dir
            ];
            volatileDirPath = dir;
          in
          state
          // {
            # parent directory on persistent storage
            "${persistentDirPath}".d = {
              inherit user group mode;
            };
            # parent directory on volatile storage
            "${volatileDirPath}".d = {
              inherit user group mode;
            };
          }
        ) { } (builtins.filter (d: !(builtins.elem d excludedDirs)) dirs)
      ) userConfig.parentDirs
    ) [ ] (withUserParentDirs stateConfig.users);

  # creates systemd mount unit configurations from a `preserveAtSubmodule`
  mkMountUnits =
    forInitrd: preserveAt: stateConfig:
    let
      allDirectories = getAllDirectories stateConfig;
      allFiles = getAllFiles stateConfig;
      mountedDirectories = onlyBindMounts forInitrd allDirectories;
      mountedFiles = onlyBindMounts forInitrd allFiles;

      prefix = if forInitrd then "/sysroot" else "/";

      directoryMounts = map (directoryConfig: {
        options = toOptionsString (
          directoryConfig.mountOptions
          ++ (lib.optional forInitrd {
            name = "x-initrd.mount";
            value = null;
          })
        );
        where = concatPaths [
          prefix
          directoryConfig.directory
        ];
        what = concatPaths [
          prefix
          stateConfig.persistentStoragePath
          directoryConfig.directory
        ];
        unitConfig.DefaultDependencies = "no";
        conflicts = [ "umount.target" ];
        wantedBy = if forInitrd then [
          "initrd-preservation.target"
        ] else [
          "preservation.target"
        ];
        before = if forInitrd then [
          # directory mounts are set up before tmpfiles
          "systemd-tmpfiles-setup-sysroot.service"
          "initrd-preservation.target"
        ] else [
          "systemd-tmpfiles-setup.service"
          "preservation.target"
        ];
      }) mountedDirectories;

      fileMounts = map (fileConfig: {
        options = toOptionsString (
          fileConfig.mountOptions
          ++ (lib.optional forInitrd {
            name = "x-initrd.mount";
            value = null;
          })
        );
        where = concatPaths [
          prefix
          fileConfig.file
        ];
        what = concatPaths [
          prefix
          stateConfig.persistentStoragePath
          fileConfig.file
        ];
        unitConfig = {
          DefaultDependencies = "no";
          ConditionPathExists = concatPaths [
            prefix
            stateConfig.persistentStoragePath
            fileConfig.file
          ];
        };
        conflicts = [ "umount.target" ];
        after =
          if forInitrd then
            [ "systemd-tmpfiles-setup-sysroot.service" ]
          else
            [ "systemd-tmpfiles-setup.service" ];
        wantedBy = if forInitrd then [ "initrd-preservation.target" ] else [ "preservation.target" ];
        before = if forInitrd then [ "initrd-preservation.target" ] else [ "preservation.target" ];
      }) mountedFiles;

      mountUnits = directoryMounts ++ fileMounts;
    in
    mountUnits;

  # aliases to avoid the use of a nameless bool outside this lib
  mkRegularMountUnits = mkMountUnits false;
  mkInitrdMountUnits = mkMountUnits true;
  mkRegularTmpfilesRules = mkTmpfilesRules false;
  mkRegularTmpfilesRulesExtra = mkTmpfilesRulesExtra;
  mkInitrdTmpfilesRules = mkTmpfilesRules true;
}
