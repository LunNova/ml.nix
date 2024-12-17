{ pkgs, variant, ... }:

let
  nvda = pkgs.linuxPackages.nvidia_x11_production;
  inherit (pkgs) rocmPackages;
  rocmLibs = [
    rocmPackages.clr
    rocmPackages.hipblas
    rocmPackages.rocblas
    rocmPackages.rocsolver
    rocmPackages.rocsparse
    rocmPackages.rocm-device-libs
    rocmPackages.rocm-smi
  ];
  #rocmClang = pkgs.linkFarm "rocm-clang" { llvm = rocmPackages.llvm.clang; };
  rocmPath = pkgs.buildEnv {
    name = "rocm-path";
    paths = rocmLibs; # ++ [ rocmClang ];
  };
  hardware_deps = with pkgs;
    if variant == "CUDA" then [
      nvda
      cudatoolkit
      xorg.libXi
      xorg.libXmu
      freeglut
      xorg.libXext
      xorg.libX11
      xorg.libXv
      xorg.libXrandr
      zlib
      fontconfig

      # for xformers
      gcc
      (pkgs.koboldcpp.override {
        #cudaSupport = true;
        vulkanSupport = false;
        cublasSupport = true;
        clblastSupport = false;
        cudaArches = [ "sm_89" ];
      })
      (pkgs.llama-cpp.override {
        #cudaSupport = true;
        vulkanSupport = false;
        cudaSupport = true;
        #cublasSupport = true;
        #clblastSupport = false;
        rpcSupport = true;
        #cudaArches = [ "sm_89" ];
      })

    ] else if variant == "ROCM" then [
      # ((pkgs.koboldcpp.override {
      #   #cudaSupport = true;
      #   vulkanSupport = true;
      #   cublasSupport = false;
      #   clblastSupport = true;
      # })
      ((pkgs.llama-cpp.override {
        stdenv = pkgs.rocmPackages.llvm.rocmClangStdenv;
        rocmSupport = true;
        #cudaSupport = true;
        #vulkanSupport = true;
        cudaSupport = false;
        #cublasSupport = true;
        #clblastSupport = false;
        rpcSupport = true;
        #cudaArches = [ "sm_89" ];
      }).overrideAttrs (old: {
        env = (old.env or { }) // {
          HSA_OVERRIDE_GFX_VERSION = "9.0.8";
          NIX_CFLAGS_COMPILE = "-march=skylake -mtune=znver3";
          ROCM_PATH = "${rocmPath}";
        };
        #nativeBuildInputs = old.nativeBuildInputs ++ [ pkgs.clang ];
        buildInputs = old.buildInputs ++ [ rocmPackages.llvm.openmp pkgs.zstd ];
        dontStrip = true;
        cmakeFlags = (lib.filter (p: !(lib.strings.hasSuffix "hipcc" p)) old.cmakeFlags) ++ [
          "-DGGML_HIPBLAS=1"
          "-DGGML_CUDA_FORCE_MMQ=1"
          #	"-DGGML_HIP_UMA=1"
          "-DGGML_NATIVE=1"
          "-DGGML_LTO=1"
          #	"-DGGML_CUDA_NO_PEER_COPY=1"
          #"-DGGML_CUDA_FORCE_CUBLAS=1"
          #"-DGGML_SANITIZE_UNDEFINED=1"
          #	"-DGGML_SANITIZE_ADDRESS=1"
          #"-DLLAMA_SANITIZE_UNDEFINED=1"
          #	"-DLLAMA_SANITIZE_ADDRESS=1"
          "-DAMDGPU_TARGETS=gfx908;gfx1030;gfx1100"
          #	"-DCMAKE_BUILD_TYPE=Release"
          #	"-DCMAKE_C_COMPILER=clang" "-DCMAKE_CXX_COMPILE=clang++" 
        ];
      }))
      #rocmPackages.clr
      #rocmPackages.rocm-runtime
      #"${pkgs.rocmPackages.llvm.compiler-rt}/lib/linux/"
    ] else if variant == "CPU" then [
    ] else throw "You need to specify which variant you want: CPU, ROCm, or CUDA.";
  libs = hardware_deps ++ (with pkgs; [
    # stdenv.cc.cc.lib
    # stdenv.cc
    # libGLU
    # libGL

    #glib
  ]);
in
pkgs.mkShell rec {
  name = "ml-shell";
  buildInputs = with pkgs;
    libs ++ [
      unzip
      pciutils
      rocmPackages.llvm.bintools
      rocmPackages.rocminfo
      (pkgs.callPackage ./vkpeak { })
      #binutils
      #python310
      #ncurses5
      #gitRepo
      #gnupg
      #autoconf
      #curl
      #procps
      #gnumake
      #util-linux
      #m4
      #gperf
    ];
  #LD_PRELOAD="${pkgs.rocmPackages.llvm.compiler-rt}/lib/linux/libclang_rt.ubsan_standalone-x86_64.so";
  #UBSAN_OPTIONS="print_stacktrace=1";
  LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath libs;
  CUDA_PATH = pkgs.lib.optionalString (variant == "CUDA") pkgs.cudatoolkit;
  EXTRA_LDFLAGS = pkgs.lib.optionalString (variant == "CUDA") "-L${nvda}/lib";
}
