{ lib
, stdenv
, fetchFromGitHub
, rocmUpdateScript
, cmake
, rocm-cmake
, rocm-merged-llvm
, clr
, rocm-device-libs
, rocminfo
, hipify
, git
, gtest
, zstd
, ninja
, buildTests ? false
, buildExamples ? false
  # FIXME: I can't get this to build for gfx1030
, gpuTargets ? [ "gfx908" "gfx90a" ] # gpuTargets = [ "gfx803" "gfx900" "gfx1030" ... ]
}:

stdenv.mkDerivation (finalAttrs: {
  pname =
    builtins.trace "composable_kernel: FIXME: ck is not building ck4inductor python package and can't be used as pytorch blas backend" "composable_kernel";
  # This version must be PEP 440 compatible because it's the version of the ck4inductor python package too
  version = "6.4.0a20241217";

  outputs = [
    "out"
  ] ++ lib.optionals buildTests [
    "test"
  ] ++ lib.optionals buildExamples [
    "example"
  ];

  patches = [
    # ./disable-amdgpu-inline.patch
    # for Gentoo this gives a significant speedup in build times
    # not observing speedup. possibly because our LLVM has been patched to fix amdgpu-early-inline-all issues?
  ];

  # PRed upstream with fix for ddp instances being built for gfx9
  # src = fetchFromGitHub {
  #   owner = "ROCm";
  #   repo = "composable_kernel";
  #   rev = "develop";
  #   hash = "sha256-MW5sxNDC4dfODIUPgex8W/fO0/8bLz4FEgxyB7OOIG8=";
  # };

  src = fetchFromGitHub {
    owner = "ROCm";
    repo = "composable_kernel";
    rev = "6ef8d3c295686b872d7e7a86621b68f765d98572";
    hash = "sha256-/TobMrC78z1itKVe1jZE/HkMoPN7EktsRBua5EAl4zs=";
  };

  nativeBuildInputs = [
    git
    cmake
    rocminfo
    rocm-cmake
    clr
    zstd
    hipify
    ninja
  ];

  buildInputs = [ ];

  enableParallelBuilding = true;
  requiredSystemFeatures = [ "big-parallel" ];
  env.ROCM_PATH = clr;
  env.HIP_CLANG_PATH = "${rocm-merged-llvm}/bin";

  cmakeFlags = [
    "-DCMAKE_MODULE_PATH=${clr}/hip/cmake"
    "-DCMAKE_BUILD_TYPE=Release"
    "-DCMAKE_POLICY_DEFAULT_CMP0069=NEW"
    "-DCMAKE_INTERPROCEDURAL_OPTIMIZATION=TRUE"
    # Manually define CMAKE_INSTALL_<DIR>
    # See: https://github.com/NixOS/nixpkgs/pull/197838
    # "-DDL_KERNELS=ON"
    # "-DCK_USE_CODEGEN=ON"
    "-DCMAKE_INSTALL_BINDIR=bin"
    "-DCMAKE_INSTALL_LIBDIR=lib"
    "-DCMAKE_INSTALL_INCLUDEDIR=include"
    "-DBUILD_DEV=OFF"
    "-DROCM_PATH=${clr}"
    "-DCMAKE_HIP_COMPILER_ROCM_ROOT=${clr}"

    # FP8 can build for 908/90a but very slow build
    # and produces unusably slow kernels that are huge
    "-DCK_USE_FP8_ON_UNSUPPORTED_ARCH=OFF"
  ] ++ lib.optionals (gpuTargets != [ ]) [
    "-DGPU_ARCHS=${lib.concatStringsSep ";" gpuTargets}"
  ] ++ lib.optionals buildTests [
    "-DGOOGLETEST_DIR=${gtest.src}" # Custom linker names
  ];

  # No flags to build selectively it seems...
  postPatch = ''
    export HIP_DEVICE_LIB_PATH=${rocm-device-libs}/amdgcn/bitcode
  '' + lib.optionalString (!buildTests) ''
    substituteInPlace CMakeLists.txt \
      --replace-fail "add_subdirectory(test)" ""
    substituteInPlace codegen/CMakeLists.txt \
      --replace-fail "include(ROCMTest)" ""
  '' + lib.optionalString (!buildExamples) ''
    substituteInPlace CMakeLists.txt \
      --replace-fail "add_subdirectory(example)" ""
  '' + ''
    substituteInPlace CMakeLists.txt \
      --replace-fail "add_subdirectory(profiler)" ""
  '';

  env.LDFLAGS = "-fPIC -Wl,--icf=all,--lto-O3,--as-needed,--gc-sections,--compress-debug-sections=zstd";
  env.CFLAGS = "-O3 -fPIC -flto -Wl,--icf=all,--lto-O3,--as-needed,--gc-sections,--compress-debug-sections=zstd";
  env.CXXFLAGS = "-O3 -fPIC -flto -Wl,--icf=all,--lto-O3,--as-needed,--gc-sections,--compress-debug-sections=zstd";
  # Clamp parallelism based on free memory at build start to avoid OOM
  preConfigure = ''
    alias ninja=samu
    export NINJA_SUMMARIZE_BUILD=1
    export NINJA_STATUS="[%r jobs | %P %f/%t @ %o/s | %w | ETA %W ] "
    MEM_GB_TOTAL=$(awk '/MemTotal/ { printf "%d \n", $2/1024/1024 }' /proc/meminfo)
    MEM_GB_FREE=$(awk '/MemAvailable/ { printf "%d \n", $2/1024/1024 }' /proc/meminfo)
    SWAP_GB_FREE=$(awk '/SwapFree/ { printf "%d \n", $2/1024/1024 }' /proc/meminfo)
    APPX_GB=$((MEM_GB_FREE + SWAP_GB_FREE / 4))
    APPX_GB=$((APPX_GB > MEM_GB_TOTAL ? MEM_GB_TOTAL : APPX_GB))
    MAX_CORES=$((1 + APPX_GB / 3))
    MAX_CORES_LINK=$((1 + APPX_GB / 7))
    MAX_CORES_LINK=$((MAX_CORES_LINK > NIX_BUILD_CORES ? NIX_BUILD_CORES : MAX_CORES_LINK))
    export NIX_BUILD_CORES="$((NIX_BUILD_CORES > MAX_CORES ? MAX_CORES : NIX_BUILD_CORES))"
    echo "Picked new core limits NIX_BUILD_CORES=$NIX_BUILD_CORES MAX_CORES_LINK=$MAX_CORES_LINK based on available mem: $APPX_GB GB"
    #export LDFLAGS="-Wl,--icf=all,--lto-O3,--as-needed,--gc-sections"
    cmakeFlagsArray+=(
      "-DCK_PARALLEL_LINK_JOBS=$MAX_CORES_LINK"
      "-DCK_PARALLEL_COMPILE_JOBS=$NIX_BUILD_CORES"
    )
    makeFlagsArray+=("-l$(nproc)")
    ninjaFlagsArray+=("-l$(nproc)")
  '';

  postInstall = ''
    zstd --rm $out/lib/libdevice_*_operations.a
  '' + lib.optionalString buildTests ''
    mkdir -p $test/bin
    mv $out/bin/test_* $test/bin
  '' + lib.optionalString buildExamples ''
    mkdir -p $example/bin
    mv $out/bin/example_* $example/bin
  '';

  passthru.updateScript = rocmUpdateScript {
    name = finalAttrs.pname;
    inherit (finalAttrs.src) owner;
    inherit (finalAttrs.src) repo;
  };

  meta = with lib; {
    description = "Performance portable programming model for machine learning tensor operators";
    homepage = "https://github.com/ROCm/composable_kernel";
    license = with licenses; [ mit ];
    maintainers = teams.rocm.members;
    platforms = platforms.linux;
    broken = versions.minor finalAttrs.version != versions.minor stdenv.cc.version || versionAtLeast finalAttrs.version "7.0.0";
  };
})
