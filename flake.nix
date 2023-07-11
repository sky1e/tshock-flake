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
        nixosModules.tshock = { config, lib, options, pkgs, ... }:
          let
            cfg = config.services.tshock;
            inherit (lib) getBin mkIf mkOption types;
            opt = options.services.tshock;
            worldSizeMap = {
              small = 1;
              medium = 2;
              large = 3;
            };
            valFlag = name: val:
              lib.optionalString (val != null)
              ''-${name} "${lib.escape [ "\\" ''"'' ] (toString val)}"'';
            boolFlag = name: val: lib.optionalString val "-${name}";
            flags = [
              (valFlag "port" cfg.port)
              (valFlag "maxPlayers" cfg.maxPlayers)
              (valFlag "password" cfg.password)
              (valFlag "motd" cfg.messageOfTheDay)
              (valFlag "world" cfg.worldPath)
              (valFlag "autocreate"
                (builtins.getAttr cfg.autoCreatedWorldSize worldSizeMap))
              (valFlag "banlist" cfg.banListPath)
              (boolFlag "secure" cfg.secure)
              (boolFlag "noupnp" cfg.noUPnP)
            ];
            stopScript = pkgs.writeScript "tshock-stop" ''
              #!${pkgs.runtimeShell}

              if ! [ -d "/proc/$1" ]; then
                exit 0
              fi

              ${
                getBin pkgs.tmux
              }/bin/tmux -S ${cfg.dataDir}/tshock.sock send-keys Enter exit Enter
              ${getBin pkgs.coreutils}/bin/tail --pid="$1" -f /dev/null
            '';
          in {
            options = {
              services.tshock = {
                enable = mkOption {
                  type = types.bool;
                  default = false;
                  description = lib.mdDoc ''
                    If enabled, starts a Terraria server. The server can be connected to via `tmux -S ''${config.${opt.dataDir}}/tshock.sock attach`
                    for administration by users who are a part of the `tshock` group (use `C-b d` shortcut to detach again).
                  '';
                };

                port = mkOption {
                  type = types.port;
                  default = 7777;
                  description = lib.mdDoc ''
                    Specifies the port to listen on.
                  '';
                };

                maxPlayers = mkOption {
                  type = types.ints.u8;
                  default = 255;
                  description = lib.mdDoc ''
                    Sets the max number of players (between 1 and 255).
                  '';
                };

                password = mkOption {
                  type = types.nullOr types.str;
                  default = null;
                  description = lib.mdDoc ''
                    Sets the server password. Leave `null` for no password.
                  '';
                };

                messageOfTheDay = mkOption {
                  type = types.nullOr types.str;
                  default = null;
                  description = lib.mdDoc ''
                    Set the server message of the day text.
                  '';
                };

                worldPath = mkOption {
                  type = types.nullOr types.path;
                  default = null;
                  description = lib.mdDoc ''
                    The path to the world file (`.wld`) which should be loaded.
                    If no world exists at this path, one will be created with the size
                    specified by `autoCreatedWorldSize`.
                  '';
                };

                autoCreatedWorldSize = mkOption {
                  type = types.enum [ "small" "medium" "large" ];
                  default = "medium";
                  description = lib.mdDoc ''
                    Specifies the size of the auto-created world if `worldPath` does not
                    point to an existing world.
                  '';
                };

                banListPath = mkOption {
                  type = types.nullOr types.path;
                  default = null;
                  description = lib.mdDoc ''
                    The path to the ban list.
                  '';
                };

                secure = mkOption {
                  type = types.bool;
                  default = false;
                  description =
                    lib.mdDoc "Adds additional cheat protection to the server.";
                };

                noUPnP = mkOption {
                  type = types.bool;
                  default = false;
                  description =
                    lib.mdDoc "Disables automatic Universal Plug and Play.";
                };

                openFirewall = mkOption {
                  type = types.bool;
                  default = false;
                  description =
                    lib.mdDoc "Whether to open ports in the firewall";
                };

                dataDir = mkOption {
                  type = types.str;
                  default = "/var/lib/tshock";
                  example = "/srv/tshock";
                  description = lib.mdDoc
                    "Path to variable state data directory for tshock.";
                };
              };
            };
            config = mkIf cfg.enable {
              users.users.tshock = {
                description = "TShock server service user";
                group = "tshock";
                home = cfg.dataDir;
                createHome = true;
                #uid = config.ids.uids.terraria;
              };

              users.groups.tshock = { /*gid = config.ids.gids.tshock;*/ };

              systemd.services.tshock = {
                description = "TShock Server Service";
                wantedBy = [ "multi-user.target" ];
                after = [ "network.target" ];

                serviceConfig = {
                  User = "tshock";
                  Type = "forking";
                  GuessMainPID = true;
                  ExecStart = "${
                      getBin pkgs.tmux
                    }/bin/tmux -S ${cfg.dataDir}/tshock.sock new -d ${pkgs.tshock}/bin/TShock.Server ${
                      lib.concatStringsSep " " flags
                    }";
                  ExecStop = "${stopScript} $MAINPID";
                };

                postStart = ''
                  ${pkgs.coreutils}/bin/chmod 660 ${cfg.dataDir}/tshock.sock
                  ${pkgs.coreutils}/bin/chgrp tshock ${cfg.dataDir}/tshock.sock
                '';
              };

              networking.firewall = mkIf cfg.openFirewall {
                allowedTCPPorts = [ cfg.port ];
                allowedUDPPorts = [ cfg.port ];
              };

            };
          };
      };
}
