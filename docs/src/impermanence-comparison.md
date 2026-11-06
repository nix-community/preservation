# How does Preservation compare to [impermanence](https://github.com/nix-community/impermanence)

### Preservation does not attempt to be a very generic solution

Preservation tries to fill a specific niche.
For instance, Preservation does not support non-NixOS systems via home-manager, which is supported
by impermanence. Home Manager used as a NixOS module is supported, see [Home Manager](./home-manager.md).
See [Migration](./impermanence-migration.md) for more technical details.

### Preservation only generates static configuration

That is configuration for [systemd-tmpfiles](https://www.freedesktop.org/software/systemd/man/latest/systemd-tmpfiles.html)
and systemd [mount units](https://www.freedesktop.org/software/systemd/man/latest/systemd.mount.html).
This makes Preservation a potential candidate for state management on interpreter-less NixOS systems.

Impermanence makes use of NixOS activation scripts and custom systemd services with bash (at the point
of writing this), to create files and directories, setup mounts and configure ownership and permissions (see next point).

### Preservation must be precisely configured
There is no [special runtime logic](https://github.com/nix-community/impermanence/blob/23c1f06316b67cb5dabdfe2973da3785cfe9c34a/mount-file.bash#L31-L42)
  in place. This means that the user must define:
  * when the preservation should be set up: either in the initrd, or after (the default)
  * how the preservation should be set up: either by symlink, or bindmount (the default)
  * whether or not parent directories of the persisted files require special permissions

See [Migration](./impermanence-migration.md) for specifics that need to be considered when coming from an impermanence setup.

### Similar configuration

Preservation's configuration is based on, and very similar to that of impermanence. See [Migration](./impermanence-migration.md) for technical details.

### Global `enable` option

Preservation uses a global `enable` option, impermanence does not.

For thoughts on the `enable` option, see the discussion at <https://github.com/nix-community/impermanence/pull/171> and for available configuration options see [Configuration Options](./configuration-options.md).

### No generic `hideMounts` option

Preservation does not provide the same `hideMounts` option as impermanence, which would set the mount option `x-gvfs-hide` for bind-mounts.
Instead, preservation allows for the configuration of arbitrary mount options that are propagated to all bind-mounts, both on the top level
of a preserved prefix, and on the per-user level. This can be done via `commonMountOptions` and would for example enable users to choose
between `x-gvfs-hide` and `x-gdu.hide`.
