{ lib
, stdenv
, llvmPackages_18
, overrideCC
, rocm-device-libs
, rocm-runtime
, fetchFromGitHub
, runCommandNoCC
, symlinkJoin
, rdfind
, wrapBintoolsWith
, emptyDirectory
, zstd
, zlib
, gcc-unwrapped
, glibc
, substituteAll
, libffi
, libxml2
}:

let
  ## Stage 1 ##
  # Projects
  # llvmPackagesSet = recurseIntoAttrs (callPackages ./llvm-upstream { }); 
  llvmPackagesNoBintools = llvmPackages_18.override {
    bootBintools = null;
    bootBintoolsNoLibc = null;
  };
  useLibcxx = false; # whether rocm stdenv uses libcxx (clang c++ stdlib) instead of gcc stdlibc++
  # llvmPackagesNoBintools = llvmPackages_18.override {
  #   bootBintools = null;
  #   bootBintoolsNoLibc = null;
  # };

  llvmStdenv =
    overrideCC
      llvmPackagesNoBintools.libcxxStdenv
      llvmPackagesNoBintools.clangUseLLVM;
  llvmLibstdcxxStdenv =
    overrideCC
      llvmPackagesNoBintools.stdenv
      (llvmPackagesNoBintools.libstdcxxClang.override {
        inherit (llvmPackages_18) bintools;
      });
  gcc-include = runCommandNoCC "gcc-include" { } ''
    mkdir -p $out
    ln -s ${gcc-unwrapped}/include/ $out/
    ln -s ${gcc-unwrapped}/lib/ $out/
  '';
  gcc-prefix = symlinkJoin {
    name = "gcc-prefix";
    paths = [
      gcc-unwrapped
      gcc-unwrapped.lib
      glibc.dev
      glibc
    ];
    postBuild = ''
      # JANKy JANKy JANK clang wasn't finding glibc in here without this
      rm $out/lib64
      ln -s $out/ $out/x86_64-unknown-linux-gnu
    '';
  };
  version = "6.3.0"; # FIXME: bump to 6.3.0
  # major version of this should be the clang version ROCm forked from
  rocmLlvmVersion = "18.0.0-${llvmSrc.rev}";
  usefulOutputs = drv: builtins.filter (x: x != null) [ drv (drv.lib or null) (drv.dev or null) ];
  listUsefulOutputs = builtins.concatMap usefulOutputs;
  llvmSrc = fetchFromGitHub {
    # owner = "ROCm";
    # repo = "llvm-project";
    # rev = "rocm-${version}";
    # hash = "sha256-ii4ErYxfwmis0PSovpG37ybaXmKX4neUjHXliaI2v6k=";

    # Performance improvements cherry-picked on top of rocm-6.3.x
    # most importantly, amdgpu-early-alwaysinline memory usage fix
    owner = "LunNova";
    repo = "llvm-project-rocm";
    rev = "d6e55e17f328a495bc32fddb7826e673ac9766ec";
    hash = "sha256-9f5Q6ZtgWqG18lfA8X9bKSOUppzkISh8Gea1XkYu9dg=";
  };
  llvmSrcFixed = llvmSrc;
  llvmMajorVersion = lib.versions.major rocmLlvmVersion;
  # An llvmPackages (pkgs/development/compilers/llvm/) built from ROCm LLVM's source tree
  # !! built on a libcxxStdenv of the same major LLVM version !!
  # so linking to both the end result's libcxx/abi *and* the LLVM C++ libraries works
  llvmPackagesRocm = llvmPackages_18.override (_old: {
    stdenv = if useLibcxx then llvmStdenv else llvmLibstdcxxStdenv; # old.stdenv #llvmPackagesNoBintools.libcxxStdenv;

    # not setting gitRelease = because that causes patch selection logic to use git patches
    # ROCm LLVM is closer to 18 official
    # gitRelease = {}; officialRelease = null;
    officialRelease = { }; # Set but empty because we're overriding everything from it.
    version = rocmLlvmVersion;
    src = llvmSrcFixed;
    monorepoSrc = llvmSrcFixed;
    doCheck = false;
  });
  sysrootCompiler = cc: name: paths:
    let linked = symlinkJoin { inherit name paths; };
    in runCommandNoCC name { } ''
      set -x
      mkdir -p $out/
      cp --reflink=auto -rL ${linked}/* $out/
      chmod -R +rw $out
      #ln -sf $out/lib/clang/${llvmMajorVersion}/include/* $out/include/
      # mv $out/lib/clang/${llvmMajorVersion}/include/* $out/include/
      # rm -rf $out/lib/clang/
      # mkdir -p $out/lib/clang/
      # ln -s $out/ $out/lib/clang/${llvmMajorVersion}
      mkdir -p $out/usr
      ln -s $out/ $out/usr/local
      #ln -s $out/lib/clang/18/include/c++/v1/* $out/lib/clang/18/include/
      mkdir -p $out/nix-support/
      rm -rf $out/lib64 # we don't need mixed 32 bit
      echo 'export CC=clang' >> $out/nix-support/setup-hook
      echo 'export CXX=clang++' >> $out/nix-support/setup-hook
      mkdir -p $out/lib/clang/${llvmMajorVersion}/lib/linux/
      ln -s $out/lib/linux/libclang_rt.* $out/lib/clang/${llvmMajorVersion}/lib/linux/

      find $out -type f -exec sed -i "s|${cc.out}|$out|g" {} +
      find $out -type f -exec sed -i "s|${cc.dev}|$out|g" {} +

      # our /include now has more than clang expects, so this specific dir still needs to point to cc.dev
      # FIXME: could copy into a different subdir?
      sed -i 's|set(CLANG_INCLUDE_DIRS.*$|set(CLANG_INCLUDE_DIRS "${cc.dev}/include")|g' $out/lib/cmake/clang/ClangConfig.cmake
      ${lib.getExe rdfind} -makesymlinks true $out/ # create links *within* the sysroot to save space
    '';
  findClangNostdlibincPatch = x: (
    (lib.strings.hasSuffix "add-nostdlibinc-flag.patch" (builtins.baseNameOf x))
    ||
    (lib.strings.hasSuffix "clang-at-least-16-LLVMgold-path.patch" (builtins.baseNameOf x))
  );
  llvmTargetsFlag = "-DLLVM_TARGETS_TO_BUILD=AMDGPU;${{
        "x86_64" = "X86";
        "aarch64" = "AArch64";
      }.${llvmStdenv.targetPlatform.parsed.cpu.name}}";
  # -ffat-lto-objects = emit LTO object files that are compatible with non-LTO-supporting builds too
  # FatLTO objects are a special type of fat object file that contain LTO compatible IR in addition to generated object code,
  # instead of containing object code for multiple target architectures. This allows users to defer the choice of whether to
  # use LTO or not to link-time, and has been a feature available in other compilers, like GCC, for some time.

  addGccLtoCmakeFlags = !llvmPackagesRocm.stdenv.cc.isClang;
  gccLtoFlags = lib.optionalString addGccLtoCmakeFlags " -D_GLIBCXX_USE_CXX11_ABI=0 -flto -ffat-lto-objects -flto-compression-level=19 -Wl,-flto";
  llvmExtraCflags = "-O3 -march=skylake -mtune=znver3${gccLtoFlags}" + lib.optionalString llvmPackagesRocm.stdenv.cc.isClang " -flto=thin -ffat-lto-objects -fno-omit-frame-pointer -gz -g1 -DNDEBUG";
in
rec {
  inherit (llvmPackagesRocm) libunwind;
  inherit (llvmPackagesRocm) libcxx;
  old-llvm = llvmPackagesRocm.llvm;
  llvm = (llvmPackagesRocm.llvm.override { ninja = emptyDirectory; }).overrideAttrs (old: {
    dontStrip = true;
    #postInstall = lib.strings.replaceStrings [ "release" ] [ "relwithdebinfo" ] old.postInstall;
    inherit (old) nativeBuildInputs;
    buildInputs = old.buildInputs ++ [ zstd zlib ];
    env.NIX_BUILD_ID_STYLE = "fast";
    postPatch = (old.postPatch or "") + ''
      find . -name "*.sh" -exec bash -c 'chmod +x "$0"; patchShebangs "$0"' {} \;
      patchShebangs lib/OffloadArch/make_generated_offload_arch_h.sh
    '';
    LDFLAGS = "-Wl,--build-id=sha1,--icf=all";
    cmakeFlags = old.cmakeFlags ++ [
      llvmTargetsFlag
      "-DCMAKE_BUILD_TYPE=Release"
      "-DLLVM_ENABLE_ZSTD=FORCE_ON"
      "-DLLVM_ENABLE_ZLIB=FORCE_ON"
      "-DLLVM_ENABLE_THREADS=ON"
      "-DLLVM_ENABLE_LTO=Thin"
      "-DLLVM_USE_LINKER=lld"
      (lib.cmakeBool "LLVM_ENABLE_LIBCXX" useLibcxx)
      "-DCLANG_DEFAULT_CXX_STDLIB=${if useLibcxx then "libc++" else "libstdc++"}"
    ] ++ lib.optionals addGccLtoCmakeFlags [
      "-DCMAKE_AR=${gcc-unwrapped}/bin/gcc-ar"
      "-DCMAKE_RANLIB=${gcc-unwrapped}/bin/gcc-ranlib"
      "-DCMAKE_NM=${gcc-unwrapped}/bin/gcc-nm"
      #"-DLLVM_ENABLE_MODULES=ON"
      #"-DLLVM_USE_PERF=ON"
      #"-DLLVM_UNREACHABLE_OPTIMIZE=OFF"

      # ROCm code that links to LLVM may use exceptions !!
      #"-DLLVM_ENABLE_EH=ON"
      #"-DCMAKE_CXX_FLAGS_RELEASE=-fuse-ld=lld -O3 -gline-tables-only\\ -DNDEBUG"
      #"-DLIBC_CONF_KEEP_FRAME_POINTER=ON"
    ] ++ lib.optionals useLibcxx [
      "-DLLVM_ENABLE_LTO=Thin"
      "-DLLVM_USE_LINKER=lld"
      "-DLLVM_ENABLE_LIBCXX=ON"
    ];
    preConfigure = (old.preConfigure or "") + ''
      cmakeFlagsArray+=(
        '-DCMAKE_C_FLAGS_RELEASE=${llvmExtraCflags}'
        '-DCMAKE_CXX_FLAGS_RELEASE=${llvmExtraCflags}'
      )
    '';
  });
  lld = (llvmPackagesRocm.lld.override { libllvm = llvm; ninja = emptyDirectory; }).overrideAttrs (old: {
    patches = builtins.filter (x: !(lib.strings.hasSuffix "more-openbsd-program-headers.patch" (builtins.baseNameOf x))) old.patches;
    dontStrip = true;
    nativeBuildInputs = old.nativeBuildInputs ++ [ llvmPackagesNoBintools.lld ];
    buildInputs = old.buildInputs ++ [ zstd zlib ];
    env.NIX_BUILD_ID_STYLE = "fast";
    LDFLAGS = "-Wl,--build-id=sha1,--icf=all";
    cmakeFlags = old.cmakeFlags ++ [
      llvmTargetsFlag
      "-DCMAKE_BUILD_TYPE=Release"
      "-DLLVM_ENABLE_ZSTD=FORCE_ON"
      "-DLLVM_ENABLE_ZLIB=FORCE_ON"
      "-DLLVM_ENABLE_THREADS=ON"
      "-DLLVM_ENABLE_LTO=Thin"
      "-DLLVM_USE_LINKER=lld"
      (lib.cmakeBool "LLVM_ENABLE_LIBCXX" useLibcxx)
      "-DCLANG_DEFAULT_CXX_STDLIB=${if useLibcxx then "libc++" else "libstdc++"}"
    ] ++ lib.optionals addGccLtoCmakeFlags [
      "-DCMAKE_AR=${gcc-unwrapped}/bin/gcc-ar"
      "-DCMAKE_RANLIB=${gcc-unwrapped}/bin/gcc-ranlib"
      "-DCMAKE_NM=${gcc-unwrapped}/bin/gcc-nm"
      #"-DLLVM_ENABLE_MODULES=ON"
      #"-DLLVM_USE_PERF=ON"
      #"-DLLVM_UNREACHABLE_OPTIMIZE=OFF"
      #"-DLIBC_CONF_KEEP_FRAME_POINTER=ON"
    ] ++ lib.optionals useLibcxx [
      "-DLLVM_ENABLE_LIBCXX=ON"
    ];
    preConfigure = (old.preConfigure or "") + ''
      cmakeFlagsArray+=(
        '-DCMAKE_C_FLAGS_RELEASE=${llvmExtraCflags}'
        '-DCMAKE_CXX_FLAGS_RELEASE=${llvmExtraCflags}'
      )
    '';
  });
  clang-unwrapped-orig = llvmPackagesRocm.clang-unwrapped;
  clang-unwrapped = ((llvmPackagesRocm.clang-unwrapped.override { libllvm = llvm; ninja = emptyDirectory; }).overrideAttrs (old:
    let filteredPatches = builtins.filter (x: !(findClangNostdlibincPatch x)) old.patches; in
    {
      meta.platforms = [
        "x86_64-linux"
      ];
      pname = "${old.pname}-rocm";
      patches = filteredPatches ++ [
        ./clang-bodge-ignore-systemwide-incls.diff
        ./clang-log-jobs.diff # FIXME: rebase for 20+?
        # FIXME: if llvm was overrideable properly this wouldn't be needed
        (substituteAll {
          src = ./clang-at-least-16-LLVMgold-path.patch;
          libllvmLibdir = "${llvm.lib}/lib";
        })
      ];
      nativeBuildInputs = old.nativeBuildInputs ++ [ llvmPackagesNoBintools.lld ];
      buildInputs = old.buildInputs ++ [ zstd zlib ];
      dontStrip = true;
      LDFLAGS = "-Wl,--build-id=sha1,--icf=all";
      env = (old.env or { }) // {
        NIX_BUILD_ID_STYLE = "fast";
      };
      requiredSystemFeatures = (old.requiredSystemFeatures or [ ]) ++ [ "big-parallel" ];
      # https://github.com/llvm/llvm-project/blob/6976deebafa8e7de993ce159aa6b82c0e7089313/clang/cmake/caches/DistributionExample-stage2.cmake#L9-L11
      cmakeFlags = old.cmakeFlags ++ [
        llvmTargetsFlag
        "-DCMAKE_BUILD_TYPE=Release"
        "-DLLVM_ENABLE_ZSTD=FORCE_ON"
        "-DLLVM_ENABLE_ZLIB=FORCE_ON"
        "-DLLVM_ENABLE_THREADS=ON"
        "-DLLVM_ENABLE_LTO=Thin"
        "-DLLVM_USE_LINKER=lld"
        # "-DLLVM_USE_SANITIZER=Undefined" ASAN will fail downstream builds because of undefined symbols, Undefined works.
        (lib.cmakeBool "LLVM_ENABLE_LIBCXX" useLibcxx)
        "-DCLANG_DEFAULT_CXX_STDLIB=${if useLibcxx then "libc++" else "libstdc++"}"
      ] ++ lib.optionals addGccLtoCmakeFlags [
        "-DCMAKE_AR=${gcc-unwrapped}/bin/gcc-ar"
        "-DCMAKE_RANLIB=${gcc-unwrapped}/bin/gcc-ranlib"
        "-DCMAKE_NM=${gcc-unwrapped}/bin/gcc-nm"
        #"-DLLVM_ENABLE_MODULES=ON"
        #"-DLLVM_USE_PERF=ON"
        #"-DLLVM_UNREACHABLE_OPTIMIZE=OFF"
        #"-DCMAKE_CXX_FLAGS_RELEASE=-fuse-ld=lld -O3 -gline-tables-only\\ -DNDEBUG"
        #"-DLIBC_CONF_KEEP_FRAME_POINTER=ON"
      ] ++ lib.optionals useLibcxx [
        "-DLLVM_ENABLE_LTO=Thin"
        "-DLLVM_ENABLE_LIBCXX=ON"
        "-DLLVM_USE_LINKER=lld"
        "-DCLANG_DEFAULT_RTLIB=compiler-rt"
      ] ++ lib.optionals (!useLibcxx) [
        # FIXME: Config file?
        "-DGCC_INSTALL_PREFIX=${gcc-prefix}"
      ];
      preConfigure = (old.preConfigure or "") + ''
        cmakeFlagsArray+=(
          '-DCMAKE_C_FLAGS_RELEASE=${llvmExtraCflags}'
          '-DCMAKE_CXX_FLAGS_RELEASE=${llvmExtraCflags}'
        )
      '';
    })) // { libllvm = llvm; };
  # A clang that understands standard include searching
  # and expects its libc to be in the sysroot
  # FIXME: clang picks an unnecessarily long libstdc++++ path with ../../../ and we should fix that
  # because string allocs can be expensive in compiling when they get long
  clang-sysrooted = (sysrootCompiler clang-unwrapped "rocmcxx" (listUsefulOutputs ([
    clang-unwrapped
    bintools
    compiler-rt
  ] ++ (lib.optionals useLibcxx [
    libcxx
  ])
  ++ (lib.optionals (!useLibcxx) [
    gcc-include
    glibc
    glibc.dev
  ]))
  )) // { version = llvmMajorVersion; cc = clang-sysrooted; libllvm = llvm; isClang = true; isGNU = false; };
  clang-tools = llvmPackagesRocm.clang-tools.override {
    inherit clang-unwrapped clang;
    # clang = clang-sysrooted;
  };
  inherit (llvmPackagesRocm) compiler-rt compiler-rt-libc;
  # compiler-rt = llvmPackagesRocm.compiler-rt.overrideAttrs (old: {
  #   pname = old.pname + "test";
  #   cmakeFlags = old.cmakeFlags ++ [
  #     # "--trace-expand" "--debug-output"
  #      "--debug-trycompile"
  #      ];
  #   env.NIX_CFLAGS_COMPILE = "-v";
  #   preConfigure = ''${old.preConfigure or ""}
  #     sed -i '1i variable_watch(__CMAKE_C_COMPILER_OUTPUT)' CMakeLists.txt
  #     sed -i '1i variable_watch(__CMAKE_CXX_COMPILER_OUTPUT)' CMakeLists.txt
  #     sed -i '1i variable_watch(OUTPUT)' CMakeLists.txt

  #     grep __CMAKE_CXX_COMPILER_OUTPUT CMakeLists.txt || exit 1
  #     env | grep ../../../..
  #     env | grep gcc-13
  #     env | grep gcc-toolchain
  #     exit 1
  #   '';
  # });
  bintools = wrapBintoolsWith {
    bintools = llvmPackagesRocm.bintools-unwrapped.override {
      inherit lld llvm;
    };
  };

  # gnu-sysroot accepting clang built from ROCm LLVM tree set to use LLVM libs
  clang = clang-sysrooted;

  # Emulate a monolithic ROCm LLVM build to support building ROCm's in-tree LLVM projects
  rocm-merged-llvm = symlinkJoin {
    name = "rocm-llvm-merge";
    paths = [
      llvm
      llvm.dev
      lld
      lld.lib
      lld.dev
      libunwind
      libunwind.dev
      compiler-rt
      compiler-rt.dev
      clang-sysrooted
    ] ++ lib.optionals useLibcxx [
      libcxx
      libcxx.out
      libcxx.dev
    ];
    postBuild = builtins.unsafeDiscardStringContext ''
      found_files=$(find $out -name '*.cmake')
      if [ -z "$found_files" ]; then
          >&2 echo "Error: No CMake files found in $out"
          exit 1
      fi

      for target in ${clang-unwrapped.out} ${clang-unwrapped.lib} ${clang-unwrapped.dev}; do
        if grep "$target" $found_files; then
            >&2 echo "Unexpected ref to $target (clang-unwrapped) found"
            # exit 1
            # FIXME: enable this to reduce closure size
        fi
      done
    '';
    inherit version;
    llvm-src = llvmSrc;
  };

  rocmClangStdenv = overrideCC (if useLibcxx then llvmPackagesRocm.libcxxStdenv else llvmPackagesRocm.stdenv) clang;

  # Projects
  # libclc = callPackage ./stage-3/libclc.nix { inherit rocmUpdateScript llvm clang; stdenv = rocmClangStdenv; };
  # lldb = callPackage ./stage-3/lldb.nix { inherit rocmUpdateScript clang; stdenv = rocmClangStdenv; };
  # mlir = callPackage ./stage-3/mlir.nix { inherit rocmUpdateScript clr; stdenv = rocmClangStdenv; };
  # polly = callPackage ./stage-3/polly.nix { inherit rocmUpdateScript; stdenv = rocmClangStdenv; };
  # flang = callPackage ./stage-3/flang.nix { inherit rocmUpdateScript clang-unwrapped mlir; stdenv = rocmClangStdenv; };
  openmp = (llvmPackagesRocm.openmp.override {
    stdenv = rocmClangStdenv;
    # FIXME: this is wrong for cross builds
    llvm = rocm-merged-llvm;
    targetLlvm = rocm-merged-llvm;
    clang-unwrapped = clang;
  }).overrideAttrs (old: {
    cmakeFlags = old.cmakeFlags ++ [
      "-DDEVICELIBS_ROOT=${rocm-device-libs.src}"
    ] ++ lib.optionals addGccLtoCmakeFlags [
      "-DCMAKE_AR=${gcc-unwrapped}/bin/gcc-ar"
      "-DCMAKE_RANLIB=${gcc-unwrapped}/bin/gcc-ranlib"
    ];
    env.LLVM = "${rocm-merged-llvm}";
    env.LLVM_DIR = "${rocm-merged-llvm}";
    env.CCC_OVERRIDE_OPTIONS = "+-v";
    buildInputs = old.buildInputs ++ [
      rocm-device-libs
      rocm-runtime
      zlib
      zstd
      libxml2
      libffi
    ];
  });

  # Runtimes
  #pstl = callPackage ./stage-3/pstl.nix { inherit rocmUpdateScript; stdenv = rocmClangStdenv; };
}
