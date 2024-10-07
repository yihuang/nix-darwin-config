{
  description = "Example Darwin system flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    nix-darwin.url = "github:LnL7/nix-darwin";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";

    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    nix-index-database.url = "github:nix-community/nix-index-database";
    nix-index-database.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    inputs@{
      self,
      nix-darwin,
      nixpkgs,
      home-manager,
      ...
    }:
    let
      configuration =
        { pkgs, ... }:
        let
          hostPlatform = "aarch64-darwin";
        in
        {
          nix.linux-builder = {
            enable = true;
            maxJobs = 4;
            config = {
              virtualisation = {
                cores = 6;
                darwin-builder = {
                  diskSize = 200 * 1024; # 200GB
                  min-free = 100 * 1024 * 1024 * 1024; # 100GB
                  max-free = 160 * 1024 * 1024 * 1024; # 160GB
                  memorySize = 16 * 1024; # 16GB
                };
              };
            };
          };

          # List packages installed in system profile. To search by name, run:
          # $ nix-env -qaP | grep wget
          environment = {
            systemPackages = with pkgs; [
              neovim
              (callPackage ./gopls.nix { })
              nixfmt-rfc-style
            ];
            shellAliases = {
              vim = "nvim";
            };
            variables = {
              EDITOR = "vim";
            };
          };

          # Auto upgrade nix package and the daemon service.
          services.nix-daemon.enable = true;
          nix.package = pkgs.nixVersions.nix_2_24;

          # Necessary for using flakes on this system.
          nix.settings = {
            experimental-features = "nix-command flakes";
            trusted-users = [
              "@admin"
              "root"
              "huangyi"
            ];
            extra-platforms = [
              "x86_64-darwin"
            ];
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
      # $ darwin-rebuild build --flake .#dev
      darwinConfigurations.dev = nix-darwin.lib.darwinSystem {
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
          inputs.nix-index-database.darwinModules.nix-index
          { programs.nix-index-database.comma.enable = true; }
        ];
      };

      # Expose the package set, including overlays, for convenience.
      darwinPackages = self.darwinConfigurations.dev.pkgs;
    };
}
