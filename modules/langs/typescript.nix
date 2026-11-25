{
  flake.modules.homeManager.weomacs = {pkgs, ...}: {
    home.packages = [pkgs.typescript-language-server];
  };
}
