{ lib
, stdenv
, fetchFromGitHub
, rocmUpdateScript
, pkg-config
, cmake
, libdrm
, numactl
, linuxHeaders
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "rocm-thunk";
  version = "6.2.2";

  src = fetchFromGitHub {
    owner = "ROCm";
    repo = "ROCT-Thunk-Interface";
    rev = "rocm-${finalAttrs.version}";
    hash = "sha256-IGzBDTr3oh0qnj7i9Vz/ryFWDej6fmyW22fTuTbgyRI=";
  };

  patches = [
    ./pkgconfig-numa.patch
  ];

  nativeBuildInputs = [
    pkg-config
    cmake
  ];

  buildInputs = [
    libdrm
    numactl
    linuxHeaders
  ];

  cmakeFlags = [
    "-DCMAKE_VERBOSE_MAKEFILE=ON"
    # Manually define CMAKE_INSTALL_<DIR>
    # See: https://github.com/NixOS/nixpkgs/pull/197838
    "-DCMAKE_INSTALL_BINDIR=bin"
    "-DCMAKE_INSTALL_LIBDIR=lib"
    "-DCMAKE_INSTALL_INCLUDEDIR=include"
  ];

  passthru.updateScript = rocmUpdateScript {
    name = finalAttrs.pname;
    inherit (finalAttrs.src) owner;
    inherit (finalAttrs.src) repo;
  };

  meta = with lib; {
    description = "Radeon open compute thunk interface";
    homepage = "https://github.com/ROCm/ROCT-Thunk-Interface";
    license = with licenses; [ bsd2 mit ];
    maintainers = with maintainers; [ lovesegfault ] ++ teams.rocm.members;
    platforms = platforms.linux;
    broken = versions.minor finalAttrs.version != versions.minor stdenv.cc.version || versionAtLeast finalAttrs.version "7.0.0";
  };
})