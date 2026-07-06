{
  description = "My Darwin system flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nix-darwin.url = "github:LnL7/nix-darwin";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs@{ self, nix-darwin, nixpkgs, home-manager }:
  let
    configuration = { pkgs, ... }: {
      # List packages installed in system profile. To search by name, run:
      # $ nix-env -qaP | grep wget
      environment.systemPackages =
        [
          pkgs.vim
          pkgs.direnv
          pkgs.sshs
          pkgs.glow
          pkgs.nushell
          pkgs.carapace
        ];
      services.nix-daemon.enable = true;
      nix.settings.experimental-features = "nix-command flakes";
      programs.zsh.enable = true;  # default shell on catalina
      system.configurationRevision = self.rev or self.dirtyRev or null;
      system.stateVersion = 4;
      nixpkgs.hostPlatform = "aarch64-darwin";
      security.pam.enableSudoTouchIdAuth = true;

      users.users.bishwa.home = "/Users/bishwa";
      home-manager.backupFileExtension = "backup";
      nix.configureBuildUsers = true;
      nix.useDaemon = true;

      # Ported from this machine's actual `defaults` values.
      system.defaults = {
        dock = {
          autohide = true;
          tilesize = 64;
          orientation = "left";
          mru-spaces = false;      # don't reorder Spaces (needed for the yabai/sketchybar setup)
          show-recents = false;
          wvous-br-corner = 1;     # bottom-right hot corner: disabled
        };
        finder = {
          FXPreferredViewStyle = "icnv";  # icon view
        };
        NSGlobalDomain = {
          AppleInterfaceStyle = "Dark";
          NSAutomaticCapitalizationEnabled = true;
        };
        trackpad = {
          Clicking = false;               # tap-to-click off
          TrackpadThreeFingerDrag = false;
        };
      };

      # Homebrew needs to be installed on its own (https://brew.sh).
      homebrew.enable = true;

      # Third-party taps required by the brews below.
      homebrew.taps = [
        "felixkratz/formulae"       # borders, sketchybar
        "koekeishiya/formulae"      # yabai, skhd
        "hashicorp/tap"             # vault
        "kreuzwerker/taps"          # m1-terraform-provider-helper
        "launchdarkly/tap"          # ldcli
        "skyhook-io/tap"            # radar
        "smudge/smudge"             # nightlight
      ];

      homebrew.brews = [
        # Window management (this repo's yabai/skhd setup)
        "koekeishiya/formulae/yabai"
        "koekeishiya/formulae/skhd"
        "felixkratz/formulae/sketchybar"
        "felixkratz/formulae/borders"

        # Shell / CLI experience
        "starship"
        "atuin"
        "zoxide"
        "z"
        "direnv"
        "fzf"
        "fd"
        "eza"
        "bat"
        "stow"
        "neovim"
        "ranger"
        "zsh-autosuggestions"
        "zsh-completions"

        # GNU coreutils & build tooling
        "coreutils"
        "findutils"
        "gnu-indent"
        "gnu-sed"
        "gnu-tar"
        "gnu-which"
        "gawk"
        "gpatch"
        "gzip"
        "binutils"
        "diffutils"
        "ed"
        "flex"
        "make"
        "autoconf"
        "util-linux"
        "wdiff"
        "less"
        "nano"
        "watch"
        "sponge"
        "choose-rust"
        "jid"
        "jq"
        "yq"

        # Languages / runtimes
        "node"
        "python@3.13"
        "rust"
        "uv"
        "pipx"

        # Kubernetes / cloud / devops
        "kubie"
        "kube-ps1"
        "k9s"
        "krew"
        "helm@3"
        "argocd"
        "cmctl"
        "operator-sdk"
        "oci-cli"
        "gcloud-cli"
        "terragrunt"
        "tfenv"
        "kreuzwerker/taps/m1-terraform-provider-helper"
        "hashicorp/tap/vault"
        "sops"
        "ansible"
        "launchdarkly/tap/ldcli"

        # Security tooling
        "checkov"
        "trivy"
        "prowler"
        "scoutsuite"
        "bcrypt"
        "pass"
        "pinentry-mac"
        "pam-reattach"   # Touch ID for sudo inside tmux/screen
        "pwgen"
        "zbar"

        # Networking / misc
        "gh"
        "wget"
        "httping"
        "iperf"
        "iperf3"
        "oha"
        "swaks"
        "telnet"
        "screen"
        "byobu"
        "tmux-xpanes"
        "wtfutil"
        "xh"
        "zip"
        "imagemagick"
        "skyhook-io/tap/radar"
        "smudge/smudge/nightlight"
      ];

      homebrew.casks = [
        # Terminals / editors / dev
        "iterm2"
        "visual-studio-code"
        "zed"
        "postman"
        "docker-desktop"
        "mongodb-compass"
        "sourcetree"
        "gitkraken"

        # Window mgmt / desktop
        "aerospace"
        "hammerspoon"
        "betterdisplay"
        "monitorcontrol"
        "lunar"
        "maccy"
        "shottr"
        "pearcleaner"

        # k8s / cloud
        "freelens"

        # Comms / apps
        "microsoft-teams"
        "termius"
        "spotify"
        "vlc"
        "obs"
        "bitwarden"

        # AI
        "chatgpt"
        "claude"
        "claude-code"

        # Security / auth
        "gpg-suite-no-mail"

        # Fonts / assets
        "font-hack-nerd-font"
        "font-sf-pro"
        "sf-symbols"

        # Updaters
        "microsoft-auto-update"
      ];
    };
  in
  {
    darwinConfigurations."MacBook-Pro" = nix-darwin.lib.darwinSystem {
      system = "aarch64-darwin";
      modules = [
	configuration
        home-manager.darwinModules.home-manager {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.users.bishwa = import ./home.nix;
        }
      ];
    };

    # Expose the package set, including overlays, for convenience.
    darwinPackages = self.darwinConfigurations."MacBook-Pro".pkgs;
  };
}
