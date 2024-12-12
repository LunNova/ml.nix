{ system ? builtins.currentSystem }:
let flake = builtins.getFlake (toString ./.);
in flake.checks.${system}
# // {
#rocminfo = flake.legacyPackages.${system}.rocmPackages.rocminfo;
#}
