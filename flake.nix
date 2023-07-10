{
  inputs = {
    flake-utils.url = "github:numtide/flake-utils";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, flake-utils, nixpkgs }:
    let systems = [ "x86_64-linux" ];
    in flake-utils.lib.eachSystem systems (system:
      let pkgs = nixpkgs.legacyPackages.${system};
      in rec {
        packages.tshock = pkgs.buildDotnetModule rec {
          pname = "TShock";
          version = "5.2.0"; # for Terraria 1.4.4.9

          src = pkgs.fetchFromGitHub {
            owner = "Pryaxis";
            repo = pname;
            rev = "v${version}";
            hash = "sha256-sy7n3JLz7i3I407Jw3xsHzVbdtK6HfyziIj8NzJZEzI=";
            fetchSubmodules = true;
          };
          projectFile = [
            "TShockAPI/TShockAPI.csproj"
            "TerrariaServerAPI/TerrariaServerAPI/TerrariaServerAPI.csproj"
            "TShockLauncher/TShockLauncher.csproj"
            "TShockInstaller/TShockInstaller.csproj"
            "TShockPluginManager/TShockPluginManager.csproj"
          ];
          nugetDeps = ./deps.nix;
        };
        packages.default = packages.tshock;

        apps.fetch-deps = {
          type = "app";
          program = "${packages.tshock.fetch-deps}";
        };
        apps.tshock = {
          type = "app";
          program = "${packages.tshock}/bin/TShock.Server";
        };

        apps.default = apps.tshock;

        formatter = pkgs.nixfmt;
      }) // {
        nixosModules.tshock = { config, lib }:
          let cfg = config.services.terraria;
          in {
            options = {
              services.tshock = {
                enable = lib.mkOption {
                  type = lib.types.bool;
                  default = false;
                };
              };
            };
            config = { };
          };
      };
}
