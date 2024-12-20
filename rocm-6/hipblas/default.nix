{ lib
, stdenv
, fetchFromGitHub
, rocmUpdateScript
, cmake
, rocm-cmake
, clr
, gfortran
, hipblas-common
, rocblas
, rocsolver
, rocsparse
, rocprim
, gtest
, lapack-reference
, writeShellScriptBin
, buildTests ? false
, buildBenchmarks ? false
, buildSamples ? false
}:

# Can also use cuBLAS
stdenv.mkDerivation (finalAttrs: {
  pname = "hipblas";
  version = "6.3.0";
  env.NIX_DEBUG = 1;
  env.NIX_DISABLE_WRAPPER_INCLUDES = 1;

  outputs = [
    "out"
  ] ++ lib.optionals buildTests [
    "test"
  ] ++ lib.optionals buildBenchmarks [
    "benchmark"
  ] ++ lib.optionals buildSamples [
    "sample"
  ];

  src = fetchFromGitHub {
    owner = "ROCm";
    repo = "hipBLAS";
    rev = "rocm-${finalAttrs.version}";
    #rev = "a4b23dec749d9d623f0e7699045f381ec3eddfab";
    hash = "sha256-Rz1KAhBUbvErHTF2PM1AkVhqo4OHldfSNMSpp5Tx9yk=";
  };

  postPatch = ''
    substituteInPlace library/CMakeLists.txt \
      --replace-fail "find_package(Git REQUIRED)" ""
  '';

  nativeBuildInputs = [
    cmake
    #ninja
    rocm-cmake
    clr
    gfortran
    (writeShellScriptBin "amdclang++" ''
      exec clang++ "$@"
    '')
  ];

  buildInputs = [
    rocblas
    rocprim
    rocsparse
    rocsolver
    # hipblaslt
    hipblas-common
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
    #"-DCMAKE_C_COMPILER=${lib.getBin clr}/bin/clang"
    "-DCMAKE_CXX_COMPILER=${lib.getBin clr}/bin/hipcc"
    #"-DCMAKE_CXX_COMPILER=${lib.getBin clr}/bin/amdclang++"
    # Manually define CMAKE_INSTALL_<DIR>
    # See: https://github.com/NixOS/nixpkgs/pull/197838
    "-DCMAKE_INSTALL_BINDIR=bin"
    "-DCMAKE_INSTALL_LIBDIR=lib"
    "-DCMAKE_INSTALL_INCLUDEDIR=include"
    "-DAMDGPU_TARGETS=${rocblas.amdgpu_targets}" # FIXME: 
  ] ++ lib.optionals buildTests [
    "-DBUILD_CLIENTS_TESTS=ON"
  ] ++ lib.optionals buildBenchmarks [
    "-DBUILD_CLIENTS_BENCHMARKS=ON"
  ] ++ lib.optionals buildSamples [
    "-DBUILD_CLIENTS_SAMPLES=ON"
  ];

  postInstall = lib.optionalString buildTests ''
    mkdir -p $test/bin
    mv $out/bin/hipblas-test $test/bin
  '' + lib.optionalString buildBenchmarks ''
    mkdir -p $benchmark/bin
    mv $out/bin/hipblas-bench $benchmark/bin
  '' + lib.optionalString buildSamples ''
    mkdir -p $sample/bin
    mv $out/bin/example-* $sample/bin
  '' + lib.optionalString (buildTests || buildBenchmarks || buildSamples) ''
    rmdir $out/bin
  '';

  passthru.updateScript = rocmUpdateScript {
    name = finalAttrs.pname;
    inherit (finalAttrs.src) owner;
    inherit (finalAttrs.src) repo;
  };

  meta = with lib; {
    description = "ROCm BLAS marshalling library";
    homepage = "https://github.com/ROCm/hipBLAS";
    license = with licenses; [ mit ];
    maintainers = teams.rocm.members;
    platforms = platforms.linux;
    broken = versions.minor finalAttrs.version != versions.minor stdenv.cc.version || versionAtLeast finalAttrs.version "7.0.0";
  };
})
