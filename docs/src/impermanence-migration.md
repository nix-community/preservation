# Migration from impermanence to Preservation

This section lists individual differences between impermanence and
Preservation, to better understand them in context of a complete configuration
[Examples](./examples.md) may be helpful.

The following points need to be considered when migrating an existing
impermanence configuration to Preservation:

### Global `enable` switch

The module must be explicitly enabled by setting `preservation.enable` to `true`.

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

### Configuration of intermediate path components

Preservation does not handle any files or directories other than those specifically configured
to be preserved, and optionally their immediate parent directories (via `configureParent` and
the `parent` options).

All missing components of a preserved path that do not already exist, are created by
systemd-tmpfiles with default ownership `root:root` and mode `0755`, except for user-specific
paths, where intermediate components (up to and including the home directory) are created
with the user's ownership and mode `0755`.

Should such directories require different ownership or mode, the intended way to provision them
is directly via systemd-tmpfiles.

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
