{ lib
, stdenv
, fetchFromGitHub
, rocmUpdateScript
, cmake
, writeText
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "rocm-core";
  version = "6.3.0";

  src = fetchFromGitHub {
    owner = "ROCm";
    repo = "rocm-core";
    rev = "rocm-${finalAttrs.version}";
    hash = "sha256-Rhmenvml5LwfFkOvdG5yrA+JIk48CzYhj0QpJhcGw5s=";
  };

  nativeBuildInputs = [ cmake ];
  env.ROCM_LIBPATCH_VERSION = "60300";
  env.BUILD_ID = "nixos-${finalAttrs.env.ROCM_LIBPATCH_VERSION}";
  env.ROCM_BUILD_ID = "release-${finalAttrs.env.BUILD_ID}";
  cmakeFlags = [
    "-DROCM_LIBPATCH_VERSION=${finalAttrs.env.ROCM_LIBPATCH_VERSION}"
    "-DROCM_VERSION=${finalAttrs.version}"
    "-DBUILD_ID=${finalAttrs.env.BUILD_ID}"
  ];

  setupHook = writeText "setupHook.sh" ''
    export ROCM_LIBPATCH_VERSION="${finalAttrs.env.ROCM_LIBPATCH_VERSION}"
    export BUILD_ID="${finalAttrs.env.BUILD_ID}"
    export ROCM_BUILD_ID="${finalAttrs.env.ROCM_BUILD_ID}"
  '';

  passthru.ROCM_LIBPATCH_VERSION = finalAttrs.env.ROCM_LIBPATCH_VERSION;
  passthru.updateScript = rocmUpdateScript {
    name = finalAttrs.pname;
    inherit (finalAttrs.src) owner;
    inherit (finalAttrs.src) repo;
    page = "tags?per_page=4";
  };

  meta = with lib; {
    description = "Utility for getting the ROCm release version";
    homepage = "https://github.com/ROCm/rocm-core";
    license = with licenses; [ mit ];
    maintainers = teams.rocm.members;
    platforms = platforms.linux;
    broken = versions.minor finalAttrs.version != versions.minor stdenv.cc.version || versionAtLeast finalAttrs.version "7.0.0";
  };
})
