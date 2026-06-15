{
  inputs = {
    flake-parts.url = "github:hercules-ci/flake-parts";

    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };

  outputs = inputs:
    inputs.flake-parts.lib.mkFlake
      { inherit inputs; }
      {
        systems = [
          "x86_64-linux"
          "aarch64-linux"
        ];
        perSystem = { pkgs, ... }:
          {
            checks = {
              default = pkgs.testers.runNixOSTest (import ./basic.nix pkgs);
              firstboot-bind-mount = pkgs.testers.runNixOSTest (import ./firstboot-bind-mount.nix pkgs);
              firstboot-symlink = pkgs.testers.runNixOSTest (import ./firstboot-symlink.nix pkgs);
              verity-image = pkgs.testers.runNixOSTest (import ./appliance-image-verity.nix pkgs);
            };
          };
      };
}
