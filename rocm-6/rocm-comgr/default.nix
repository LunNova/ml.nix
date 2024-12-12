{ lib
, stdenv
, rocmUpdateScript
, cmake
, python3
, rocm-merged-llvm
, rocm-device-libs
, zlib
, zstd
, libxml2
}:

let
  llvmNativeTarget =
    if stdenv.hostPlatform.isx86_64 then "X86"
    else if stdenv.hostPlatform.isAarch64 then "AArch64"
    else throw "Unsupported ROCm LLVM platform";
in
stdenv.mkDerivation (finalAttrs: {
  pname = "rocm-comgr";
  # In-tree with ROCm LLVM
  inherit (rocm-merged-llvm) version;
  src = rocm-merged-llvm.llvm-src;

  sourceRoot = "${finalAttrs.src.name}/amd/comgr";

  nativeBuildInputs = [
    cmake
    python3
  ];

  buildInputs = [
    rocm-device-libs
    libxml2
    zlib
    zstd
    rocm-merged-llvm
  ];

  dontStrip = true;
  cmakeFlags = [
    "-DCMAKE_VERBOSE_MAKEFILE=ON"
    "-DCMAKE_BUILD_TYPE=RelWithDebInfo"
    "-DLLVM_TARGETS_TO_BUILD=AMDGPU;${llvmNativeTarget}"
  ];

  passthru.updateScript = rocmUpdateScript {
    name = finalAttrs.pname;
    inherit (finalAttrs.src) owner;
    inherit (finalAttrs.src) repo;
  };

  meta = with lib; {
    description = "APIs for compiling and inspecting AMDGPU code objects";
    homepage = "https://github.com/ROCm/ROCm-CompilerSupport/tree/amd-stg-open/lib/comgr";
    license = licenses.ncsa;
    maintainers = with maintainers; [ lovesegfault ] ++ teams.rocm.members;
    platforms = platforms.linux;
    broken = versions.minor finalAttrs.version != versions.minor stdenv.cc.version || versionAtLeast finalAttrs.version "7.0.0";
  };
})
