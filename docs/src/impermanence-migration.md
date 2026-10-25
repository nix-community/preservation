# Migration from impermanence to Preservation

This section lists individual differences between impermanence and
Preservation, to better understand them in context of a complete configuration
[Examples](./examples.md) may be helpful.

The following points need to be considered when migrating an existing
impermanence configuration to Preservation:

### Global `enable` switch

The module must be explicitly enabled by setting `preservation.enable` to `true`.

### Handling of existing state

Coming from a setup with impermanence it is important to make sure existing persistent state is preserved
correctly, meaning the ownership and mode of preservation remains the same. There is no exhaustive list
of files and directories requiring special treatment but at least the following needs to be considered:

**SSH host keys**

Correct ownership and mode of SSH host keys is very important for sshd to accept connections.
Getting this wrong, e.g. not restricted enough, may cause your host to become inaccessible via SSH, forcing
you to use other means of logging into the machine.

The following config may be used to preserve the RSA and Ed25519 host keys with preservation:

```nix
preservation.preserveAt."/persistent".files = [
  { file = "/etc/ssh/ssh_host_rsa_key"; how = "symlink"; configureParent = true; }
  { file = "/etc/ssh/ssh_host_ed25519_key"; how = "symlink"; configureParent = true; }
];
```

The above config does not include access modes for the key files because the preservation
mode is `symlink` and the link's target is not touched by preservation without an explicit
`createLinkTarget = true`.

**Secrets and other files requiring special access modes**

Any files and directories that need to have a mode that differs from the default (`0644` for files
and `0755` for directories) must be configured explicitly to avoid having the default mode applied.

### When to persist

Files and directories that need to be persisted early, must be explicitly configured. For example `/etc/machine-id`:

This file needs to be persisted very early, by explicitly setting `inInitrd` to `true`:
```nix
preservation.preserveAt."/persistent".files = [
  { file = "/etc/machine-id"; inInitrd = true; }
];
```

### How to persist

The mode of preservation must be set explicitly for some files and directories.
This can be done by setting `how` to either `symlink` or `bindmount` (default).
For most cases the default is sufficient but sometimes a symlink may be needed,
for example `/var/lib/systemd/random-seed`.

This file is expected to not exist before it is initialized. A symlink can be
used to cause its creation to happen on the persistent volume:

```nix
preservation.preserveAt."/persistent".files = [
  {
    file = "/var/lib/systemd/random-seed";
    # create a symlink on the volatile volume
    how = "symlink";
    # prepare the preservation early during startup
    inInitrd = true;
  }
];
```

Note that no file is created at the symlink's target, unless `createLinkTarget` is set to `true`.

### Intermediate path components

Any directory that is not preserved itself but is a parent of a preserved file or directory
is called an intermediate path component here. Regarding the ownership and permissions of these
intermediate path components, the following needs to be considered.

#### Intermediate path components of user-specific files and directories

Parent directories of a preserved user-specific file or directory are created with the respective
user as their owner and permissions `0755`. This is the case for all intermediate path components
up to, but not including, the user's home directory.

**Example**

Consider the following preservation config:

```nix
preservation.preserveAt."/persistent".users.alice.directories = [
  ".local/state/nvim"
];
```

This config will cause preservation to configure a bind-mount for the subdirectory `nvim`, causing its
contents to be preserved. The intermediate path components `.local` and `state` will be created if
necessary, but their contents are not preserved. Owner is set to `alice`, group to alice's primary
group, i.e. `users.users.alice.group` and the mode is set to `0755`.


#### Intermediate path components of system-wide files and directories

For system-wide files and directories, missing components of a preserved path that do not already exist,
are created by systemd-tmpfiles with default ownership `root:root` and mode `0755`.

Should such directories require different ownership or mode, the intended way to create and configure them
is via systemd-tmpfiles directly.

**Example**

Consider a preserved file `/foo/bar/baz`:

```nix
preservation.preserveAt."/persistent".files = [
  { file = "/foo/bar/baz"; user = "baz"; group = "baz"; };
];
```

This would create the file with desired ownership on both the volatile and persistent volumes.
However, the parent directories that did not exist before, i.e. `/foo` and `/foo/bar`, are
created with ownership `root:root` and mode `0755`.

Preservations allows the configuration of immediate parents, so the permissions for `/foo/bar`
can be configured:
```nix
preservation.preserveAt."/persistent".files = [
  {
    file = "/foo/bar/baz"; user = "baz"; group = "baz";
    configureParent = true;
    parent.user = "baz";
    parent.group = "bar";
  };
];
```
Now the parent directory `/foo/bar` is configured with ownership `baz:bar`. But the first
path component `/foo` still has systemd-tmpfiles' default ownership and the configuration
becomes quite convoluted.

**Solution**

To create or configure intermediate path components of a persisted path, systemd-tmpfiles
may be used directly:

```nix
# configure preservation of single file
preservation.preserveAt."/persistent".files = [
  { file = "/foo/bar/baz"; user = "baz"; group = "bar"; };
];

# create and configure parents of preserved file on the volatile volume with custom permissions
# The Preservation module also uses `settings.preservation` here.
systemd.tmpfiles.settings.preservation = {
  "/foo".d = { user = "foo"; group = "bar"; mode = "0775"; };
  "/foo/bar".d = { user = "bar"; group = "bar"; mode = "0755"; };
};
```

See [tmpfiles.d(5)](https://www.freedesktop.org/software/systemd/man/latest/tmpfiles.d.html)
for available configuration options.

### Applying the migration

Apply the first configuration that uses Preservation instead of impermanence with
`nixos-rebuild boot` and a reboot, rather than with `nixos-rebuild switch`.

On a switch, NixOS stops the units and unmounts the filesystems of the running system
that the new configuration no longer declares. After the migration, that is everything
impermanence set up:

- Each persisted file has a `persist-*.service` unit. Stopping it runs its `ExecStop`,
  which removes the symlink, or unmounts and removes the bind-mounted file, at the file's
  path, e.g. `/etc/machine-id`.
- Each persisted directory is a bind mount, declared in `/etc/fstab` or, in impermanence
  since September 2025, as a mount unit, and is unmounted.

Entries with `inInitrd = true`, such as `/etc/machine-id` or `/var/log`, are only set up
in the initrd, so they stay missing from the running system until the next boot. A
directory that is in use can also fail to unmount, which fails the switch.
