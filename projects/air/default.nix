# AIR spec: https://github.com/civitai/civitai/wiki/AIR-%E2%80%90-Uniform-Resource-Names-for-AI
{...}: {
  perSystem = {
    pkgs,
    lib,
    ...
  }: let
    fetchurl = args:
      if builtins.hasAttr "curlOptsList" args
      then pkgs.fetchurl args
      else import <nix/fetchurl.nix> args;
  in {
    legacyPackages.fetchair = import ./fetcher.nix {inherit fetchurl lib;};
  };
}
