{ system ? builtins.currentSystem }:
let flake = builtins.getFlake (toString ./.);
in flake.legacyPackages.${system} // { recurseForDerivations = true; }
