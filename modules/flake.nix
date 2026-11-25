# Each feature module adds to flake.modules.homeManager.weomacs; this exposes the merged result.
{
  inputs,
  config,
  ...
}: {
  imports = [inputs.flake-parts.flakeModules.modules];

  systems = [];

  flake.homeManagerModules.default = config.flake.modules.homeManager.weomacs;
}
