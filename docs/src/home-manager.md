# Home Manager

When [Home Manager](https://github.com/nix-community/home-manager) is used as a NixOS module,
each user can declare their own preservation in their Home Manager configuration.
The preservation module adds the option `preservation.preserveAt` to every Home Manager user and
forwards its contents to the NixOS option `preservation.preserveAt.<path>.users.<user>`.

Standalone Home Manager is not supported.

```nix
# home.nix
{ config, ... }:
{
  preservation.preserveAt."/persistent" = {
    directories = [
      # relative to the home directory
      ".rabbit_hole"
      # absolute paths must lie below the home directory
      "${config.xdg.dataHome}/someapp"
    ];
    files = [
      {
        file = "${config.xdg.configHome}/foo";
        mode = "0600";
      }
    ];
  };
}
```

Entries in `directories` and `files` take the same options as their counterparts under
`preservation.preserveAt.<path>.users.<user>`, see [Configuration Options](./configuration-options.md).
See [Options](./home-manager-options.md) for the Home Manager options.
They are checked by the NixOS module, errors name the Home Manager option they were defined in.

The read-only option `preservation.enable` reflects whether the NixOS module is enabled,
and is `false` outside of NixOS.
