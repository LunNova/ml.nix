{ lib
, stdenv
, fetchFromGitHub
, rocmUpdateScript
, cmake
, rocm-cmake
, clr
, python3
, tensile
, msgpack
, libxml2
, gtest
, gfortran
, openmp
, git
, amd-blis
, zstd
, clang-sysrooted
, hipblas-common
, hipblaslt
, python3Packages
, rocm-smi
, writeShellScriptBin
, buildTensile ? true
, buildTests ? true
, buildBenchmarks ? true
  #, tensileLogic ? "asm_full"
, tensileCOVersion ? "default"
  # https://github.com/ROCm/Tensile/issues/1757
  # Allows gfx101* users to use rocBLAS normally.
  # Turn the below two values to `true` after the fix has been cherry-picked
  # into a release. Just backporting that single fix is not enough because it
  # depends on some previous commits.
, tensileSepArch ? true
, tensileLazyLib ? true
  # `gfx940`, `gfx941` are not present in this list because they are early
  # engineering samples, and all final MI300 hardware are `gfx942`:
  # https://github.com/NixOS/nixpkgs/pull/298388#issuecomment-2032791130
  #
  # `gfx1012` is not present in this list because the ISA compatibility patches
  # would force all `gfx101*` GPUs to run as `gfx1010`, so `gfx101*` GPUs will
  # always try to use `gfx1010` code objects, hence building for `gfx1012` is
  # useless: https://github.com/NixOS/nixpkgs/pull/298388#issuecomment-2076327152
  # , gpuTargets ? [ "gfx900;gfx906:xnack-;gfx908:xnack-;gfx90a:xnack+;gfx90a:xnack-;gfx942;gfx1010;gfx1030;gfx1100;gfx1101;gfx1102" ]
  #, gpuTargets ? [ "gfx908;gfx90a;gfx942;gfx1010;gfx1030;gfx1100;gfx1101;gfx1102" ]
  #, gpuTargets ? [ "gfx908:xnack-;gfx90a:xnack+;gfx90a:xnack-;gfx1030" ]
, gpuTargets ? [ "gfx908" "gfx90a" "gfx942" "gfx1030" "gfx1100" ] # "gfx1030" "gfx1100" ]
}:

