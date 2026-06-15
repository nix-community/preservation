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

  # splits a path on "/", returning a list of non-empty path components
  parts =
    path:
    builtins.foldl' (acc: p: if builtins.isString p && p != "" then acc ++ [ p ] else acc) [ ] (
      builtins.split "/" path
    );

  # generates a list of path segments that are parents of the given path
  # e.g.: for "/foo/bar/baz" this yields [ "foo" "foo/bar" ]
  parentSegments =
    path:
    let
      # collect all path segments, including the given path itself
      includingPath = builtins.foldl' (
        acc: part: if acc == [ ] then [ part ] else ([ (concatTwoPaths (builtins.head acc) part) ] ++ acc)
      ) [ ] (parts path);
      # return all path segments except for the given path
    in
    builtins.tail includingPath;

  # generates a list of unique path segments that are parents of a given list of paths
  missingIntermediatePaths =
    paths:
    let
      intermediates = builtins.foldl' (acc: path: acc ++ (parentSegments path)) [ ] paths;
    in
    lib.lists.unique (builtins.filter (path: !(builtins.elem path paths)) intermediates);

  # generates a list of attributes to be used in the `directories` option of the `userModule`
  #
  # essentially this takes the given lists of configurations for `directories` and `files`,
  # generates a list of all their unique parent paths and returns a single list of the
  # given configurations extended by the configurations for their parents, using `defaults`
  mkIntermediateUserDirectories =
    defaults: files: prefix: directories:
    let
      partitions = builtins.partition (d: d.inInitrd) (files ++ directories);
      toPaths = map (
        d: if builtins.hasAttr "file" d then lib.removePrefix prefix d.file else d.directory
      );
      intermediateInitrdPaths = missingIntermediatePaths (toPaths partitions.right);
      intermediateRegularPaths = missingIntermediatePaths (toPaths partitions.wrong);
      initrdIntermediates = map (
        p:
        defaults
        // {
          inInitrd = true;
          directory = p;
        }
      ) intermediateInitrdPaths;
      regularIntermediates = map (
        p:
        defaults
        // {
          inInitrd = false;
          directory = p;
        }
      ) intermediateRegularPaths;
    in
    directories ++ initrdIntermediates ++ regularIntermediates;

  # retrieves the list of directories for all users in a `userModule`
  getUserDirectories = lib.mapAttrsToList (_: userConfig: userConfig.directories);
  # retrieves the list of files for all users in a `userModule`
  getUserFiles = lib.mapAttrsToList (_: userConfig: userConfig.files);
  # retrieves all directories configured in a `preserveAtSubmodule`
  getAllDirectories =
    stateConfig:
    stateConfig.directories ++ (builtins.concatLists (getUserDirectories stateConfig.users));
  # retrieves all files configured in a `preserveAtSubmodule`
  getAllFiles =
    stateConfig: stateConfig.files ++ (builtins.concatLists (getUserFiles stateConfig.users));
  # retrieves the list of user configs that preserve any file or directory for all
  # users in a `preserveAtSubmodule`
  getNonEmptyUserConfigs =
    forInitrd: stateConfig:
    let
      preservesAny =
        userConfig: lib.any (def: def.inInitrd == forInitrd) (userConfig.files ++ userConfig.directories);
      nonEmptyUsers = lib.filterAttrs (_: preservesAny) stateConfig.users;
    in
    lib.mapAttrsToList (_: userConfig: userConfig) nonEmptyUsers;
  # filters a list of files or directories, returns only bindmounts
  onlyBindMounts =
    forInitrd: builtins.filter (conf: conf.how == "bindmount" && conf.inInitrd == forInitrd);
  # filters a list of files or directories, returns only symlinks
  onlySymLinks =
    forInitrd: builtins.filter (conf: conf.how == "symlink" && conf.inInitrd == forInitrd);
  # filters a list of files or directories, returns only intermediate paths
  onlyIntermediates =
    forInitrd: builtins.filter (conf: conf.how == "_intermediate" && conf.inInitrd == forInitrd);

  # creates tmpfiles.d rules for the `settings` option of the tmpfiles module from a `preserveAtSubmodule`
  mkTmpfilesRules =
    forInitrd: preserveAt: stateConfig:
    let
      allDirectories = getAllDirectories stateConfig;
      allFiles = getAllFiles stateConfig;
      nonEmptyUserConfigs = getNonEmptyUserConfigs forInitrd stateConfig;
      mountedDirectories = onlyBindMounts forInitrd allDirectories;
      intermediateDirectories = onlyIntermediates forInitrd allDirectories;
      mountedFiles = onlyBindMounts forInitrd allFiles;
      symlinkedDirectories = onlySymLinks forInitrd allDirectories;
      symlinkedFiles = onlySymLinks forInitrd allFiles;

      prefix = if forInitrd then "/sysroot" else "/";

      # directories that are bind-mounted from the persistent prefix
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

      # directories that are not persisted themselves
      intermediateDirRules = map (
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
      ) intermediateDirectories;

      # home directories that are not persisted themselves but require
      # user-specific ownership and permissions on the persistent prefix
      intermediateHomeRules = map (
        userConfig:
        let
          persistentDirPath = concatPaths [
            prefix
            stateConfig.persistentStoragePath
            userConfig.home
          ];
        in
        {
          "${persistentDirPath}".d = {
            user = userConfig.username;
            group = userConfig.homeGroup;
            mode = userConfig.homeMode;
          };
        }

      ) nonEmptyUserConfigs;

      # files that are bind-mounted from the persistent prefix
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
          ]}".f =
            {
              inherit (fileConfig) user group mode;
            };
          # file on volatile storage
          "${concatPaths [
            prefix
            fileConfig.file
          ]}".f =
            {
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

      # directories are linked to from the volatile prefix
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

      # files are linked to from the volatile prefix
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

      rules =
        mountedDirRules
        ++ intermediateDirRules
        ++ intermediateHomeRules
        ++ symlinkedDirRules
        ++ mountedFileRules
        ++ symlinkedFileRules;
    in
    rules;

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
        after =
          if forInitrd then
            [ "systemd-tmpfiles-setup-preservation.service" ]
          else
            [ "systemd-tmpfiles-setup-preservation.service" ];
        wantedBy =
          if forInitrd then
            [
              "initrd-preservation.target"
            ]
          else
            [
              "preservation.target"
            ];
        before =
          if forInitrd then
            [
              "systemd-tmpfiles-setup-sysroot.service"
              "initrd-preservation.target"
            ]
          else
            [
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
            [ "systemd-tmpfiles-setup-preservation.service" ]
          else
            [ "systemd-tmpfiles-setup-preservation.service" ];
        wantedBy = if forInitrd then [ "initrd-preservation.target" ] else [ "preservation.target" ];
        before =
          if forInitrd then
            [
              "systemd-tmpfiles-setup-sysroot.service"
              "initrd-preservation.target"
            ]
          else
            [
              "systemd-tmpfiles-setup.service"
              "preservation.target"
            ];
      }) mountedFiles;

      mountUnits = directoryMounts ++ fileMounts;
    in
    mountUnits;

  # aliases to avoid the use of a nameless bool outside this lib
  mkRegularMountUnits = mkMountUnits false;
  mkInitrdMountUnits = mkMountUnits true;
  mkRegularTmpfilesRules = mkTmpfilesRules false;
  mkInitrdTmpfilesRules = mkTmpfilesRules true;

  mkInitrdTmpfilesService = configPath: persistentStoragePaths: {
    wantedBy = [ "initrd-preservation.target" ];
    before = [
      "initrd.target"
      "shutdown.target"
      "initrd-switch-root.target"
      "systemd-tmpfiles-setup-sysroot.service"
      "initrd-preservation.target"
    ];
    conflicts = [
      "shutdown.target"
      "initrd-switch-root.target"
    ];
    unitConfig = {
      DefaultDependencies = false;
      RefuseManualStop = true;
      RequiresMountsFor = map (concatTwoPaths "/sysroot") ([ "/etc" ] ++ persistentStoragePaths);
    };
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "systemd-tmpfiles --create --remove --boot ${configPath}";
      SuccessExitStatus = "DATAERR CANTCREAT";
      ImportCredential = [
        "tmpfiles.*"
        "login.motd"
        "login.issue"
        "network.hosts"
        "ssh.authorized_keys.root"
      ];
    };
  };

  mkRegularTmpfilesService = onBoot: configPath: persistentStoragePaths: restartTrigger: {
    wantedBy = lib.optionals onBoot [ "preservation.target" ];
    requiredBy = lib.optionals (!onBoot) [ "sysinit-reactivation.target" ];
    after = [
      "systemd-sysusers.service"
      "systemd-journald.service"
    ];
    before = [
      "shutdown.target"
    ]
    ++ lib.optionals onBoot [
      "sysinit.target"
      "initrd-switch-root.target"
      "systemd-tmpfiles-setup.service"
      "preservation.target"
    ]
    ++ lib.optionals (!onBoot) [
      "sysinit-reactivation.target"
      "systemd-tmpfiles-resetup.service"
    ];
    conflicts = [
      "shutdown.target"
    ]
    ++ lib.optionals onBoot [
      "initrd-switch-root.target"
    ];
    restartTriggers = lib.optionals (!onBoot) [ restartTrigger ];
    unitConfig = {
      DefaultDependencies = false;
      RefuseManualStop = onBoot;
      RequiresMountsFor = persistentStoragePaths;
    };
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "systemd-tmpfiles --create --remove ${lib.optionalString onBoot "--boot"} ${configPath}";
      SuccessExitStatus = "DATAERR CANTCREAT";
      ImportCredential = [
        "tmpfiles.*"
        "login.motd"
        "login.issue"
        "network.hosts"
        "ssh.authorized_keys.root"
      ];
    };
  };
}
