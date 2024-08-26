# implementation of a fetcher based on the AIR spec https://github.com/civitai/civitai/wiki/AIR-%E2%80%90-Uniform-Resource-Names-for-AI
{
  lib,
  fetchurl,
}: let
  optStrFn = f: x: lib.optionalString (!(isNull x)) (f x);
  orNull = p: x:
    if p x
    then x
    else null;
  nullMap = f: x:
    if isNull x
    then null
    else f x;

  parseAirUrn = urn: let
    parts = let
      # the valid patterns for each component of the URN
      # https://github.com/civitai/civitai/wiki/AIR-%E2%80%90-Uniform-Resource-Names-for-AI#spec
      cs = "a-zA-Z0-9_\\-"; # valid characters for all components

      ecosystem = "[${cs}\\/]+";
      type = "[${cs}\\/]+";
      source = "[${cs}\\/]+";
      id = "[${cs}\\/]+";
      version = "[${cs}]+";
      format = "[${cs}]+";

      pat = "^urn:air:(${ecosystem}):(${type}):(${source}):(${id})@?(${version})?\\.?(${format})?$";
    in
      lib.pipe (builtins.split pat urn) [
        (nullMap (orNull (x: builtins.length x == 3)))
        (nullMap (x: builtins.elemAt x 1))
        (nullMap (orNull (x: builtins.length x == 6)))
        (x:
          if isNull x
          then throw "invalid AIR: ${urn}"
          else x)
      ];
    part = builtins.elemAt parts;
  in {
    ecosystem = part 0;
    type = part 1;
    source = part 2;
    model = part 3;
    version = part 4;
    format = part 5;
  };
in
  {
    air,
    sha256,
    authToken ? null,
    ...
  } @ args: let
    parsed = parseAirUrn air;
    params = ps: "?" + builtins.concatStringsSep "&" (builtins.filter (x: x != "") ps);
    url =
      if isNull parsed.version
      # not sure why the spec has version as optional when civitai's download urls seemingly rely on it
      then throw "a model version is required (...:id@<version>) in order to fetch this AI resource"
      else if parsed.source == "civitai"
      then
        # ex:
        # AIR: urn:air:flux1:lora:civitai:685229@766909
        # URL: https://civitai.com/api/download/models/766909?type=Model&format=SafeTensor
        "https://${parsed.source}.com/api/download/models/${parsed.version}"
        + (params [
          "type=Model" # TODO: what about configs, workflows, etc?
          (optStrFn (s: "format=${s}") parsed.format) # necessary?
        ])
      else
        # TODO: does huggingface implement the spec?
        lib.trivial.warn "support for ${parsed.source} as a source has not been added yet; trying the only known url template..."
        "https://${parsed.source}.com/api/download/models/${parsed.version}";
  in
    fetchurl
    ({
        inherit url;
        name = with parsed; "${ecosystem}-${type}-${model}" + (optStrFn (s: "-${s}") version) + (optStrFn (s: "-${s}") format);
      }
      // lib.optionalAttrs (!(isNull authToken)) {curlOptsList = ["--header" "Authorization: Bearer ${authToken}"];}
      // builtins.removeAttrs args ["air" "authToken"])
    // lib.optionalAttrs (parsed.source == "civitai") {
      meta =
        {
          inherit air;
          inherit (parsed) source ecosystem type;
          homepage = with parsed; "https://${source}.com/models/${model}?modelVersionId=${version}";
        }
        // lib.optionalAttrs (!(isNull parsed.format)) {inherit (parsed) format;};
    }