# FIXME: this derivation is ludicrously large, split into arch-specific derivations and symlink together?
let gpuTargets' = builtins.trace (lib.concatStringsSep ";" gpuTargets) (lib.concatStringsSep ";" gpuTargets); in
stdenv.mkDerivation (finalAttrs: {
  pname = "rocblas" + (if buildTests then "-tested" else "");
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
    repo = "rocBLAS";
    rev = "rocm-${finalAttrs.version}";
    hash = "sha256-IYcrVcGH4yZDkFZeNOJPfG0qsPS/WiH0fTSUSdo1BH4=";
  };

  nativeBuildInputs = [
    cmake
    # no ninja, it buffers console output and nix times out long periods of no output
    rocm-cmake
    clr
    git
    (writeShellScriptBin "amdclang++" ''
      exec clang++ "$@"
    '')
  ] ++ lib.optionals buildTensile [
    tensile
  ];

  buildInputs = [
    python3
    hipblas-common
    hipblaslt
  ] ++ lib.optionals buildTensile [
    zstd
    msgpack
    libxml2
    python3Packages.msgpack
    python3Packages.zstandard
  ] ++ lib.optionals buildTests [
    gtest
  ] ++ lib.optionals (buildTests || buildBenchmarks) [
    gfortran
    openmp
    amd-blis
    rocm-smi
  ] ++ lib.optionals (buildTensile || buildTests || buildBenchmarks) [
    python3Packages.pyyaml
  ];

  dontStrip = true;
  env.CFLAGS = "-g1 -gz";
  env.CXXFLAGS = "-g1 -gz";
  env.NIX_DISABLE_WRAPPER_INCLUDES = 1;
  env.TENSILE_ROCM_ASSEMBLER_PATH = "${clang-sysrooted}/bin/clang++";

  cmakeFlags = [
    "-DCMAKE_BUILD_TYPE=Release"
    "--log-level=debug"
    #"--debug-output"
    # "-DCMAKE_INTERPROCEDURAL_OPTIMIZATION=ON"
    "-DCMAKE_VERBOSE_MAKEFILE=ON"
    (lib.cmakeFeature "CMAKE_CXX_FLAGS" "-I${hipblas-common}/include") # FIX: -I${amd-blis}/include/blis 
    (lib.cmakeFeature "CMAKE_EXECUTE_PROCESS_COMMAND_ECHO" "STDERR")
    # This may change to using clang directly in future releases
    # (lib.cmakeFeature "CMAKE_C_COMPILER" "hipcc")
    # (lib.cmakeFeature "CMAKE_CXX_COMPILER" "hipcc")
    "-DCMAKE_Fortran_COMPILER=${lib.getBin gfortran}/bin/gfortran"
    "-DCMAKE_Fortran_COMPILER_AR=${lib.getBin gfortran}/bin/ar"
    "-DCMAKE_Fortran_COMPILER_RANLIB=${lib.getBin gfortran}/bin/ranlib"
    # FIXME: AR and RANLIB might need passed `--plugin=$(gfortran --print-file-name=liblto_plugin.so)`
    (lib.cmakeFeature "python" "python3")
    "-DSUPPORTED_TARGETS=${gpuTargets'}"
    "-DAMDGPU_TARGETS=${gpuTargets'}"
    "-DGPU_TARGETS=${gpuTargets'}"
    (lib.cmakeBool "BUILD_WITH_TENSILE" buildTensile)
    (lib.cmakeBool "ROCM_SYMLINK_LIBS" false)
    (lib.cmakeFeature "ROCBLAS_TENSILE_LIBRARY_DIR" "lib/rocblas")
    (lib.cmakeBool "BUILD_CLIENTS_TESTS" buildTests)
    (lib.cmakeBool "BUILD_CLIENTS_BENCHMARKS" buildBenchmarks)
    (lib.cmakeBool "BUILD_CLIENTS_SAMPLES" buildBenchmarks)
    (lib.cmakeBool "BUILD_OFFLOAD_COMPRESS" true)
    # rocblas header files are not installed unless we set this
    (lib.cmakeFeature "CMAKE_INSTALL_INCLUDEDIR" "include")
  ] ++ lib.optionals buildTensile [
    #"        -DCMAKE_PREFIX_PATH="${DEPS_DIR};${ROCM_PATH}" \
    "-DCPACK_SET_DESTDIR=OFF"
    "-DLINK_BLIS=ON"
    "-DTensile_CODE_OBJECT_VERSION=default"
    "-DTensile_LOGIC=asm_full"
    # "-DTensile_LOGIC=hip_lite"
    #"-DTensile_SEPARATE_ARCHITECTURES=ON"
    #"-DTensile_LAZY_LIBRARY_LOADING=ON"
    "-DTensile_LIBRARY_FORMAT=msgpack"
    (lib.cmakeBool "BUILD_WITH_PIP" false)
    # "-DTensile_COMPILER=hipcc"
    # "-DTensile_CODE_OBJECT_VERSION=V4"
    # "-DTensile_LOGIC=hip_lite"
    #(lib.cmakeFeature "Tensile_LOGIC" tensileLogic)
    #(lib.cmakeFeature "Tensile_CODE_OBJECT_VERSION" tensileCOVersion)
    (lib.cmakeBool "Tensile_SEPARATE_ARCHITECTURES" tensileSepArch)
    (lib.cmakeBool "Tensile_LAZY_LIBRARY_LOADING" tensileLazyLib)
    #(lib.cmakeBool "Tensile_PRINT_DEBUG" true)
    #"-DTENSILE_GPU_ARCHS=gfx908"
    #"-DTensile_VERBOSE=2"
  ] ++ lib.optionals (buildTests || buildBenchmarks) [
    (lib.cmakeFeature "CMAKE_CXX_FLAGS" "-I${amd-blis}/include/blis")
  ];

  preConfigure = ''
    makeFlagsArray+=("-l$((NIX_BUILD_CORES / 2))")
  '';

  passthru.amdgpu_targets = gpuTargets';

  patches = [
    # (fetchpatch {
    #   name = "Extend-rocBLAS-HIP-ISA-compatibility.patch";
    #   url = "https://github.com/GZGavinZhao/rocBLAS/commit/89b75ff9cc731f71f370fad90517395e117b03bb.patch";
    #   hash = "sha256-W/ohOOyNCcYYLOiQlPzsrTlNtCBdJpKVxO8s+4G7sjo=";
    # })
    # ./offload-compress.diff
  ];

  # Pass $NIX_BUILD_CORES to Tensile
  postPatch = ''
    substituteInPlace cmake/build-options.cmake \
      --replace-fail 'Tensile_CPU_THREADS ""' 'Tensile_CPU_THREADS "$ENV{NIX_BUILD_CORES}"'
    substituteInPlace CMakeLists.txt \
      --replace-fail "4.42.0" "4.43.0"
  '';

  passthru.updateScript = rocmUpdateScript {
    name = finalAttrs.pname;
    inherit (finalAttrs.src) owner;
    inherit (finalAttrs.src) repo;
  };

  # Reduces output size from >2GB with all arches to ~200MB
  postFixup = ''
    # Compress individual offload files - natively supported by AMD HSA
    # python3 ${./offload-compress.py} $out/

    # Compress .dat files (msgpack) - requires patched Tensile
    # standard Tensile can't load compressed files
    #pushd $out/lib/rocblas/library/
    #zstd -f --rm *.dat && for f in *.dat.zst; do mv "$f" "''${f%.zst}"; done
    #popd

    find $out -name '*.o' -delete
  '';

  enableParallelBuilding = true;
  requiredSystemFeatures = [ "big-parallel" ];

  meta = with lib; {
    description = "BLAS implementation for ROCm platform";
    homepage = "https://github.com/ROCm/rocBLAS";
    license = with licenses; [ mit ];
    maintainers = teams.rocm.members;
    platforms = platforms.linux;
    broken = versions.minor finalAttrs.version != versions.minor stdenv.cc.version || versionAtLeast finalAttrs.version "7.0.0";
  };
})
