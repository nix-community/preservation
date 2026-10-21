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
              default = pkgs.testers.nixosTest (import ./basic.nix pkgs);
              firstboot = pkgs.testers.nixosTest (import ./firstboot.nix pkgs);
              verity-image = pkgs.testers.nixosTest (import ./appliance-image-verity.nix pkgs);
            };
          };
      };
}
