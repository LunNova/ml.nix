{ lib
, stdenv
, fetchFromGitHub
, rocmUpdateScript
, cmake
, rocm-cmake
, rocblas
, rocprim
, rocsparse
, clr
, fmt
, gtest
, gfortran
, lapack-reference
, buildTests ? false
, buildBenchmarks ? false
  #, gpuTargets ? ["gfx908:xnack-;gfx90a:xnack-;gfx90a:xnack+;gfx942;gfx1030;gfx1100;gfx1101"]
, gpuTargets ? [ "gfx908;gfx1030;gfx1100" ]
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "rocsolver";
  version = "6.3.0";

  outputs = [
    "out"
  ] ++ lib.optionals buildTests [
    "test"
  ] ++ lib.optionals buildBenchmarks [
    "benchmark"
  ];

  src = fetchFromGitHub {
    owner = "ROCm";
    repo = "rocSOLVER";
    rev = "rocm-${finalAttrs.version}";
    hash = "sha256-oExWcnQKcg9OVU1ebNNYQ4KKjC1EPoAZT/9TM3WLFHU=";
  };
  # env.CFLAGS = "-fsanitize=undefined";
  # env.CXXFLAGS = "-fsanitize=undefined";

  # FIXME: this is needed so build doesn't time out. multi job clang invocations for offload builds
  # take forever and only output anything between arches with -v on
  # FIXME: hits https://github.com/amcamd/Tensile/blob/35aad0223ca68d1005639107362a3a780c732f8f/Tensile/SolutionStructs.py#L1844
  # env.NIX_CFLAGS_COMPILE = "-v";
  # env.NIX_CXXFLAGS_COMPILE = "-v";

  nativeBuildInputs = [
    cmake
    # no ninja, it buffers console output and nix times out long periods of no output
    rocm-cmake
    clr
  ] ++ lib.optionals (buildTests || buildBenchmarks) [
    gfortran
  ];

  buildInputs = [
    # FIXME:
    # rocblas and rocsolver can't build in parallel
    # but rocsolver doesn't need rocblas' offload builds at runtime
    # could build against a rocblas-minimal?
    rocblas
    rocprim
    rocsparse
    fmt
  ] ++ lib.optionals buildTests [
    gtest
  ] ++ lib.optionals (buildTests || buildBenchmarks) [
    lapack-reference
  ];

  dontStrip = true;
  env.CFLAGS = "-g1 -gz";
  env.CXXFLAGS = "-g1 -gz";
  cmakeFlags = [
    "-DCMAKE_BUILD_TYPE=Release"
    "--log-level=debug"
    "-DCMAKE_VERBOSE_MAKEFILE=ON"
    "-DCMAKE_CXX_FLAGS=-Wno-switch" # Way too many warnings
    # Manually define CMAKE_INSTALL_<DIR>
    # See: https://github.com/NixOS/nixpkgs/pull/197838
    "-DCMAKE_INSTALL_BINDIR=bin"
    "-DCMAKE_INSTALL_LIBDIR=lib"
    "-DCMAKE_INSTALL_INCLUDEDIR=include"
  ] ++ lib.optionals (gpuTargets != [ ]) [
    "-DAMDGPU_TARGETS=${lib.concatStringsSep ";" gpuTargets}"
  ] ++ lib.optionals buildTests [
    "-DBUILD_CLIENTS_TESTS=ON"
  ] ++ lib.optionals buildBenchmarks [
    "-DBUILD_CLIENTS_BENCHMARKS=ON"
  ];

  postInstall = lib.optionalString buildTests ''
    mkdir -p $test/bin
    mv $out/bin/rocsolver-test $test/bin
  '' + lib.optionalString buildBenchmarks ''
    mkdir -p $benchmark/bin
    mv $out/bin/rocsolver-bench $benchmark/bin
  '' + lib.optionalString (buildTests || buildBenchmarks) ''
    rmdir $out/bin
  '';

  passthru.updateScript = rocmUpdateScript {
    name = finalAttrs.pname;
    inherit (finalAttrs.src) owner;
    inherit (finalAttrs.src) repo;
  };

  enableParallelBuilding = true;
  requiredSystemFeatures = [ "big-parallel" ];

  meta = with lib; {
    description = "ROCm LAPACK implementation";
    homepage = "https://github.com/ROCm/rocSOLVER";
    license = with licenses; [ bsd2 ];
    maintainers = teams.rocm.members;
    platforms = platforms.linux;
    timeout = 14400; # 4 hours
    maxSilent = 14400; # 4 hours
    broken = versions.minor finalAttrs.version != versions.minor stdenv.cc.version || versionAtLeast finalAttrs.version "7.0.0";
  };
})
