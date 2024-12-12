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
, buildTests ? false
, buildExamples ? false
, gpuTargets ? [ "gfx908" "gfx1100" ] # gpuTargets = [ "gfx803" "gfx900" "gfx1030" ... ]
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "composable_kernel";
  version = "6.2.4";

  outputs = [
    "out"
  ] ++ lib.optionals buildTests [
    "test"
  ] ++ lib.optionals buildExamples [
    "example"
  ];

  env.NIX_DISABLE_WRAPPER_INCLUDES = 1;

  patches = [
    # ./0001-mark-kernels-maybe-unused.patch
  ];

  src = fetchFromGitHub {
    owner = "ROCm";
    repo = "composable_kernel";
    # rev = "rocm-${finalAttrs.version}";
    # hash = "sha256-shxr3y0r+L55kHyFQEVq7VgvR3nzqo0KksCdLG6Fqng=";
    rev = "50ee4267e27b875d149e642f4cebd47be1dc3b57"; #pytorch 2.6 nightly 20241203 uses this
    hash = "sha256-COkyf+FZzX6OdOPCHkP2bXsVvSXK9UR9s7RHWRtIXUE=";
  };

  nativeBuildInputs = [
    git
    cmake
    rocminfo
    rocm-cmake
    clr
    #clang-tools-extra
    zstd
    hipify
  ];

  buildInputs = [
    #  openmp
  ];

  enableParallelBuilding = true;
  env.ROCM_PATH = clr;
  env.HIP_CLANG_PATH = "${rocm-merged-llvm}/bin";

  cmakeFlags = [
    "-DCMAKE_MODULE_PATH=${clr}/hip/cmake"
    "-DCMAKE_BUILD_TYPE=Release"
    #"--debug"
    #"--trace"
    # Manually define CMAKE_INSTALL_<DIR>
    # See: https://github.com/NixOS/nixpkgs/pull/197838
    # "-DCMAKE_C_COMPILER=${lib.getBin clr}/bin/hipcc"
    # "-DCMAKE_CXX_COMPILER=${lib.getBin clr}/bin/hipcc"
    "-DCMAKE_INSTALL_BINDIR=bin"
    "-DCMAKE_INSTALL_LIBDIR=lib"
    "-DCMAKE_INSTALL_INCLUDEDIR=include"
    "-DBUILD_DEV=OFF"
    "-DROCM_PATH=${clr}"
    "-DHIP_ROOT_DIR=${clr}"
    "-DCMAKE_HIP_COMPILER_ROCM_ROOT=${clr}"
    # "-DCMAKE_CXX_COMPILER=${lib.getBin clr}/bin/hipcc"
    # "-DCMAKE_C_COMPILER=${lib.getBin clr}/bin/hipcc"
    # "-DCMAKE_CXX_COMPILER=hipcc"
  ] ++ lib.optionals (gpuTargets != [ ]) [
    "-DCMAKE_HIP_ARCHITECTURES=${lib.concatStringsSep ";" gpuTargets}"
    "-DGPU_ARCHS=${lib.concatStringsSep ";" gpuTargets}"
    "-DGPU_TARGETS=${lib.concatStringsSep ";" gpuTargets}"
    "-DAMDGPU_TARGETS=${lib.concatStringsSep ";" gpuTargets}"
  ] ++ lib.optionals buildTests [
    "-DGOOGLETEST_DIR=${gtest.src}" # Custom linker names
  ];

  # No flags to build selectively it seems...
  postPatch = ''
    export HIP_DEVICE_LIB_PATH=${rocm-device-libs}/amdgcn/bitcode
  '' + lib.optionalString (!buildTests) ''
    substituteInPlace CMakeLists.txt \
      --replace-fail "add_subdirectory(test)" ""
  '' + lib.optionalString (!buildExamples) ''
    substituteInPlace CMakeLists.txt \
      --replace-fail "add_subdirectory(example)" ""
  '' + ''
    substituteInPlace CMakeLists.txt \
      --replace-fail "add_subdirectory(profiler)" ""
    
    # Unconditionally compress offload code
    substituteInPlace library/src/tensor_operation_instance/gpu/CMakeLists.txt \
      --replace-fail 'target_compile_features(''${INSTANCE_NAME} PUBLIC)' 'target_compile_features(''${INSTANCE_NAME} PUBLIC)
      target_compile_options(''${INSTANCE_NAME} PRIVATE --offload-compress)
      '
    # cat library/src/tensor_operation_instance/gpu/CMakeLists.txt | head -n90
    # exit 1
  ''
  ;

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

  # Times out otherwise
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
