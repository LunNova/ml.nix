{ lib
, stdenv
, rocmUpdateScript
, cmake
, ninja
, libxml2
, zlib
, zstd
, ncurses
, rocm-merged-llvm
, python3
}:

let
  llvmNativeTarget =
    if stdenv.hostPlatform.isx86_64 then "X86"
    else if stdenv.hostPlatform.isAarch64 then "AArch64"
    else throw "Unsupported ROCm LLVM platform";
in
stdenv.mkDerivation (finalAttrs: {
  pname = "rocm-device-libs";
  # In-tree with ROCm LLVM
  inherit (rocm-merged-llvm) version;
  src = rocm-merged-llvm.llvm-src;

  postPatch = ''
    cd amd/device-libs
  '';

  patches = [ ./cmake.patch ];

  nativeBuildInputs = [
    cmake
    ninja
    python3
  ];

  buildInputs = [
    libxml2
    zlib
    zstd
    ncurses
    rocm-merged-llvm
  ];

  dontStrip = true;
  # env.NIX_DEBUG = 1;
  # env.CFLAGS = "-g1 -fsanitize=undefined";
  # env.CXXFLAGS = "-g1 -fsanitize=undefined";
  # env.NIX_CFLAGS_COMPILE = "-g1";
  # env.NIX_CXXFLAGS_COMPILE = "-g1";

  cmakeFlags = [
    "-DCMAKE_RELEASE_TYPE=RelWithDebInfo"
    "-DLLVM_TARGETS_TO_BUILD=AMDGPU;${llvmNativeTarget}"
  ];

  passthru.updateScript = rocmUpdateScript {
    name = finalAttrs.pname;
    inherit (finalAttrs.src) owner;
    inherit (finalAttrs.src) repo;
  };

  meta = with lib; {
    description = "Set of AMD-specific device-side language runtime libraries";
    homepage = "https://github.com/ROCm/ROCm-Device-Libs";
    license = licenses.ncsa;
    maintainers = with maintainers; [ lovesegfault ] ++ teams.rocm.members;
    platforms = platforms.linux;
    broken = versions.minor finalAttrs.version != versions.minor stdenv.cc.version || versionAtLeast finalAttrs.version "7.0.0";
  };
})
