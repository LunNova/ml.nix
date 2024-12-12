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
  pname = "hipblaslt";
  #version = "unstable-20241122";
  version = "6.3.0";

  # hipblaslt-unstable> # Writing Custom CMake
  # hipblaslt-unstable> Traceback (most recent call last):
  # hipblaslt-unstable>   File "/nix/store/mdd1rbwjc0p5jmbw9gvjr22sh7wdi74w-python3.12-tensilelite-6.2.2/lib/python3.12/site-packages/Tensile/bin/TensileCreateLibrary", line 43, in <module>
  # hipblaslt-unstable>     TensileCreateLibrary()
  # hipblaslt-unstable>   File "/nix/store/mdd1rbwjc0p5jmbw9gvjr22sh7wdi74w-python3.12-tensilelite-6.2.2/lib/python3.12/site-packages/Tensile/TensileCreateLibrary.py", line 60, in wrapper
  # hipblaslt-unstable>     res = func(*args, **kwargs)
  # hipblaslt-unstable>           ^^^^^^^^^^^^^^^^^^^^^
  # hipblaslt-unstable>   File "/nix/store/mdd1rbwjc0p5jmbw9gvjr22sh7wdi74w-python3.12-tensilelite-6.2.2/lib/python3.12/site-packages/Tensile/TensileCreateLibrary.py", line 1421, in TensileCreateLibrary
  # hipblaslt-unstable>     shutil.copy( os.path.join(globalParameters["SourcePath"], fileName), \
  # hipblaslt-unstable>   File "/nix/store/px2nj16i5gc3d4mnw5l1nclfdxhry61p-python3-3.12.7/lib/python3.12/shutil.py", line 435, in copy
  # hipblaslt-unstable>     copyfile(src, dst, follow_symlinks=follow_symlinks)
  # hipblaslt-unstable>   File "/nix/store/px2nj16i5gc3d4mnw5l1nclfdxhry61p-python3-3.12.7/lib/python3.12/shutil.py", line 262, in copyfile
  # hipblaslt-unstable>     with open(dst, 'wb') as fdst:
  # hipblaslt-unstable>          ^^^^^^^^^^^^^^^


  src = fetchFromGitHub {
    owner = "ROCm";
    repo = "hipBLASLt";
    rev = "rocm-${finalAttrs.version}";
    hash = "sha256-TTxjFQE53PcDA3Yw31h9j2nXpuB1OnHLOPX+d6K2MS8=";
    # rev = "93d7ec47fa251daf13db4a87763da1864e64cf82";
    # hash = "sha256-hOV+vSCBCtoQPi4P30BaaKVj8ES8IJB9F9Fhtvk+t9s=";

    # builds for gfx908!
    # rev = "7b199d190bd446b8a26f8ca2cab381a711b04fc8";
    # hash = "sha256-1mWM0geT/rQ95oGNd3ANR+e2GLRVSN55EBAB79/HuP4=";

    # rebased "tested" gfx908 branch before merge, half a year ago
    # rev = "30aa14836bfebda03c14e6406d3decaf7a8cdb19";
    # hash = "sha256-Tfs9nI1bBWUgjQd7UUdrVGOHZHpUeVJzr2OOKecTJFE=";

    # rev = "3c44762350b2386f3a0f448cfb732f3eee380f2b";
    # hash = "sha256-jLUpCTjnDfG05MYE0BYuwk7orELk54MUna46M4MIOXI=";
    # rev = "rocm-test-09212024"; # ce612a8cb99e2cde4f46b124552e1998b7e8cd96
    # hash = "sha256-SpkxomxsaFbrIK+PN/hBXx3q0d6mjMDSrKA+vwpON28=";
    # rev = "6655405569ec47ec8637b743f48713e45f299d8d";
    # hash = "sha256-5INvDqHO8aVLCu29NIh0WPPYMcIINwoye9bhRqeLXck=";
    # rev = "e0270657047211d7cc5b7de64252744fd77b5d7a";
    # hash = "sha256-9ViZdidLq+aEXHNlqmYNhTETIlU5ZgXOqSrQGkyryww=";
  };
  # env.CFLAGS = "-fsanitize=undefined";
  env.CXX = compiler;
  # env.CCC_OVERRIDE_OPTIONS = "+${cFlags}"; # HACK
  # env.CXXFLAGS = "-fsanitize=undefined";
  # env.CMAKE_CXX_COMPILER = "hipcc"; # used by Tensile
  env.ROCM_PATH = "${clr}";
  env.TENSILE_ROCM_ASSEMBLER_PATH = "${clang-sysrooted}/bin/clang++";
  env.NIX_CC_USE_RESPONSE_FILE = 0;
  env.NIX_DISABLE_WRAPPER_INCLUDES = 1;
  env.TENSILE_GEN_ASSEMBLY_TOOLCHAIN = "${clang-sysrooted}/bin/clang++";
  # env.NIX_DEBUG = 1;
  #enableParallelBuilding = false;
  requiredSystemFeatures = [ "big-parallel" ];

  patches = [
    ./ext-op-first.diff
    # ./alpha_1_init_fix.patch # libcxx bug workaround - https://github.com/llvm/llvm-project/issues/98734
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

  # FIXME: gen_assembly.sh ignores errors
  # blaslt> FileNotFoundError: [Errno 2] No such file or directory: '/opt/rocm/llvm/bin/clang++'
  # hipblaslt> Traceback (most recent call last):
  # hipblaslt>   File "/nix/store/x3p68s3nkcg9syi9hj5zv9z8v8bv8xyq-python3.12-tensile-6.2.2/lib/python3.12/site-packages/Tensile/Ops/./AMaxGenerator.py", line 851, in <module>
  # hipblaslt>     ti.Base._global_ti.init(isa, toolchain_path, False)
  # hipblaslt>   File "/nix/store/x3p68s3nkcg9syi9hj5zv9z8v8bv8xyq-python3.12-tensile-6.2.2/lib/python3.12/site-packages/Tensile/TensileInstructions/Base.py", line 69, in init
  # hipblaslt>     asmCaps  = _initAsmCaps(isaVersion, assemblerPath, debug)
  # hipblaslt>                ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  # hipblaslt>   File "/nix/store/x3p68s3nkcg9syi9hj5zv9z8v8bv8xyq-python3.12-tensile-6.2.2/lib/python3.12/site-packages/Tensile/TensileInstructions/Base.py", line 234, in _initAsmCaps
  # hipblaslt>     rv["SupportedISA"]      = _tryAssembler(isaVersion, assemblerPath, "", isDebug)
  # hipblaslt>                               ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  # hipblaslt>   File "/nix/store/x3p68s3nkcg9syi9hj5zv9z8v8bv8xyq-python3.12-tensile-6.2.2/lib/python3.12/site-packages/Tensile/TensileInstructions/Base.py", line 212, in _tryAssembler
  # hipblaslt>     result = subprocess.run(args, input=asmString.encode(), stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
  # hipblaslt>              ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  # hipblaslt>   File "/nix/store/pv8sxpqsv1nl22n9ka0gpp43j3xr1va2-python3-3.12.6/lib/python3.12/subprocess.py", line 548, in run
  # hipblaslt>     with Popen(*popenargs, **kwargs) as process:
  # hipblaslt>          ^^^^^^^^^^^^^^^^^^^^^^^^^^^
  # hipblaslt>   File "/nix/store/pv8sxpqsv1nl22n9ka0gpp43j3xr1va2-python3-3.12.6/lib/python3.12/subprocess.py", line 1026, in __init__
  # hipblaslt>     self._execute_child(args, executable, preexec_fn, close_fds,
  # hipblaslt>   File "/nix/store/pv8sxpqsv1nl22n9ka0gpp43j3xr1va2-python3-3.12.6/lib/python3.12/subprocess.py", line 1955, in _execute_child
  # hipblaslt>     raise child_exception_type(errno_num, err_msg, err_filename)
  # hipblaslt> FileNotFoundError: [Errno 2] No such file or directory: '/opt/rocm/llvm/bin/clang++'
  # hipblaslt> /nix/store/x3p68s3nkcg9syi9hj5zv9z8v8bv8xyq-python3.12-tensile-6.2.2/lib/python3.12/site-packages/Tensile/Source/..//Ops/gen_assembly.sh: line 76: /opt/rocm/llvm/bin/clang++: No such file or directory
  # hipblaslt> /nix/store/x3p68s3nkncg9syi9hj5zv9z8v8bv8xyq-python3.12-tensile-6.2.2/lib/python3.12/site-packages/Tensile/Source/..//Ops/gen_assembly.sh: line 80: deactivate: command not found
  # hipblaslt> make[2]: *** [library/CMakeFiles/build_ext_op_library.dir/build.make:76: Tensile/library/hipblasltExtOpLibrary.dat] Error 127
  # hipblaslt> make[1]: *** [CMakeFiles/Makefile2:187: library/CMakeFiles/build_ext_op_library.dir/all] Error 2

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
