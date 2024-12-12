{ pkgs, lib, ... }:
# FIXME: this 
let
  # libffi = (pkgs.libffi.override {
  #   stdenv = rocmPackages.llvm.rocmClangStdenv;
  # }).overrideAttrs (old: {
  #   dontStrip = true;
  #   #env.NIX_CFLAGS_COMPILE = "-fsanitize=undefined -w -march=znver1 -mtune=znver1";
  #   cmakeFlags = (old.cmakeFlags or [ ]) ++ [
  #     "-DCMAKE_BUILD_TYPE=RelWithDebInfo"
  #   ];
  # });
  pythonInterp = (pkgs.python312.override {
    #inherit libffi;
    #stdenv = rocmPackages.llvm.rocmClangStdenv;
    enableOptimizations = true;
    reproducibleBuild = false;
    self = pythonInterp;
  }).overrideAttrs (old: {
    enableParallelBuilding = true;
    requiredSystemFeatures = (old.requiredSystemFeatures or [ ]) ++ [ "big-parallel" ];
    dontStrip = true;
    separateDebugInfo = false;
    disallowedReferences = [ ]; # debug info does point to openssl and that's ok
    configureFlags = old.configureFlags ++ [ "--with-undefined-behavior-sanitizer" ];
    # env.LDFLAGS = "-fsanitize=undefined";
    # env.CFLAGS = "-fsanitize=undefined -shared-libsan -frtti -frtti-data";
    # env.CXXFLAGS = "-fsanitize=undefined -shared-libsan -frtti -frtti-data";
    #env.NIX_CFLAGS_COMPILE = "-fsanitize=undefined -w -march=znver1 -mtune=znver1";
    env = old.env // {
      CFLAGS = "-frtti -fno-omit-frame-pointer -mno-omit-leaf-frame-pointer -g1";
    };
    cmakeFlags = (old.cmakeFlags or [ ]) ++ [
      "-DCMAKE_BUILD_TYPE=RelWithDebInfo"
      # "-DCMAKE_MODULE_LINKER_FLAGS_INIT=-fsanitize=undefined"
      # "-DCMAKE_EXE_LINKER_FLAGS_INIT=-fsanitize=undefined"
      # "-DCMAKE_SHARED_LINKER_FLAGS_INIT=-fsanitize=undefined"
      # "-DCMAKE_STATIC_LINKER_FLAGS_INIT=-fsanitize=undefined"
    ];
  });
  pythonPkgsOverridenInterp = pkgs.python312.override {
    packageOverrides = ps: prev: {
      #stdenv = rocmPackages.llvm.rocmClangStdenv;
      # pycparser = prev.pycparser.overridePythonAttrs (old: {
      #     doCheck = false;
      # });
      # websockets = prev.websockets.overridePythonAttrs (old: {
      #     doCheck = false;
      # });
      # meson = prev.meson.overridePythonAttrs (old: {
      #     doCheck = false;
      # });
      torch = ((prev.torch.override {
        stdenv = rocmPackages.llvm.rocmClangStdenv;
        #cudaSupport = true;
        rocmSupport = true;
        rocmPackages_5 = pkgs.rocmPackages;
        cudaSupport = false;
        useSystemNccl = true;
        #gpuTargets = ["8.9" "8.9+PTX"];
        MPISupport = true;
        effectiveMagma = pkgs.emptyDirectory;
        triton = ps.triton-no-cuda.overrideAttrs (old: {
          postPatch = old.postPatch + ''
            substituteInPlace third_party/amd/backend/compiler.py \
              --replace-fail '"/opt/rocm/llvm/bin/ld.lld"' "os.environ['ROCM_PATH']"' + "/llvm/bin/ld.lld"'
          '';
        });
      }).overridePythonAttrs (oldPyAttrs: {
        version = "2.6.0-nightly-20241203";
        src = oldPyAttrs.src.override {
          owner = "pytorch";
          repo = "pytorch";
          rev = "7851460668d6df096884697c5a750d75b0c35ea2";
          hash = "sha256-pizc2Q/IXclkrfRDu8IEbPP34yiGJlZZ9xQof3jeIDY=";
          fetchSubmodules = true;
        };
      })).overrideAttrs (old: {
        env.MPI_HOME = pkgs.mpich;
        enableParallelBuilding = true;
        nativeBuildInputs = old.nativeBuildInputs ++ [ pkgs.ninja pkgs.pkg-config ];
        buildInputs = old.buildInputs ++ [
          ps.six
          pkgs.openssl
          pkgs.rocmPackages.aotriton
          pkgs.rocmPackages.hiprand
          pkgs.rocmPackages.hipblaslt
          pkgs.rocmPackages.hipblas-common
          pkgs.amd-blis
          pkgs.mpich # FIXME: doesn't support GPU buffers
        ];
        cmakeFlags = [
          "-DAOTRITON_INSTALL_PREFIX=${pkgs.rocmPackages.aotriton}"
          "-DAOTRITON_INSTALLED_PREFIX=${pkgs.rocmPackages.aotriton}"
          # "-DCUDA_LIMIT_GPU_ARCHITECTURE=8.9"
          # "-DCUDA_ALL_GPU_ARCHITECTURES=8.9"
          # "-DCUDA_COMMON_GPU_ARCHITECTURES=8.9"
          "-DPYTHON_SIX_SOURCE_DIR=${ps.six.src}"
          "-DUSE_MPI=ON"
          "-DUSE_MAGMA=OFF"
          "-Wno-dev"
          "-DCMAKE_SUPPRESS_DEVELOPER_WARNINGS=ON"
          "-DCMAKE_VERBOSE_MAKEFILE=ON"
        ];
        postPatch = old.postPatch + ''
          echo HACK: removing third_party/composable_kernel and using system version, disabling submodule check
          rm -rf third_party/composable_kernel/
          substituteInPlace cmake/Dependencies.cmake \
            --replace-fail 'find_package(MPI)' 'find_package(MPI REQUIRED)'
          substituteInPlace setup.py \
            --replace-fail 'getenv("USE_SYSTEM_LIBS", False)' 'getenv("USE_SYSTEM_LIBS", True)'
          substituteInPlace aten/src/ATen/Context.cpp \
            --replace-fail '"gfx90a", "gfx940"' '"gfx908", "gfx90a", "gfx940"'
          substituteInPlace aten/src/ATen/native/cuda/Blas.cpp \
            --replace-fail '"gfx90a", "gfx940"' '"gfx908", "gfx90a", "gfx940"'
          substituteInPlace third_party/NNPACK/CMakeLists.txt --replace "PYTHONPATH=" 'PYTHONPATH=$ENV{PYTHONPATH}:'
          sed -i '2s;^;set(PYTHON_SIX_SOURCE_DIR ${ps.six.src})\n;' third_party/NNPACK/CMakeLists.txt
          sed -i '2s;^;set(CMAKE_SUPPRESS_DEVELOPER_WARNINGS ON CACHE INTERNAL "" FORCE)\n;' CMakeLists.txt

          CORE_LIM=$(( ''${NIX_LOAD_LIMIT:-''${CORE_LIM:-$(nproc)}} / 2 ))
          # Set HIPCC_JOBS with min and max constraints
          export CMAKE_BUILD_PARALLEL_LEVEL="$CORE_LIM"
          export HIPCC_JOBS=$(( CORE_LIM < 1 ? 1 : (CORE_LIM > 12 ? 12 : CORE_LIM) ))
          export HIPCC_JOBS_LINK=$(( CORE_LIM < 1 ? 1 : (CORE_LIM > 6 ? 6 : CORE_LIM) ))
          export HIPCC_COMPILE_FLAGS_APPEND="-O3 -Wno-format-nonliteral -parallel-jobs=$HIPCC_JOBS"
          export HIPCC_LINK_FLAGS_APPEND="-O3 -parallel-jobs=$HIPCC_JOBS_LINK"
        '';
        preConfigure = old.preConfigure + ''
          export PYTORCH_ROCM_ARCH="gfx908;gfx1100"
        '';
        env.CC = "hipcc";
        env.CXX = "hipcc";
        env.LD = "lld";
        # env.USE_SYSTEM_LIBS = 1; 
        USE_NNPACK = 1;
        env.CFLAGS = "-w";
        env.CXXFLAGS = "-w";
        env.USE_NINJA = 1;
        env.USE_MPI = 1;
        env.CMAKE_GENERATOR = "Ninja";
        env.PYTHON_SIX_SOURCE_DIR = ps.six.src;
        # env.TORCH_CUDA_ARCH_LIST = "8.9 8.9+PTX";
        # env.TORCH_NVCC_FLAGS = "-Xfatbin -compress-all";
        env.NIX_CFLAGS_COMPILE = "-Wno-everything -w -O3";
        env.AOTRITON_INSTALLED_PREFIX = "${pkgs.rocmPackages.aotriton}";
      });
    };
  };
  pythonPkgs = pythonPkgsOverridenInterp.pkgs // { python = pythonInterp; python3 = pythonInterp; };
  inherit (pkgs) rocmPackages;

  rocm-hip-libraries = pkgs.symlinkJoin {
    name = "rocm-hip-libraries-meta";

    paths = with rocmPackages; [
      rocblas
      hipfort
      rocm-core
      rocsolver
      # rocalution FIXME: build fails
      rocrand
      hipblas
      hipblaslt
      rocfft
      hipfft
      rccl
      rocsparse
      hipsparse
      hipsolver

      rocm-core
      rocminfo
      clr

      rocm-runtime
      rocm-core
      rocm-comgr
      llvm.openmp
    ];
  };
