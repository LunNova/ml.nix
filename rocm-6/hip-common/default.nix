{ lib
, stdenv
, fetchFromGitHub
, rocmUpdateScript
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "hip-common";
  version = "6.3.0";

  src = fetchFromGitHub {
    owner = "ROCm";
    repo = "HIP";
    rev = "rocm-${finalAttrs.version}";
    hash = "sha256-Nhz/0VD539Qn3o/fM4aIS4Y+R3PJY8uz1iY8Hq8xPgI=";
    # rev = "5f2d2d109c34e749d7947b48834098eec26a5e67";
    # hash = "sha256-Lws65mzRJZP/JE9UiHHfX4Y3zOYA6FPxgbAea48D9Gk=";
  };

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out
    mv * $out

    runHook postInstall
  '';

  passthru.updateScript = rocmUpdateScript {
    name = finalAttrs.pname;
    inherit (finalAttrs.src) owner;
    inherit (finalAttrs.src) repo;
  };

  meta = with lib; {
    description = "C++ Heterogeneous-Compute Interface for Portability";
    homepage = "https://github.com/ROCm/HIP";
    license = with licenses; [ mit ];
    maintainers = with maintainers; [ lovesegfault ] ++ teams.rocm.members;
    platforms = platforms.linux;
    broken = versions.minor finalAttrs.version != versions.minor stdenv.cc.version || versionAtLeast finalAttrs.version "7.0.0";
  };
})
