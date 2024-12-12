{ buildPythonPackage, fetchFromGitHub, setuptools, wheel, click }:
buildPythonPackage {
  name = "files-to-prompt";
  version = "unstable-2024-09-28";
  format = "pyproject";
  propagatedBuildInputs = [
    setuptools
    wheel
    click
  ];
  src = fetchFromGitHub {
    owner = "simonw";
    repo = "files-to-prompt";
    rev = "3332a864d3532afd429adf1aece9b27a812c9d8c";
    hash = "sha256-CIg5W8CztrUAKL8czCn8cc7WMKZMx5EdClbR0+7C1pU=";
  };
  meta.mainProgram = "files-to-prompt";
}
