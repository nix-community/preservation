{
  inputs = {
    flake-parts.url = "github:hercules-ci/flake-parts";

    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nixpkgs-stable.url = "github:nixos/nixpkgs/nixos-24.11";
  };

  outputs = inputs:
    inputs.flake-parts.lib.mkFlake
      { inherit inputs; }
      {
        systems = [
          "x86_64-linux"
          "aarch64-linux"
        ];
      perSystem =
        {
          pkgs,
          lib,
          system,
          ...
        }:
        let
          checksForPkgs = pkgs: {
            default = pkgs.nixosTest (import ./basic.nix pkgs);
            firstboot = pkgs.nixosTest (import ./firstboot.nix pkgs);
            verity-image = pkgs.nixosTest (import ./appliance-image-verity.nix pkgs);
          };
          stableChecks = (
            lib.mapAttrs' (n: lib.nameValuePair "${n}-stable") (
              checksForPkgs inputs.nixpkgs-stable.legacyPackages.${system}
            )
          );
        in
        {
          checks = checksForPkgs pkgs // stableChecks;
        };
    };
}
