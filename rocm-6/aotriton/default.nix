{ lib
, stdenv
, fetchFromGitHub
, cmake
, rocm-cmake
, clr
, rocblas
, rocsolver
, gtest
, msgpack
, libxml2
, python3
, python3Packages
, openmp
, hipblas-common
, hipblas
, cudaPackages
, nlohmann_json
, triton-llvm
, rocmlir
, lapack-reference
, ninja
, ncurses
, libffi
, zlib
, zstd
, xz
, pkg-config
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
  py = python3.withPackages (ps: [ ps.pyyaml ps.distutils ps.setuptools ps.packaging ps.numpy ps.wheel ps.filelock ps.iniconfig ps.pluggy ps.pybind11 ]);
  gpuTargets' = lib.concatStringsSep ";" gpuTargets;
  compiler = "amdclang++";
  cFlags = "-O3 -DNDEBUG";
  # cudaRtIncludes = runCommandNoCC "cuda_includes" {} 
  #   ''
  #   mkdir -p $out
  #   cd $out 
  #   tar xf  ${cudaPackages.cuda_cudart.src} --strip-components=1
  # '';
  cudaRtIncludes = cudaPackages.cudatoolkit;
  triton-llvm' = builtins.trace "aotriton: TODO: confirm using same triton-llvm pinned hash as triton 3.2.x is ok" triton-llvm;
  # triton-llvm' = triton-llvm.overrideAttrs (_old: {
  #   doCheck = false;
  #   patches = [ ];
  #   src = fetchFromGitHub {
  #     owner = "llvm";
  #     repo = "llvm-project";
  #     rev = "bd9145c8c21334e099d51b3e66f49d51d24931ee";
  #     hash = "sha256-CSZkswB8KPdph8cGOayeKSBSQjSUsHGvqQ0TRN04KSQ=";
  #   };
  # });
in
{
  pname = "aotriton";
  version = "unstable-20241122";

  src = fetchFromGitHub {
    owner = "ROCm";
    repo = "aotriton";
    rev = "0.8b";
    hash = "sha256-C5Qr0EgV+pU6Hnmxqy76Nmryqr7qNkoE6iDcg9z35Hk=";
    fetchSubmodules = true;
  };
  env.CXX = compiler;
  env.ROCM_PATH = "${clr}";
  env.NIX_CC_USE_RESPONSE_FILE = 0;
  env.NIX_DISABLE_WRAPPER_INCLUDES = 1;
  requiredSystemFeatures = [ "big-parallel" ];

  outputs = [
    "out"
  ] ++ lib.optionals buildTests [
    "test"
  ] ++ lib.optionals buildBenchmarks [
    "benchmark"
  ] ++ lib.optionals buildSamples [
    "sample"
  ];

  # ROCM doesn't include an empty cuda.h?
  # It does in AMD's distribution
  # :confused:
  # https://github.com/pytorch/pytorch/issues/42430
  postPatch = ''
    echo "" > third_party/triton/third_party/nvidia/include/cuda.h
  '';

  doCheck = false;
  doInstallCheck = false;

  nativeBuildInputs = [
    cmake
    rocm-cmake
    pkg-config
    py
    clr
    clang-sysrooted
    #git
    #gfortran
    ninja
    (writeShellScriptBin "amdclang++" ''
      exec clang++ "$@"
    '')
  ];

  buildInputs = [
    rocblas
    rocsolver
    hipblas-common
    hipblas
    openmp
    libffi
    ncurses
    xz
    nlohmann_json
    rocmlir
    cudaRtIncludes

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

  env.TRITON_OFFLINE_BUILD = 1;
  env.LLVM_SYSPATH = "${triton-llvm'}"; #clang-sysrooted;
  env.JSON_SYSPATH = nlohmann_json;
  env.MLIR_DIR = "${triton-llvm'}/lib/cmake/mlir";
  # build time dep for header only, only needs source.
  env.TRITON_CUDACRT_PATH = cudaRtIncludes;
  env.TRITON_CUDART_PATH = cudaRtIncludes;
  env.CXXFLAGS = "-I/build/source/third_party/triton/third_party/nvidia/backend/include -I${cudaRtIncludes}/include";
  # env.NOIMAGE_MODE = 1;

  # Fix up header issues in triton: https://github.com/triton-lang/triton/pull/3985/files
  preConfigure = ''
    mkdir third_party/triton/third_party/nvidia/backend/include/
    cp ${cudaRtIncludes}/include/*.h third_party/triton/third_party/nvidia/backend/include/
    find third_party/triton -type f -exec sed -i 's|[<]cupti.h[>]|"cupti.h"|g' {} +
    find third_party/triton -type f -exec sed -i 's|[<]cuda.h[>]|"cuda.h"|g' {} +
    grep -ir cuda.h third_party/triton
    find third_party/triton -name 'cuda.h'
    # echo $TRITON_CUDACRT_PATH
    # ls $TRITON_CUDACRT_PATH
    # exit 1
    sed -i '2s;^;set(CMAKE_SUPPRESS_DEVELOPER_WARNINGS ON CACHE BOOL "ON")\n;' CMakeLists.txt
    sed -i '2s;^;set(CMAKE_VERBOSE_MAKEFILE ON CACHE BOOL "ON")\n;' CMakeLists.txt
    sed -i '2s;^;set(CMAKE_SUPPRESS_DEVELOPER_WARNINGS ON CACHE BOOL "ON")\n;' third_party/triton/CMakeLists.txt
    sed -i '2s;^;set(CMAKE_VERBOSE_MAKEFILE ON CACHE BOOL "ON")\n;' third_party/triton/CMakeLists.txt
    substituteInPlace third_party/triton/python/setup.py \
      --replace-fail "from distutils.command.clean import clean" "import setuptools;from distutils.command.clean import clean" \
      --replace-fail 'system == "Linux"' 'False'
    # sed -i 's|^download_and_copy|dict|g' third_party/triton/python/setup.py
    cmakeFlagsArray+=(
      '-DCMAKE_C_FLAGS_RELEASE=${cFlags}'
      '-DCMAKE_CXX_FLAGS_RELEASE=${cFlags}'
    )
    prependToVar cmakeFlags "-GNinja"
    mkdir -p /build/tmp-home
    export HOME=/build/tmp-home
  '';

  # From README:
  # Note: do not run ninja separately, due to the limit of the current build system,
  # ninja install will run the whole build process unconditionally.
  buildPhase = ''
    echo "Skipping build phase due to aotriton bug"
  '';

  installPhase = ''
    ninja -v install
  '';

  cmakeFlags = [
    #"--debug"
    #"--trace"
    "-Wno-dev"
    "-DAOTRITON_NOIMAGE_MODE=ON" # FIXME: Should be able to build with object code but generate_shim is failing
    "-DCMAKE_BUILD_TYPE=Release"
    "-DCMAKE_VERBOSE_MAKEFILE=ON"
    # "-DCMAKE_CXX_COMPILER=hipcc" # MUST be set because tensile uses this
    # "-DCMAKE_C_COMPILER=${lib.getBin clr}/bin/hipcc"
    "-DVIRTUALENV_PYTHON_EXENAME=${lib.getExe py}"
    "-DCMAKE_CXX_COMPILER=${compiler}"
    # Manually define CMAKE_INSTALL_<DIR>
    # See: https://github.com/NixOS/nixpkgs/pull/197838
    "-DCMAKE_INSTALL_BINDIR=bin"
    "-DCMAKE_INSTALL_LIBDIR=lib"
    "-DCMAKE_INSTALL_INCLUDEDIR=include"
    # "-DSUPPORTED_TARGETS=${gpuTargets'}"
    "-DAMDGPU_TARGETS=${gpuTargets'}"
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
  meta = with lib; {
    description = "ROCm BLAS marshalling library";
    homepage = "https://github.com/ROCm/hipBLAS";
    license = with licenses; [ mit ];
    maintainers = teams.rocm.members;
    platforms = platforms.linux;
    broken = versions.minor finalAttrs.version != versions.minor stdenv.cc.version || versionAtLeast finalAttrs.version "7.0.0";
  };
})