in
pkgs.mkShell {
  buildInputs = [
    pythonPkgs.python
    pythonPkgs.torch
    pythonPkgs.torchvision
    pythonPkgs.torchmetrics
    pythonPkgs.pytorch-lightning
    pythonPkgs.huggingface-hub
    pkgs.rocmPackages.rocm-smi
    pkgs.rocmPackages.clr
  ];
  # ROCM_PATH = "${pkgs.rocmPackages.clr}";
  ROCM_PATH = "${rocm-hip-libraries}";
  LD_LIBRARY_PATH = lib.makeLibraryPath [
    pkgs.rocmPackages.rocm-runtime
    pkgs.rocmPackages.rccl
    rocm-hip-libraries
  ];
  passthru.pytorch = pythonPkgs.torch;
  TORCHINDUCTOR_FX_GRAPH_CACHE = 1;
  TORCHINDUCTOR_AUTOGRAD_CACHE = 1;

  # nix shell/develop have this annoying behavior where they put /tmp in a transient dir
  # https://github.com/NixOS/nix/blob/be04e68b3472f188ddd56f99fbdac0f04ce914e8/src/nix/develop.cc#L371
  # but torch uses /tmp as a CACHE :L
  # TODO: feedback here: https://github.com/pytorch/pytorch/issues/121122
  shellHook = ''
    export TRITON_CACHE_DIR=$HOME/ml-cache/triton
    export TORCHINDUCTOR_CACHE_DIR=$HOME/ml-cache/torchinductor
    mkdir -p $TRITON_CACHE_DIR $TORCHINDUCTOR_CACHE_DIR
    export TMP=/tmp
    export TMPDIR=/tmp
    export TEMP=/tmp
    export TEMPDIR=/tmp
  '';
}
