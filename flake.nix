{
  description = "Basic Emacs 30.1 Configuration For A Weo";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  inputs.home-manager.url = "github:nix-community/home-manager";
  inputs.home-manager.inputs.nixpkgs.follows = "nixpkgs";

  outputs = { self, nixpkgs, home-manager }: {
    homeManagerModules.default = import ./emacs.nix;
  };
}
