{
  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

  outputs = inputs: {
    packages.x86_64-linux =
      let
        pkgs = import inputs.nixpkgs { system = "x86_64-linux"; };

        mkOptionsManualMD =
          modules:
          let
            eval = pkgs.lib.evalModules {
              modules = modules ++ [
                (args: {
                  options._module.args = args.lib.mkOption { internal = true; };
                })
              ];
            };
            optionsDoc = pkgs.nixosOptionsDoc {
              inherit (eval) options;
              transformOptions =
                o:
                o
                // {
                  declarations = map (
                    declaration:
                    let
                      flakeOutPath = inputs.self.sourceInfo.outPath;
                      name = pkgs.lib.removePrefix "${flakeOutPath}/" declaration;
                    in
                    if pkgs.lib.hasPrefix "${flakeOutPath}/" declaration then
                      {
                        inherit name;
                        url = "https://github.com/nix-community/preservation/blob/main/${name}";
                      }
                    else
                      declaration
                  ) o.declarations;
                };
            };
          in
          optionsDoc.optionsCommonMark;
      in
      {
        optionsManualMD = mkOptionsManualMD [ ../options.nix ];

        homeManagerOptionsManualMD = mkOptionsManualMD [ ../home-manager-module.nix ];

        docs = pkgs.stdenv.mkDerivation {
          name = "preservation-docs";
          src = pkgs.lib.cleanSource ../.;
          nativeBuildInputs = [ pkgs.mdbook ];
          patchPhase = ''
            cat ${inputs.self.packages.x86_64-linux.optionsManualMD} > docs/src/configuration-options.md
            {
              echo "# Home Manager Options"
              echo
              cat ${inputs.self.packages.x86_64-linux.homeManagerOptionsManualMD}
            } > docs/src/home-manager-options.md
            cp README.md docs/src
          '';
          buildPhase = ''
            cd docs
            mdbook build
          '';
          installPhase = "cp -vr book $out";
        };
      };
  };
}
