{
  config,
  lib,
  ...
}: let
  l = lib // config.flake.lib;
  inherit (config.flake) overlays;
in {
  perSystem = {
    config,
    pkgs,
    lib,
    self',
    ...
  }: let
    commonOverlays = [
      (final: prev: {
        opencv-python-headless = final.opencv-python;
        opencv-python = final.opencv4;
      })
      (l.overlays.callManyPackages [
        ../../packages/mediapipe
        ../../packages/gguf
        ../../packages/spandrel
        ../../packages/colour-science
        ../../packages/rembg
        ../../packages/pixeloe
      ])
      # what gives us a python with the overlays actually applied
      overlays.python-pythonFinal
    ];

    python3Variants = {
      amd = l.overlays.applyOverlays pkgs.python311Packages (commonOverlays
        ++ [
          overlays.python-torchRocm
        ]);
      nvidia = l.overlays.applyOverlays pkgs.python311Packages (commonOverlays
        ++ [
          # FIXME: temporary standin for practical purposes.
          # They're prebuilt and come with cuda support.
          (final: prev: {
            torch = prev.torch-bin;
            torchaudio = prev.torchaudio-bin;
            torchvision = prev.torchvision-bin;
          })
          # use this when things stabilise and we feel ready to build the whole thing
          # overlays.python-torchCuda
        ]);
    };

    fetchFromHuggingFace = {
      owner,
      repo,
      sha256,
      rev ? "main",
      resource ? "", # the file to retrieve
    }:
      import <nix/fetchurl.nix> {
        inherit sha256;
        url = "https://huggingface.co/${owner}/${repo}/resolve/${rev}/${resource}";
      };

    # declare models as simply as:
    # "loras/example.safetensors" = { air = "urn:air:flux1:lora:civitai:<id>@<version>"; sha256 = "<hash>"; };
    # both AIR and sha256 is available on the civitai page of a model
    # AFAIK only civitai implements the spec as of now
    installByAir = let
      stripExt = name: builtins.concatStringsSep "" (builtins.match "(.+)\\..+" name);
    in
      attrs:
        builtins.listToAttrs (lib.mapAttrsToList (installPath: {
            air,
            sha256,
            authToken ? null,
          } @ args: let
            src = self'.legacyPackages.fetchair args;
            value = {
              inherit installPath src;
              # TODO: use AIR spec classification?
              base = src.meta.ecosystem;
              type = src.meta.format;
            };
          in {
            # "loras/some-flux1-lora-v1.safetensors" => some-flux1-lora-v1
            name = stripExt (baseNameOf installPath);
            inherit value;
          })
        attrs);
    models = import ./models {
      inherit fetchFromHuggingFace installByAir;
    };

    # we require a python3 with an appropriately overriden package set depending on GPU
    mkComfyUIVariant = python3: args:
      pkgs.callPackage ./package.nix ({inherit python3;} // args);

    # subset of `models` used by Krita plugin
    kritaModels = import ./models/krita-ai-plugin.nix models;
    # everything here needs to be parametrised over gpu vendor
    legacyPkgs = vendor: rec {
      customNodes = import ./custom-nodes {
        inherit lib models fetchFromHuggingFace;
        inherit (pkgs) stdenv fetchFromGitHub fetchzip writeText;
        python3Packages = python3Variants."${vendor}";
      };
      # subset of `customNodes` used by Krita plugin
      kritaCustomNodes = import ./custom-nodes/krita-ai-plugin.nix customNodes;
    };
    amd = legacyPkgs "amd";
    nvidia = legacyPkgs "nvidia";
  in {
    legacyPackages.comfyui = {
      inherit amd nvidia;
      inherit fetchFromHuggingFace installByAir;
      inherit (import ./models/meta.nix) base-models model-types;
      inherit models kritaModels;
    };

    packages = rec {
      comfyui-amd = mkComfyUIVariant python3Variants.amd.python {
        customNodes = {};
        models = {};
      };
      comfyui-nvidia = mkComfyUIVariant python3Variants.nvidia.python {
        customNodes = {};
        models = {};
      };
      krita-comfyui-server-amd = with amd;
        comfyui-amd.override {
          models = kritaModels.full;
          customNodes = kritaCustomNodes;
        };
      krita-comfyui-server-amd-minimal = with amd;
        comfyui-amd.override {
          models = kritaModels.required;
          customNodes = kritaCustomNodes;
        };
      krita-comfyui-server-nvidia = with nvidia;
        comfyui-nvidia.override {
          models = kritaModels.full;
          customNodes = kritaCustomNodes;
        };
      krita-comfyui-server-nvidia-minimal = with nvidia;
        comfyui-nvidia.override {
          models = kritaModels.required;
          customNodes = kritaCustomNodes;
        };
    };
  };
}
