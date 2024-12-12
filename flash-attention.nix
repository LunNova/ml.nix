{ buildPythonPackage, fetchFromGitHub, setuptools, wheel, click, torch }:
buildPythonPackage {
  name = "flash-attention";
  version = "unstable-2024-09-28-rocm-upstreaming";
  format = "pyproject";
  propagatedBuildInputs = [
    setuptools
    wheel
    click
    torch
  ];
  src = fetchFromGitHub {
    owner = "Dao-AILab";
    repo = "flash-attention";
    rev = "53a4f341634fcbc96bb999a3c804c192ea14f2ea";
    hash = "sha256-P0mEI4pD+pUOwYAUhsYDYKlTElB5dwmeVeh5KsCF994=";
  };
  meta.mainProgram = "files-to-prompt";
}
