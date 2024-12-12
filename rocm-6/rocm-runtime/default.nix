{ lib
, stdenv
, fetchFromGitHub
, rocmUpdateScript
, pkg-config
, cmake
, ninja
, xxd
, rocm-device-libs
, rocm-thunk
, elfutils
, libdrm
, numactl
, valgrind
, libxml2
, rocm-merged-llvm
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "rocm-runtime";
  version = "6.2.2";

  src = fetchFromGitHub {
    owner = "ROCm";
    repo = "ROCR-Runtime";
    rev = "rocm-${finalAttrs.version}";
    hash = "sha256-VRPwUWCnUunEADaCQIbYEDSbRNdK2e3Om/ee7Hsv3TY=";
    # rev = "816af44b05a00d3063d8a7745865b359a5fba238";
    # hash = "sha256-8XsoSOndH59M2f+f29yiKabostkV96jZDwdg2aqI/xg=";
  };

  sourceRoot = "${finalAttrs.src.name}/src";

  nativeBuildInputs = [
    pkg-config
    cmake
    ninja
    xxd
    rocm-merged-llvm
  ];

  buildInputs = [
    rocm-thunk
    elfutils
    libdrm
    numactl
    valgrind
    libxml2
  ];

  cmakeFlags = [
    "-DBUILD_SHARED_LIBS=ON"
    "-DCMAKE_INSTALL_BINDIR=bin"
    "-DCMAKE_INSTALL_LIBDIR=lib"
    "-DCMAKE_INSTALL_INCLUDEDIR=include"
  ];

  patches = [
    # (fetchpatch {
    #   name = "extend-isa-compatibility-check.patch";
    #   url = "https://salsa.debian.org/rocm-team/rocr-runtime/-/raw/076026d43bbee7f816b81fea72f984213a9ff961/debian/patches/0004-extend-isa-compatibility-check.patch";
    #   hash = "sha256-cC030zVGS4kNXwaztv5cwfXfVwOldpLGV9iYgEfPEnY=";
    #   stripLen = 1;
    # })
  ];

  postPatch = ''
    patchShebangs --host image
    patchShebangs --host core
    patchShebangs --host runtime

    substituteInPlace CMakeLists.txt \
      --replace 'hsa/include/hsa' 'include/hsa'

    # We compile clang before rocm-device-libs, so patch it in afterwards
    # Replace object version: https://github.com/ROCm/ROCR-Runtime/issues/166 (TODO: Remove on LLVM update?)
    # substituteInPlace image/blit_src/CMakeLists.txt \
    #   --replace '-cl-denorms-are-zero' '-cl-denorms-are-zero --rocm-device-lib-path=${rocm-device-libs}/amdgcn/bitcode' \
    #   --replace '-mcode-object-version=4' '-mcode-object-version=5'

    export HIP_DEVICE_LIB_PATH="${rocm-device-libs}/amdgcn/bitcode"
  '';

  passthru.updateScript = rocmUpdateScript {
    name = finalAttrs.pname;
    inherit (finalAttrs.src) owner;
    inherit (finalAttrs.src) repo;
  };

  meta = with lib; {
    description = "Platform runtime for ROCm";
    homepage = "https://github.com/ROCm/ROCR-Runtime";
    license = with licenses; [ ncsa ];
    maintainers = with maintainers; [ lovesegfault ] ++ teams.rocm.members;
    platforms = platforms.linux;
    broken = versions.minor finalAttrs.version != versions.minor stdenv.cc.version || versionAtLeast finalAttrs.version "7.0.0";
  };
})
