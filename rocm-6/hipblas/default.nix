{ lib
, stdenv
, fetchFromGitHub
, rocmUpdateScript
, cmake
, rocm-cmake
, clr
, gfortran
, hipblas-common
, rocblas
, rocsolver
, rocsparse
, rocprim
, gtest
, lapack-reference
, writeShellScriptBin
, buildTests ? false
, buildBenchmarks ? false
, buildSamples ? false
}:

# Can also use cuBLAS
stdenv.mkDerivation (finalAttrs: {
  pname = "hipblas";
  version = "6.3.0";
  env.NIX_DEBUG = 1;
  env.NIX_DISABLE_WRAPPER_INCLUDES = 1;

  outputs = [
    "out"
  ] ++ lib.optionals buildTests [
    "test"
  ] ++ lib.optionals buildBenchmarks [
    "benchmark"
  ] ++ lib.optionals buildSamples [
    "sample"
  ];

  src = fetchFromGitHub {
    owner = "ROCm";
    repo = "hipBLAS";
    rev = "rocm-${finalAttrs.version}";
    #rev = "a4b23dec749d9d623f0e7699045f381ec3eddfab";
    hash = "sha256-Rz1KAhBUbvErHTF2PM1AkVhqo4OHldfSNMSpp5Tx9yk=";
  };

  postPatch = ''
        substituteInPlace library/CMakeLists.txt \
          --replace-fail "find_package(Git REQUIRED)" ""

    # touch /build/source/library/include/hipblas-export.h
    # touch /build/source/library/include/hipblas-version.h
    #       cmd1="/nix/store/kkrwq0jr88vgz6b3qyzd5a4n3544wd75-clr-6.2.2/bin/clang++ -x c++ -E
    #       -DUSE_PROF_API=1 -D__HIP_PLATFORM_AMD__=1 -D__HIP_PLATFORM_SOLVER__ -Dhipblas_EXPORTS
    #       -DUSE_PROF_API=1 -D__HIP_PLATFORM_AMD__=1 -D__HIP_PLATFORM_SOLVER__ -Dhipblas_EXPORTS -I/build/source/library/include -I/build/source/build/include/hipblas -I/build/source/build/include -I/build/source/library/src/include -I/build/source/library/src
    #        -isystem /nix/store/xdyrs1m3gln059j62alynk7fi6d05c0d-rocblas-6.2.2/include -isystem /nix/store/s3bshf7jlhw96g36pf9sk2y112yjdd6m-rocsolver-6.2.2/include -isystem /nix/store/kkrwq0jr88vgz6b3qyzd5a4n3544wd75-clr-6.2.2/include -std=c++17 /build/source/library/src/amd_detail/hipblas.cpp -###"
    #        cmd1="/nix/store/kkrwq0jr88vgz6b3qyzd5a4n3544wd75-clr-6.2.2/bin/clang++ -x c++ -E -DUSE_PROF_API=1 -D__HIP_PLATFORM_AMD__=1 -D__HIP_PLATFORM_SOLVER__ -Dhipblas_EXPORTS -I/build/source/library/include -I/build/source/build/include/hipblas -I/build/source/build/include -I/build/source/library/src/include -I/build/source/library/src -isystem /nix/store/xdyrs1m3gln059j62alynk7fi6d05c0d-rocblas-6.2.2/include -isystem /nix/store/s3bshf7jlhw96g36pf9sk2y112yjdd6m-rocsolver-6.2.2/include -isystem /nix/store/kkrwq0jr88vgz6b3qyzd5a4n3544wd75-clr-6.2.2/include -std=c++17 /build/source/library/src/amd_detail/hipblas.cpp -dD -v"
    #        echo $cmd1
    #        set +e
    #        set +o pipefail
    #        $cmd1 
    #        #sleep 1
    #        #stdbuf -i 10K -o 10K -e 10K $cmd1 | grep -C25 "__has_attribute"
    #        #$cmd1  | grep -A 5 -B 5 "__has_attribute.*noinline"
    # exit 1
  '';

  nativeBuildInputs = [
    cmake
    #ninja
    rocm-cmake
    clr
    gfortran
    (writeShellScriptBin "amdclang++" ''
      exec clang++ "$@"
    '')
  ];

  buildInputs = [
    rocblas
    rocprim
    rocsparse
    rocsolver
    # hipblaslt
    hipblas-common
  ] ++ lib.optionals buildTests [
    gtest
  ] ++ lib.optionals (buildTests || buildBenchmarks) [
    lapack-reference
  ];

  dontStrip = true;

  cmakeFlags = [
    "-DCMAKE_BUILD_TYPE=RelWithDebInfo"
    #"-DCMAKE_C_COMPILER=${lib.getBin clr}/bin/clang"
    "-DCMAKE_CXX_COMPILER=${lib.getBin clr}/bin/hipcc"
    #"-DCMAKE_CXX_COMPILER=${lib.getBin clr}/bin/amdclang++"
    # Manually define CMAKE_INSTALL_<DIR>
    # See: https://github.com/NixOS/nixpkgs/pull/197838
    "-DCMAKE_INSTALL_BINDIR=bin"
    "-DCMAKE_INSTALL_LIBDIR=lib"
    "-DCMAKE_INSTALL_INCLUDEDIR=include"
    "-DAMDGPU_TARGETS=${rocblas.amdgpu_targets}" # FIXME: 
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
