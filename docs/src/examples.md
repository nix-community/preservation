# Examples

See [Configuration Options](./configuration-options.md) for all available options.

## Simple

```nix
# configuration.nix
{
  config,
  lib,
  pkgs,
  ...
}:
{
  preservation = {
    enable = true;
    preserveAt."/persistent" = {
      files = [
        # auto-generated machine ID
        { file = "/etc/machine-id"; inInitrd = true; }
      ];
      directories = [
        "/var/lib/systemd/timers"
        # NixOS user state
        "/var/lib/nixos"
        "/var/log"
      ];
    };
  };

  # systemd-machine-id-commit.service would fail, but it is not relevant
  # in this specific setup for a persistent machine-id so we disable it
  #
  # see the firstboot example below for an alternative approach
  systemd.suppressedSystemUnits = [ "systemd-machine-id-commit.service" ];

}
```

## Compatibility with systemd's `ConditionFirstBoot`

To preserve correct [systemd first boot semantics](https://www.freedesktop.org/software/systemd/man/latest/machine-id.html#First%20Boot%20Semantics),
additional configuration is required.

The following two configuration examples are compatible with first boot semantics.

### Symlink approach

Since systemd v258, systemd no longer creates missing symlink targets automatically
(see [this issue](https://github.com/nix-community/preservation/issues/22)).
Therefore, the target must exist ahead of time and contain an `uninitialized` machine-id.

```nix
# configuration.nix
{
  config,
  lib,
  pkgs,
  ...
}:
{
  preservation = {
    enable = true;
    preserveAt."/persistent" = {
      files = [
        # auto-generated machine ID
        {
          file = "/etc/machine-id";
          inInitrd = true;
          how = "symlink";
          configureParent = true;
          createLinkTarget = true;
        }
        # ...
      ];
      directories = [
        # ...
      ];
    };
  };

  boot.initrd.systemd.tmpfiles.settings.preservation."/sysroot/persistent/etc/machine-id".f = {
    argument = "uninitialized";
  };

  # let the service commit the transient ID to the persistent volume
  systemd.services.systemd-machine-id-commit = {
    unitConfig.ConditionPathIsMountPoint = [
      ""
      "/persistent/etc/machine-id"
    ];
    serviceConfig.ExecStart = [
      ""
      "systemd-machine-id-setup --commit --root /persistent"
    ];
  };
}
```


### Bind-mount approach

Alternatively, one can use a bind-mount. As with the symlink approach, the target
must exist ahead of time and contain an `uninitialized` machine-id.

However, note that since `/etc/machine-id` becomes a bind-mounted path,
`systemd-machine-id-commit` will see `ConditionPathIsMountPoint=/etc/machine-id`
as true on every boot.

To avoid committing on every boot, `ConditionFirstBoot=true` must be added.

```nix
# configuration.nix
{
  config,
  lib,
  pkgs,
  ...
}:
{
  preservation = {
    enable = true;
    preserveAt."/persistent" = {
      files = [
        # auto-generated machine ID
        { file = "/etc/machine-id"; inInitrd = true; }
        # ...
      ];
      directories = [
        # ...
      ];
    };
  };

  boot.initrd.systemd.tmpfiles.settings.preservation."/sysroot/persistent/etc/machine-id".f = {
    argument = "uninitialized";
  };

  systemd.services.systemd-machine-id-commit.unitConfig.ConditionFirstBoot = true;
}
```


## Complex

```nix
# configuration.nix
{
  config,
  lib,
  pkgs,
  ...
}:
{
  preservation = {
    # the module doesn't do anything unless it is enabled
    enable = true;

    preserveAt."/persistent" = {

      # preserve system directories
      directories = [
        "/etc/secureboot"
        "/var/lib/bluetooth"
        "/var/lib/fprint"
        "/var/lib/fwupd"
        "/var/lib/libvirt"
        "/var/lib/power-profiles-daemon"
        "/var/lib/systemd/coredump"
        "/var/lib/systemd/rfkill"
        "/var/lib/systemd/timers"
        "/var/log"
        { directory = "/var/lib/nixos"; inInitrd = true; }
      ];

      # preserve system files
      files = [
        { file = "/etc/machine-id"; inInitrd = true; }
        { file = "/etc/ssh/ssh_host_rsa_key"; how = "symlink"; configureParent = true; }
        { file = "/etc/ssh/ssh_host_ed25519_key"; how = "symlink"; configureParent = true; }
        "/var/lib/usbguard/rules.conf"

        # creates a symlink on the volatile root
        # creates an empty directory on the persistent volume, i.e. /persistent/var/lib/systemd
        # does not create an empty file at the symlink's target (would require `createLinkTarget = true`)
        { file = "/var/lib/systemd/random-seed"; how = "symlink"; inInitrd = true; configureParent = true; }
      ];

      # preserve user-specific files, implies ownership
      users = {
        butz = {
          commonMountOptions = [
            "x-gvfs-hide"
          ];
          directories = [
            { directory = ".ssh"; mode = "0700"; }
            ".config/syncthing"
            ".config/Element"
            ".local/state/nvim"
            ".local/state/wireplumber"
            ".local/share/direnv"
            ".local/state/nix"
            ".mozilla"
          ];
          files = [
            ".histfile"
          ];
        };
        root = {
          # specify user home when it is not `/home/${user}`
          home = "/root";
          directories = [
            { directory = ".ssh"; mode = "0700"; }
          ];
        };
      };
    };
  };

  # Create some directories with custom permissions.
  #
  # In this configuration the path `/home/butz/.local` is not an immediate parent
  # of any persisted file, so it would be created with the systemd-tmpfiles default
  # ownership `root:root` and mode `0755`. This would mean that the user `butz`
  # could not create other files or directories inside `/home/butz/.local`.
  #
  # Therefore systemd-tmpfiles is used to prepare such directories with
  # appropriate permissions.
  #
  # Note that immediate parent directories of persisted files can also be
  # configured with ownership and permissions from the `parent` settings if
  # `configureParent = true` is set for the file.
  systemd.tmpfiles.settings.preservation = {
    "/home/butz/.config".d = { user = "butz"; group = "users"; mode = "0755"; };
    "/home/butz/.local".d = { user = "butz"; group = "users"; mode = "0755"; };
    "/home/butz/.local/share".d = { user = "butz"; group = "users"; mode = "0755"; };
    "/home/butz/.local/state".d = { user = "butz"; group = "users"; mode = "0755"; };
  };

}
```
