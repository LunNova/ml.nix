{ lib
, stdenv
, fetchFromGitHub
, rocmUpdateScript
, cmake
, rocm-cmake
, rocm-smi
, clr
, perl
, hipify
, gtest
, chrpath
, rocprofiler
, rocprofiler-register
, writeShellScriptBin
, buildTests ? false
, gpuTargets ? [ ]
}:

let
  amdclang =
    writeShellScriptBin "amdclang++" ''
      exec clang++ "$@"
    '';
in
stdenv.mkDerivation (finalAttrs: {
  pname = "rccl";
  version = "6.3.0";

  outputs = [
    "out"
  ] ++ lib.optionals buildTests [
    "test"
  ];

  patches = [
    ./ignore-missing-kconf.diff
  ];

  src = fetchFromGitHub {
    owner = "ROCm";
    repo = "rccl";
    rev = "rocm-${finalAttrs.version}";
    hash = "sha256-aTRtQZ/DZiQB6UNQYGPNEcmxDX+nVh9x0aIXsVAAJts=";
  };

  nativeBuildInputs = [
    cmake
    rocm-cmake
    clr
    perl
    hipify
  ];

  buildInputs = [
    rocm-smi
    gtest
    rocprofiler
    rocprofiler-register
    # msccl # FIXME: optional dep for 6.3.0+
  ] ++ lib.optionals buildTests [
    chrpath
  ];

  cmakeFlags = [
    "-DROCM_PATH=${clr}"
    "-DCMAKE_CXX_COMPILER=${amdclang}/bin/amdclang++"
    "-DBUILD_BFD=OFF" # Can't get it to detect bfd.h
    "-DENABLE_MSCCL_KERNEL=OFF"
    "-DENABLE_MSCCLPP=OFF"
    # Manually define CMAKE_INSTALL_<DIR>
    # See: https://github.com/NixOS/nixpkgs/pull/197838
    "-DCMAKE_INSTALL_BINDIR=bin"
    "-DCMAKE_INSTALL_LIBDIR=lib"
    "-DCMAKE_INSTALL_INCLUDEDIR=include"
  ] ++ lib.optionals (gpuTargets != [ ]) [
    "-DAMDGPU_TARGETS=${lib.concatStringsSep ";" gpuTargets}"
  ] ++ lib.optionals buildTests [
    "-DBUILD_TESTS=ON"
  ];
  makeFlags = [ "-l16" ];

  env.CXXFLAGS = "-I${clr}/include";
  env.CCC_OVERRIDE_OPTIONS = "+-parallel-jobs=4";
  postPatch = ''
    patchShebangs src tools

    # Really strange behavior, `#!/usr/bin/env perl` should work...
    substituteInPlace CMakeLists.txt \
      --replace "\''$ \''${hipify-perl_executable}" "${perl}/bin/perl ${hipify}/bin/hipify-perl" \
       --replace-fail 'target_link_options(rccl PRIVATE -parallel-jobs=' "#" \
       --replace-fail 'target_compile_options(rccl PRIVATE -parallel-jobs=12)' ""
  '';

  postInstall = lib.optionalString buildTests ''
    mkdir -p $test/bin
    mv $out/bin/* $test/bin
    rmdir $out/bin
  '';

  passthru.updateScript = rocmUpdateScript {
    name = finalAttrs.pname;
    inherit (finalAttrs.src) owner;
    inherit (finalAttrs.src) repo;
  };

  meta = with lib; {
    description = "ROCm communication collectives library";
    homepage = "https://github.com/ROCm/rccl";
    license = with licenses; [ bsd2 bsd3 ];
    maintainers = teams.rocm.members;
    platforms = platforms.linux;
    broken = versions.minor finalAttrs.version != versions.minor stdenv.cc.version || versionAtLeast finalAttrs.version "7.0.0";
  };
})
