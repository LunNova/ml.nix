{ lib
, stdenv
, fetchFromGitHub
, cmake
, rocm-cmake
, clr
, gfortran
, gtest
, msgpack
, libxml2
, python3
, python3Packages
, openmp
, hipblas-common
, tensile
, lapack-reference
, ncurses
, libffi
, zlib
, zstd
, clang-sysrooted
, writeShellScriptBin
, rocmUpdateScript
, buildTests ? false
, buildBenchmarks ? false
, buildSamples ? false
, gpuTargets ? [ "gfx908" ] #[  ]
}:

stdenv.mkDerivation (finalAttrs:
let
  tensile' = (tensile.override { isTensileLite = true; }).overrideAttrs {
    inherit (finalAttrs) src;
    sourceRoot = "${finalAttrs.src.name}/tensilelite";
    env.ROCM_PATH = "${clr}";
  };
  py = python3.withPackages (ps: [ ps.pyyaml ps.setuptools ps.packaging ]);
  gpuTargets' = lib.concatStringsSep ";" gpuTargets;
  compiler = "hipcc"; # FIXME: amdclang++ in future
  cFlags = "-I${msgpack}/include"; # FIXME: cmake files need patched to include this properly
in
{
  # build will fail with llvm libcxx, must use gnu libstdcxx
  # https://github.com/llvm/llvm-project/issues/98734
  pname = "hipblaslt";
  version = "6.3.0";

  src = fetchFromGitHub {
    owner = "ROCm";
    repo = "hipBLASLt";
    rev = "rocm-${finalAttrs.version}";
    hash = "sha256-TTxjFQE53PcDA3Yw31h9j2nXpuB1OnHLOPX+d6K2MS8=";
  };
  env.CXX = compiler;
  env.ROCM_PATH = "${clr}";
  env.TENSILE_ROCM_ASSEMBLER_PATH = "${clang-sysrooted}/bin/clang++";
  env.NIX_CC_USE_RESPONSE_FILE = 0;
  env.NIX_DISABLE_WRAPPER_INCLUDES = 1;
  env.TENSILE_GEN_ASSEMBLY_TOOLCHAIN = "${clang-sysrooted}/bin/clang++";
  requiredSystemFeatures = [ "big-parallel" ];

  patches = [
    ./ext-op-first.diff
    # ./alpha_1_init_fix.patch # libcxx bug workaround - 
  ];

  outputs = [
    "out"
  ] ++ lib.optionals buildTests [
    "test"
  ] ++ lib.optionals buildBenchmarks [
    "benchmark"
  ] ++ lib.optionals buildSamples [
    "sample"
  ];

  postPatch = ''
    rm -rf tensilelite
      #   sed -i '1i variable_watch(__CMAKE_C_COMPILER_OUTPUT)' CMakeLists.txt
      # sed -i '1i variable_watch(__CMAKE_CXX_COMPILER_OUTPUT)' CMakeLists.txt
      # sed -i '1i variable_watch(OUTPUT)' CMakeLists.txt
    mkdir -p build/Tensile/library
    # substituteInPlace tensilelite/Tensile/Ops/gen_assembly.sh \
    #   --replace-fail '. ''${venv}/bin/activate' 'set -x; . ''${venv}/bin/activate'
    # git isn't needed and we have no .git
    substituteInPlace cmake/Dependencies.cmake \
      --replace-fail "find_package(Git REQUIRED)" ""
    substituteInPlace CMakeLists.txt \
      --replace-fail "include(virtualenv)" "" \
      --replace-fail "virtualenv_install(\''${Tensile_TEST_LOCAL_PATH})" "" \
      --replace-fail "virtualenv_install(\''${CMAKE_SOURCE_DIR}/tensilelite)" "" \
      --replace-fail 'find_package(Tensile 4.33.0 EXACT REQUIRED HIP LLVM OpenMP PATHS "''${INSTALLED_TENSILE_PATH}")' "find_package(Tensile)"
    if [ -f library/src/amd_detail/rocblaslt/src/kernels/compile_code_object.sh ]; then
      substituteInPlace library/src/amd_detail/rocblaslt/src/kernels/compile_code_object.sh \
        --replace-fail '${"\${rocm_path}"}/bin/' ""
    fi
    echo $CFLAGS
    echo $CXXFLAGS
  '';

  doCheck = false;
  doInstallCheck = false;

  nativeBuildInputs = [
    cmake
    rocm-cmake
    py
    clr
    #git
    gfortran
    #ninja
    (writeShellScriptBin "amdclang++" ''
      exec clang++ "$@"
    '')
  ];

  buildInputs = [
    # rocblas
    # rocsolver
    hipblas-common
    # hipblas
    tensile'
    openmp
    libffi
    ncurses

    # Tensile deps - not optional, building without tensile isn't actually supported
    msgpack # FIXME: not included in cmake!
    libxml2
    python3Packages.msgpack
    zlib
    zstd
    #python3Packages.joblib
  ] ++ lib.optionals buildTests [
    gtest
  ] ++ lib.optionals (buildTests || buildBenchmarks) [
    lapack-reference
  ];

  preConfigure = ''
    cmakeFlagsArray+=(
      '-DCMAKE_C_FLAGS_RELEASE=${cFlags}'
      '-DCMAKE_CXX_FLAGS_RELEASE=${cFlags}'
    )
  '';

  cmakeFlags = [
    #"--debug"
    #"--trace"
    "-Wno-dev"
    "-DCMAKE_BUILD_TYPE=Release"
    "-DCMAKE_VERBOSE_MAKEFILE=ON"
    # "-DCMAKE_CXX_COMPILER=hipcc" # MUST be set because tensile uses this
    # "-DCMAKE_C_COMPILER=${lib.getBin clr}/bin/hipcc"
    "-DVIRTUALENV_PYTHON_EXENAME=${lib.getExe py}"
    "-DTENSILE_USE_HIP=ON"
    "-DTENSILE_BUILD_CLIENT=OFF"
    # "-DTENSILE_USE_LLVM=ON"
    "-DTENSILE_USE_FLOAT16_BUILTIN=ON"
    "-DCMAKE_CXX_COMPILER=${compiler}"
    # Manually define CMAKE_INSTALL_<DIR>
    # See: https://github.com/NixOS/nixpkgs/pull/197838
    "-DCMAKE_INSTALL_BINDIR=bin"
    "-DCMAKE_INSTALL_LIBDIR=lib"
    "-DCMAKE_INSTALL_INCLUDEDIR=include"
    "-DHIPBLASLT_ENABLE_MARKER=Off"
    # FIXME what are the implications of hardcoding this?
    "-DTensile_CODE_OBJECT_VERSION=V5"
    "-DTensile_COMPILER=${compiler}" # amdclang++ in future
    # "-DSUPPORTED_TARGETS=${gpuTargets'}"
    "-DAMDGPU_TARGETS=${gpuTargets'}"
    "-DTensile_LIBRARY_FORMAT=msgpack"
    # "-DGPU_TARGETS=${gpuTargets'}"
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
  passthru.tensilelite = tensile';
  meta = with lib; {
    description = "ROCm BLAS marshalling library";
    homepage = "https://github.com/ROCm/hipBLAS";
    license = with licenses; [ mit ];
    maintainers = teams.rocm.members;
    platforms = platforms.linux;
    broken = versions.minor finalAttrs.version != versions.minor stdenv.cc.version || versionAtLeast finalAttrs.version "7.0.0";
  };
})
