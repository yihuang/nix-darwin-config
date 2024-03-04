{
  description = "Example Darwin system flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nix-darwin.url = "github:LnL7/nix-darwin";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = inputs@{ self, nix-darwin, nixpkgs, home-manager }:
    let
      configuration = { pkgs, ... }:
        let
          hostPlatform = "aarch64-darwin";
          linuxSystem = builtins.replaceStrings [ "darwin" ] [ "linux" ] hostPlatform;

          darwin-builder = nixpkgs.lib.nixosSystem {
            system = linuxSystem;
            modules = [
              "${nixpkgs}/nixos/modules/profiles/macos-builder.nix"
              {
                virtualisation = {
                  host.pkgs = pkgs;
                  darwin-builder = {
                    diskSize = 100 * 1024; # 100GB
                    min-free = 50 * 1024 * 1024 * 1024; # 50GB
                    max-free = 80 * 1024 * 1024 * 1024; # 80GB
                    memorySize = 16 * 1024; # 16GB
                    workingDirectory = "/var/lib/darwin-builder";
                  };
                };
              }
            ];
          };
        in
        {
          # List packages installed in system profile. To search by name, run:
          # $ nix-env -qaP | grep wget
          environment.systemPackages =
            [
              pkgs.vim
            ];

          nix.distributedBuilds = true;
          nix.buildMachines = [{
            hostName = "linux-builder";
            sshUser = "builder";
            sshKey = "/etc/nix/builder_ed25519";
            system = linuxSystem;
            maxJobs = 4;
            supportedFeatures = [ "kvm" "benchmark" "big-parallel" ];
          }];
          launchd.daemons.darwin-builder = {
            command = "${darwin-builder.config.system.build.macos-builder-installer}/bin/create-builder";
            serviceConfig = {
              KeepAlive = true;
              RunAtLoad = true;
              StandardOutPath = "/var/log/darwin-builder.log";
              StandardErrorPath = "/var/log/darwin-builder.log";
            };
          };

          # Auto upgrade nix package and the daemon service.
          services.nix-daemon.enable = true;
          # nix.package = pkgs.nix;

          # Necessary for using flakes on this system.
          nix.settings = {
            experimental-features = "nix-command flakes";
            trusted-users = [
              "root"
              "huangyi"
            ];
            builders-use-substitutes = true;
          };

          # Create /etc/zshrc that loads the nix-darwin environment.
          programs.zsh.enable = true; # default shell on catalina
          # programs.fish.enable = true;

          # Set Git commit hash for darwin-version.
          system.configurationRevision = self.rev or self.dirtyRev or null;

          # Used for backwards compatibility, please read the changelog before changing.
          # $ darwin-rebuild changelog
          system.stateVersion = 4;

          # The platform the configuration will be used on.
          nixpkgs.hostPlatform = hostPlatform;
        };
    in
    {
      # Build darwin flake using:
      # $ darwin-rebuild build --flake .#huangyi-m3mpb
      darwinConfigurations."huangyi-m3mpb" = nix-darwin.lib.darwinSystem {
        modules = [
          configuration
          home-manager.darwinModules.home-manager
          {
            users.users.huangyi = {
              home = "/Users/huangyi";
              shell = "zsh";
            };
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.users.huangyi = {
              home.stateVersion = "24.05";
              programs.direnv.enable = true;
            };

            # Optionally, use home-manager.extraSpecialArgs to pass
            # arguments to home.nix
          }
        ];
      };

      # Expose the package set, including overlays, for convenience.
      darwinPackages = self.darwinConfigurations."huangyi-m3mpb".pkgs;
    };
}
