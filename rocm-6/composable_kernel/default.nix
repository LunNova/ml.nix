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
  pname = "composable_kernel";
  version = "6.4.0-unstable-20241217";

  outputs = [
    "out"
  ] ++ lib.optionals buildTests [
    "test"
  ] ++ lib.optionals buildExamples [
    "example"
  ];

  patches = [ ];

  # PRed upstream with fix for ddp instances being built for gfx9
  src = fetchFromGitHub {
    owner = "ROCm";
    repo = "composable_kernel";
    rev = "297e5bd6fe649f5da1e05a6ffed3579b7c2a8d29";
    hash = "sha256-qXolU33de5vgAI1ZLI7RpYpXSbeypQP1H4X5016P668=";
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
  env.ROCM_PATH = clr;
  env.HIP_CLANG_PATH = "${rocm-merged-llvm}/bin";

  cmakeFlags = [
    "-DCMAKE_VERBOSE_MAKEFILE=ON"
    "-DCMAKE_MODULE_PATH=${clr}/hip/cmake"
    "-DCMAKE_BUILD_TYPE=Release"
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

  # Set up parallel-jobs and compression, then reduce NIX_BUILD_CORES to account for
  # internal parallelism with parallel-jobs
  # echo HACK: Removing amdgpu-early-inline-all due to unusably high compile memory.
  # echo HACK: See https://github.com/llvm/llvm-project/issues/86332
  # substituteInPlace CMakeLists.txt \
  #   --replace-fail 'if(NOT WIN32 AND ''${hip_VERSION_FLAT} GREATER 600241132)' 'if(0)' \
  #   --replace-fail 'amdgpu-early-inline-all' 'invalid-arg-should-not-get-used -invalid'

  # echo HACK: disable CK_USE_AMD_V_DOT_DPP8_INLINE_ASM 1 by replacing in include/ck/ck.hpp to fix gfx908
  # substituteInPlace include/ck/ck.hpp \
  #   --replace-fail "CK_USE_AMD_V_DOT_DPP8_INLINE_ASM 1" "CK_USE_AMD_V_DOT_DPP8_INLINE_ASM 0"

  #export MALLOC_CONF="prof:true,lg_prof_sample:1,prof_accum:false,prof_prefix:jeprof.out"
  #export MALLOC_CONF="background_thread:true,narenas:2,dirty_decay_ms:5000,muzzy_decay_ms:5000"
  # export MALLOC_CONF="narenas:1,tcache:true,background_thread:true,dirty_decay_ms:1000,muzzy_decay_ms:1000"
  # export LD_PRELOAD="${jemalloc}/lib/libjemalloc.so";


  # Clamp parallelism based on free memory at build start to avoid OOM
  preConfigure = ''
    MEM_GB_FREE=$(awk '/MemFree/ { printf "%d \n", $2/1024/1024 }' /proc/meminfo)
    MAX_CORES=$((1 + MEM_GB_FREE / 10))
    MAX_CORES_LINK=$((1 + MEM_GB_FREE / 50))
    MAX_CORES_LINK=$((MAX_CORES_LINK > NIX_BUILD_CORES ? NIX_BUILD_CORES : MAX_CORES_LINK))
    export NIX_BUILD_CORES="$((1 + NIX_BUILD_CORES / 2))"
    export NIX_BUILD_CORES="$((NIX_BUILD_CORES > MAX_CORES ? MAX_CORES : NIX_BUILD_CORES))"
    echo "Picked new core limit NIX_BUILD_CORES=$NIX_BUILD_CORES based on available free mem: $MEM_GB_FREE GB"
    cmakeFlagsArray+=(
      "-DCK_PARALLEL_LINK_JOBS=$MAX_CORES_LINK"
      "-DCK_PARALLEL_COMPILE_JOBS=$NIX_BUILD_CORES"
    )
    makeFlagsArray+=("-j$NIX_BUILD_CORES" "-l$(nproc)")
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

  # This will use a lot of RAM per core, set a small --cores if you OOM.
  requiredSystemFeatures = [ "big-parallel" ];

  meta = with lib; {
    description = "Performance portable programming model for machine learning tensor operators";
    homepage = "https://github.com/ROCm/composable_kernel";
    license = with licenses; [ mit ];
    maintainers = teams.rocm.members;
    platforms = platforms.linux;
    broken = versions.minor finalAttrs.version != versions.minor stdenv.cc.version || versionAtLeast finalAttrs.version "7.0.0";
  };
})
