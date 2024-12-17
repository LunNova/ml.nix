{ fetchFromGitHub
, stdenv
, cmake
, clr
, numactl
, nlohmann_json
}:
stdenv.mkDerivation {
  pname = "mscclpp";
  version = "v0.5.2";
  nativeBuildInputs = [
    cmake
  ];
  buildInputs = [
    clr
    numactl
    #nlohmann_json
    #python3Packages.nanobind
  ];
  postPatch = ''
    substituteInPlace CMakeLists.txt \
      --replace-fail "gfx90a gfx941 gfx942" "gfx908 gfx90a gfx942 gfx1030 gfx1100"
  '';
  cmakeFlags = [
    #"--trace"
    "-DMSCCLPP_BYPASS_GPU_CHECK=ON"
    "-DMSCCLPP_USE_ROCM=ON"
    "-DMSCCLPP_BUILD_TESTS=OFF"
    "-DAMDGPU_TARGETS=gfx908;gfx90a;gfx942;gfx1030;gfx1100"
    "-DMSCCLPP_BUILD_APPS_NCCL=ON"
    "-DMSCCLPP_BUILD_PYTHON_BINDINGS=OFF"
    "-DFETCHCONTENT_QUIET=OFF"
    "-DFETCHCONTENT_TRY_FIND_PACKAGE_MODE=ALWAYS"
    #"-DFETCHCONTENT_SOURCE_DIR_NANOBIND=${nanobind_src}"
    "-DFETCHCONTENT_SOURCE_DIR_JSON=${nlohmann_json.src}"
    #"-DFETCHCONTENT_FULLY_DISCONNECTED=ON"
  ];
  env.ROCM_PATH = clr;
  src = fetchFromGitHub {
    owner = "microsoft";
    repo = "mscclpp";
    rev = "ee75caf365a27b9ab7521cfdda220b55429e5c37";
    hash = "sha256-/mi9T9T6OIVtJWN3YoEe9az/86rz7BrX537lqaEh3ig=";
  };
}
