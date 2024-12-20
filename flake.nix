{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachSystem flake-utils.lib.defaultSystems (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
          config.allowBroken = true;
          overlays = [
            (f: _super:
              let rocm = f.callPackage ./rocm-6 { }; in {
                rocmPackages_6 = rocm;
                rocmPackages = rocm;
                # FIXME: we need to patch magma to use rocm 6, for now can't use it as pytorch dep
              })
          ];
        };
        lib = import ./lib.nix { bootstrapLib = nixpkgs.lib; };
        libffi = (pkgs.libffi.override {
          stdenv = rocmPackages.llvm.rocmClangStdenv;
        }).overrideAttrs (old: {
          dontStrip = true;
          #env.NIX_CFLAGS_COMPILE = "-fsanitize=undefined -w -march=znver1 -mtune=znver1";
          cmakeFlags = (old.cmakeFlags or [ ]) ++ [
            "-DCMAKE_BUILD_TYPE=RelWithDebInfo"
          ];
        });
        pythonInterp = (pkgs.python312.override {
          inherit libffi;
          stdenv = rocmPackages.llvm.rocmClangStdenv;
          enableOptimizations = true;
          reproducibleBuild = false;
          self = pythonInterp;
        }).overrideAttrs (old: {
          dontStrip = true;
          separateDebugInfo = false;
          disallowedReferences = [ ]; # debug info does point to openssl
          configureFlags = old.configureFlags ++ [ "--with-undefined-behavior-sanitizer" ];
          env = old.env // {
            CFLAGS = "-fno-sanitize=function -frtti -frtti-data";
          };
          cmakeFlags = (old.cmakeFlags or [ ]) ++ [
            "-DCMAKE_BUILD_TYPE=RelWithDebInfo"
          ];
        });
        pythonPkgsOverridenInterp = pkgs.python312.override {
          packageOverrides = ps: prev: {
            torch = (prev.torch.override {
              stdenv = rocmPackages.llvm.rocmClangStdenv;
              #cudaSupport = true;
              rocmSupport = true;
              rocmPackages_5 = pkgs.rocmPackages;
              cudaSupport = false;
              useSystemNccl = true;
              #gpuTargets = ["8.9" "8.9+PTX"];
              MPISupport = true;
              triton = ps.triton-no-cuda;
            }).overrideAttrs (old: {
              nativeBuildInputs = old.nativeBuildInputs ++ [ pkgs.ninja ];
              buildInputs = old.buildInputs ++ [ ps.six pkgs.openssl ];
              cmakeFlags = [
                "-DCUDA_LIMIT_GPU_ARCHITECTURE=8.9"
                "-DCUDA_ALL_GPU_ARCHITECTURES=8.9"
                "-DCUDA_COMMON_GPU_ARCHITECTURES=8.9"
                "-DPYTHON_SIX_SOURCE_DIR=${ps.six.src}"
                "-Wno-dev"
                "-DCMAKE_SUPPRESS_DEVELOPER_WARNINGS=ON"
              ];
              postPatch = old.postPatch + ''
                substituteInPlace third_party/NNPACK/CMakeLists.txt --replace "PYTHONPATH=" 'PYTHONPATH=$ENV{PYTHONPATH}:'
                sed -i '2s;^;set(PYTHON_SIX_SOURCE_DIR ${ps.six.src})\n;' third_party/NNPACK/CMakeLists.txt
                sed -i '2s;^;set(CMAKE_SUPPRESS_DEVELOPER_WARNINGS ON CACHE INTERNAL "" FORCE)\n;' CMakeLists.txt
              '';
              USE_NNPACK = 1;
              env.USE_NINJA = 1;
              env.CMAKE_GENERATOR = "Ninja";
              env.PYTHON_SIX_SOURCE_DIR = ps.six.src;
              env.TORCH_CUDA_ARCH_LIST = "8.9 8.9+PTX";
              env.TORCH_NVCC_FLAGS = "-Xfatbin -compress-all";
              env.NIX_CFLAGS_COMPILE = old.env.NIX_CFLAGS_COMPILE + " -w -O3";
            });
          };
        };
        pythonPkgs = pythonPkgsOverridenInterp.pkgs // { python = pythonInterp; python3 = pythonInterp; };
        inherit (pkgs) rocmPackages;
        inherit (rocmPackages) rocmPath;
        self = {
          packages.py-spy = pkgs.callPackage ./py-spy.nix { };
          packages.magma = pkgs.magma;
          packages.torch = pythonPkgs.torch;
          packages.flash-attention = pythonPkgs.callPackage ./flash-attention.nix { };
          packages.files-to-prompt = pythonPkgs.callPackage ./files-to-prompt.nix { };
          packages.koboldcpp-rocm = (pkgs.koboldcpp.override {
            # FIXME: still builds with something ancient
            stdenv = pkgs.rocmPackages.llvm.rocmClangStdenv;
            python3Packages = pythonPkgs;
          }).overrideAttrs (old:
            {
              nativeBuildInputs = builtins.filter (x: (x.pname or null) != "ninja") old.nativeBuildInputs;
              enableParallelBuilding = true;
              env = (old.env or { }) // {
                #CFLAGS = "-fsanitize=undefined";
                #CXXFLAGS = "-fsanitize=undefined";
                NIX_CFLAGS_COMPILE = "-w";
                LLAMA_HIPBLAS = "1";
                ROCM_PATH = rocmPath;
                GPU_TARGETS = "gfx908,gfx1030,gfx1100";
              };
              cmakeFlags = (old.cmakeFlags or [ ]) ++ [
                "-DCMAKE_BUILD_TYPE=RelWithDebInfo"
              ];
              dontStrip = true;
              postPatch = (old.postPatch or "") + ''
                #ln -s "$ {rocmPath}" /opt/rocm
                substituteInPlace Makefile --replace-fail "/opt/rocm" "${rocmPath}"
              '';
              src = pkgs.fetchFromGitHub {
                owner = "YellowRoseCx";
                repo = "koboldcpp-rocm";
                rev = "6be122b6005fd8fb6472e9334fb23c8d04d3caa4";
                hash = "sha256-H+7nQoYy5uoCkHixwbrgQ9Sy9j0qbubwRcQRtWU7fTc=";
              };
            });

          legacyPackages = self.packages // {
            inherit (pkgs) rocmPackages;
            rocmPackages_6 = pkgs.lib.recurseIntoAttrs pkgs.rocmPackages_6;
          };

          # TODO: make default a devShell that detects what's compatible?
          #devShells.default = throw "You need to specify which output you want: CPU, ROCm, or CUDA.";
          devShells.cpu = import ./impl.nix { inherit pkgs; variant = "CPU"; };
          devShells.cuda = import ./impl.nix { inherit pkgs; variant = "CUDA"; };
          devShells.rocm = import ./impl.nix { inherit pkgs; variant = "ROCM"; };
          devShells.pytorch-rocm = import ./pytorch-rocm.nix { inherit pkgs; inherit (pkgs) lib; };
        };
      in
      self
    );
}
