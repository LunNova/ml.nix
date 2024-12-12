{ stdenv, cmake, fetchFromGitHub, rocm-cmake }:
stdenv.mkDerivation (_final: {
  pname = "hipblas-common";
  version = "unstable";
  nativeBuildInputs = [ cmake rocm-cmake ];
  src = fetchFromGitHub {
    owner = "ROCm";
    repo = "hipBLAS-common";
    rev = "7c1566ba4628e777b91511242899b6df48555d04";
    hash = "sha256-eTwoAXH2HGdSAOLTZHJUFHF+c2wWHixqeMqr60KxJrc=";
  };
})
