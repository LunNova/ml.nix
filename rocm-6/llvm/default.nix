{ lib
, stdenv
, llvmPackages_18
, callPackage
, rocmUpdateScript
, overrideCC
, rocm-device-libs
, rocm-runtime
, rocm-thunk
, clr
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
  gcc-include = runCommandNoCC "gcc-include" { } ''
    mkdir -p $out
    ln -s ${gcc-unwrapped}/include/ $out/
    ln -s ${gcc-unwrapped}/lib/ $out/
  '';
  gcc-prefix = symlinkJoin {
    name = "gcc-prefix-for-rocm-clang";
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
  version = "6.2.4"; # FIXME: bump to 6.3.0
  # major version of this should be the clang version ROCm forked from
  rocmLlvmVersion = "18.0.0-${llvmSrc.rev}";
  usefulOutputs = drv: builtins.filter (x: x != null) [ drv (drv.lib or null) (drv.dev or null) ];
  listUsefulOutputs = builtins.concatMap usefulOutputs;
  llvmSrc = fetchFromGitHub {
    owner = "ROCm";
    repo = "llvm-project";
    rev = "rocm-${version}";
    hash = "sha256-AaSrA6YW60bmpaP1DI5eeNHcMzwdKysV79OV6Ct9sPY=";
    # rev = "301a848b2854672bf286b29a174efa2a2b87c1f0";
    # hash = "sha256-1ZJajAl8vceM8ZDZ3czWtFlhLHHfPCEnrewZp75qt4g=";

    # amd-mainline-open 2024-11-14
    # rev = "13f42873339fe94aadc669360b782da6017d1d85";
    # hash = "sha256-w6k0o8+IYm5M7fE8DrKf2HWY5RuNsfvLtBZXrfx+Yg8=";

    # amd-trunk-dev
    # rev = "ae842a7c4ae295e3391bc160156a71e523499166";
    # hash = "sha256-Qts/jgtbICgoSW2v9UtMCOvM6nkVwwA0/FijEb5UhQ0=";

    # amd-staging
    # rev = "0366005cd760c6dbdfe752ba0a285bb00f149bc6";
    # hash = "sha256-02gCnAQVRJf0pFNkyenEUnJ81t1K9jjMBY2jmKEeW1w=";

    # rev = "rocm-test-09212024"; # "c3f66fa2c315b5b631133176b5c81cfad7697645"
    # hash = "sha256-XyLFpqRVVo9qXjiQybsrQz06PkBWHv73K5dBu0jo9mQ=";
  };
  llvmSrcFixed = runCommandNoCC "rocm-llvm-src-patched" { } ''
    cp --no-preserve=mode,ownership -r ${llvmSrc}/. "$out"/
    chmod +x $out/llvm/lib/OffloadArch/*.sh
    find . -iname "*.sh" -exec bash -c 'chmod +x "$0"; patchShebangs "$0"' {} \;
    patchShebangs $out/llvm/lib/OffloadArch/make_generated_offload_arch_h.sh
  '';
  # llvmSrcFixed = llvmSrc;
  llvmMajorVersion = lib.versions.major rocmLlvmVersion;

  # An llvmPackages (pkgs/development/compilers/llvm/) built from ROCm LLVM's source tree
  # !! built on a libcxxStdenv of the same major LLVM version !!
  # so linking to both the end result's libcxx/abi *and* the LLVM C++ libraries works
  llvmPackagesRocm = llvmPackages_18.override (old: {
    stdenv = if useLibcxx then llvmStdenv else old.stdenv; #llvmPackagesNoBintools.libcxxStdenv;

    # bootBintools = null;
    # bootBintoolsNoLibc = null;
    # not setting gitRelease = because that causes patch selection logic to use git patches
    # ROCm LLVM is closer to 18 official
    # gitRelease = {}; officialRelease = null;
    officialRelease = { }; # Set but empty because we're overriding everything from it.
    version = rocmLlvmVersion;
    src = llvmSrcFixed;
    monorepoSrc = llvmSrcFixed;
    doCheck = false;
  });
  # FIXME: sysroot supporting compiler in llvm/ dir?
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
      ln -s $out/lib/linux/libclang_rt.builtins-x86_64.a $out/lib/clang/${llvmMajorVersion}/lib/linux/libclang_rt.builtins-x86_64.a

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
  llvmExtraCflags = lib.optionalString useLibcxx "-ffat-lto-objects -Wl,--icf=all,--compress-debug-sections=zlib -fno-omit-frame-pointer -mno-omit-leaf-frame-pointer -O3 -gline-tables-only -DNDEBUG";
in
rec {
  inherit (llvmPackagesRocm) libunwind;
  inherit (llvmPackagesRocm) libcxx;
  old-llvm = llvmPackagesRocm.llvm;
  llvm = (llvmPackagesRocm.llvm.override { ninja = emptyDirectory; }).overrideAttrs (old: {
    dontStrip = true;
    postInstall = lib.strings.replaceStrings [ "release" ] [ "relwithdebinfo" ] old.postInstall;
    #nativeBuildInputs = old.nativeBuildInputs ++ [ mold ];
    buildInputs = old.buildInputs ++ [ zstd zlib ];
    env.NIX_BUILD_ID_STYLE = "fast";
    cmakeFlags = old.cmakeFlags ++ [
      llvmTargetsFlag
      "-DCMAKE_BUILD_TYPE=RelWithDebInfo"
      "-DLLVM_ENABLE_ZSTD=FORCE_ON"
      "-DLLVM_ENABLE_ZLIB=FORCE_ON"
      #"-DLLVM_ENABLE_MODULES=ON"
      "-DLLVM_USE_PERF=ON"
      #"-DLLVM_UNREACHABLE_OPTIMIZE=OFF"

      # ROCm code that links to LLVM may use exceptions !!
      #"-DLLVM_ENABLE_EH=ON"
      #"-DCMAKE_CXX_FLAGS_RELWITHDEBINFO=-fuse-ld=lld -O3 -gline-tables-only\\ -DNDEBUG"
      #"-DLIBC_CONF_KEEP_FRAME_POINTER=ON"
    ] ++ lib.optionals useLibcxx [
      "-DLLVM_ENABLE_LTO=Thin"
      "-DLLVM_USE_LINKER=lld"
      "-DLLVM_ENABLE_LIBCXX=ON"
    ];
    preConfigure = (old.preConfigure or "") + ''
      cmakeFlagsArray+=(
        '-DCMAKE_C_FLAGS_RELWITHDEBINFO=${llvmExtraCflags}'
        '-DCMAKE_CXX_FLAGS_RELWITHDEBINFO=${llvmExtraCflags}'
      )
    '';
  });
  lld = (llvmPackagesRocm.lld.override { libllvm = llvm; ninja = emptyDirectory; }).overrideAttrs (old: {
    patches = builtins.filter (x: !(lib.strings.hasSuffix "more-openbsd-program-headers.patch" (builtins.baseNameOf x))) old.patches;
    dontStrip = true;
    #nativeBuildInputs = old.nativeBuildInputs ++ [ mold ];
    buildInputs = old.buildInputs ++ [ zstd zlib ];
    env.NIX_BUILD_ID_STYLE = "fast";
    cmakeFlags = old.cmakeFlags ++ [
      llvmTargetsFlag
      "-DCMAKE_BUILD_TYPE=RelWithDebInfo"
      "-DLLVM_ENABLE_ZSTD=FORCE_ON"
      "-DLLVM_ENABLE_ZLIB=FORCE_ON"
      #"-DLLVM_ENABLE_MODULES=ON"
      "-DLLVM_USE_PERF=ON"
      #"-DLLVM_UNREACHABLE_OPTIMIZE=OFF"
      #"-DCMAKE_CXX_FLAGS_RELWITHDEBINFO=-fuse-ld=lld -O3 -gline-tables-only\\ -DNDEBUG"
      #"-DLIBC_CONF_KEEP_FRAME_POINTER=ON"
    ] ++ lib.optionals useLibcxx [
      "-DLLVM_ENABLE_LIBCXX=ON"
      "-DLLVM_ENABLE_LTO=Thin"
      "-DLLVM_USE_LINKER=lld"
    ];
    preConfigure = (old.preConfigure or "") + ''
      cmakeFlagsArray+=(
        '-DCMAKE_C_FLAGS_RELWITHDEBINFO=${llvmExtraCflags}'
        '-DCMAKE_CXX_FLAGS_RELWITHDEBINFO=${llvmExtraCflags}'
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
      #nativeBuildInputs = old.nativeBuildInputs ++ [ mold ];
      buildInputs = old.buildInputs ++ [ zstd zlib ];
      dontStrip = true;
      env = (old.env or { }) // {
        NIX_BUILD_ID_STYLE = "fast";
      };
      postInstall = lib.strings.replaceStrings [ "-release" ] [ "-relwithdebinfo" ] old.postInstall;
      # https://github.com/llvm/llvm-project/blob/6976deebafa8e7de993ce159aa6b82c0e7089313/clang/cmake/caches/DistributionExample-stage2.cmake#L9-L11
      cmakeFlags = old.cmakeFlags ++ [
        llvmTargetsFlag
        "-DCMAKE_BUILD_TYPE=RelWithDebInfo"
        "-DCLANG_DEFAULT_CXX_STDLIB=${if useLibcxx then "libc++" else "libstdc++"}"
        "-DLLVM_ENABLE_ZSTD=FORCE_ON"
        "-DLLVM_ENABLE_ZLIB=FORCE_ON"
        #"-DLLVM_ENABLE_MODULES=ON"
        "-DLLVM_USE_PERF=ON"
        #"-DLLVM_UNREACHABLE_OPTIMIZE=OFF"
        #"-DCMAKE_CXX_FLAGS_RELWITHDEBINFO=-fuse-ld=lld -O3 -gline-tables-only\\ -DNDEBUG"
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
          '-DCMAKE_C_FLAGS_RELWITHDEBINFO=${llvmExtraCflags}'
          '-DCMAKE_CXX_FLAGS_RELWITHDEBINFO=${llvmExtraCflags}'
        )
      '';
    })) // { libllvm = llvm; };
  # A clang that understands standard include searching
  # and expects its libc to be in the sysroot
  clang-sysrooted = (sysrootCompiler clang-unwrapped "rocm-clang-sysrooted" (listUsefulOutputs ([
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
  inherit (llvmPackagesRocm) compiler-rt; # PREV was rt-libc 
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

  # Standard wrapped clang built from ROCm LLVM tree set to use LLVM libs
  clang = clang-sysrooted;
  clang2 = ((if useLibcxx then llvmPackagesRocm.clangUseLLVM else llvmPackagesRocm.clang).override (old:
    let
      # FIXME: this needs to unsafeDiscardStringContext to prevent building the now unused replaced out parts
      # but now it's possible to have it *not* build deps
      # should make clangUseLLVM use finalAttrs.cc
      # resourceDir = symlinkJoin {
      #   name = "clang-resources-glibc";
      #   paths = [
      #     #gcc-prefix
      #     #glibc.dev
      #     "${clang-sysrooted}/lib/clang/${llvmMajorVersion}"
      #   ];
      # };
      replacedExtraBuildCommands = builtins.unsafeDiscardStringContext (builtins.replaceStrings [ "${llvmPackagesRocm.clang-unwrapped}" "${llvmPackagesRocm.clang-unwrapped.lib}" ] [ "${clang-sysrooted}" "${clang-sysrooted}" ] "${old.extraBuildCommands or ""}");
    in
    {
      cc = clang-sysrooted;
      # sysrooted clang knows how to find libcxx from its own dir
      # set to empty dir because null will default to gnu
      #libc = emptyDirectory;
      libcxx = if useLibcxx then emptyDirectory else old.libcxx;
      bintools = if useLibcxx then bintools else old.bintools;
      # old.bintools.override {
      #   inherit lld;
      # };
      extraPackages =
        if useLibcxx then [
          compiler-rt
        ] else [
          compiler-rt
          glibc
          glibc.dev
          gcc-include
        ];
      # ${verifyResourceRootValid}
      extraBuildCommands = ''
        ${replacedExtraBuildCommands}
        # cp --no-preserve=mode,ownership -rL "$rsrc" "$out/resource_tmp/"
        # rm -rf "$rsrc"
        # mv "$out/resource_tmp/" "$rsrc"
        #ln -s "$ {libcxx.dev}/include/"* "$rsrc/include/"
        # 

        ln -s ${clang-sysrooted} $out/llvm
        ln -sf ${gcc-unwrapped}/bin/ld $out/bin/lld

        # rm -rf $rsrc/include

        # TODO: is there a way to have our clang live with its resources or know there expected path without relying on this?
        cat $out/nix-support/cc-cflags
        rm $out/nix-support/cc-cflags
        ls $out/nix-support/*flags
        cat $out/nix-support/*flags
        rm $out/nix-support/*flags
        # exit 1
        echo "--sysroot=${clang-sysrooted}" >> $out/nix-support/cc-cflags
        echo "--sysroot=${clang-sysrooted} -L{clang-sysrooted}/lib" >> $out/nix-support/ld-cflags
        echo "-B${clang-sysrooted}/lib" >> $out/nix-support/libc-crt1-cflags
        # cat $out/bin/clang
        # ${clang-sysrooted}/bin/clang -print-resource-dir
        #echo '>&2 echo "clang wrapper params ''${extraBefore+"''${extraBefore[@]}"} ''${params+"''${params[@]}"} ''${extraAfter+"''${extraAfter[@]}"}"' >> $out/nix-support/cc-wrapper-hook
        #echo 'env | grep /include >&2' >> $out/nix-support/cc-wrapper-hook

        # Disable the automatic -isystem based includes Nix adds
        # because everything built on rocm should be using pkg-config
        # FIXME: numactl failures in rocm-thunk!
        # TODO: rocm-thunk is probably missing
        substituteInPlace $out/nix-support/setup-hook \
          --replace-fail '1/include"' '1/include''${NIX_DISABLE_WRAPPER_INCLUDES:+-DONOTUSE}"'

        rm -f $out/nix-support/libc-cflags || true
        rm -f $out/nix-support/libc-ldflags || true

        echo "-Wno-error=unused-command-line-argument -Wno-unused-command-line-argument" >> $out/nix-support/cc-cflags
        touch $out/nix-support/libc-cflags
        cat $out/nix-support/libc-cflags

        #exit 1
        # echo "-resource-dir=$out/resource-root" >> $out/nix-support/cc-cflags

        # FIXME: disable hardening only for offload arches
        echo "" > $out/nix-support/add-hardening.sh

        echo '
        # Calculate the core limit
        # could use ''$(nproc) / 2 instead of 1 if unset
        CORE_LIM="''${NIX_BUILD_CORES:-1}"
        if ((CORE_LIM <= 0)); then
          guess=$(nproc 2>/dev/null || true)
          ((CORE_LIM = guess <= 0 ? 1 : guess))
        fi
        CORE_LIM=$(( ''${NIX_LOAD_LIMIT:-''${CORE_LIM:-$(nproc)}} / 2 ))
        # Set HIPCC_JOBS with min and max constraints
        export HIPCC_JOBS=$(( CORE_LIM < 1 ? 1 : (CORE_LIM > 6 ? 6 : CORE_LIM) ))
        export HIPCC_JOBS_LINK=$(( CORE_LIM < 1 ? 1 : (CORE_LIM > 3 ? 3 : CORE_LIM) ))
        export HIPCC_COMPILE_FLAGS_APPEND="-O3 -Wno-format-nonliteral -parallel-jobs=$HIPCC_JOBS"
        export HIPCC_LINK_FLAGS_APPEND="-O3 -parallel-jobs=$HIPCC_JOBS_LINK"
        #export HIPCC_VERBOSE=1
        export CFLAGS=$(echo ''${CFLAGS:-} -parallel-jobs=$HIPCC_JOBS -v)
        export CXXFLAGS=$(echo ''${CFLAGS:-} -parallel-jobs=$HIPCC_JOBS -stdlib=libstdc++ -v)
        #export CXXFLAGS="''${CXXFLAGS:-} -parallel-jobs=$HIPCC_JOBS -stdlib=libstdc++"
        # FIXME: LDFLAGS applies to linker -> gfortran is the default linker for
        export LDFLAGS="''${LDFLAGS:-} -v"
        export LD=lld
        ' >> $out/nix-support/setup-hook
      '';


      #exit 1
      #echo "--gcc-toolchain=${old.gccForLibs} -resource-dir=${clang-sysrooted}" >> $out/nix-support/cc-cflags
      #echo "--gcc-toolchain=${old.gccForLibs} -internal-isystem rocm-clang-combined/lib/clang/18/c++" >> $out/nix-support/cc-cflags
      #echo "--gcc-toolchain=${old.gccForLibs} -idirafter ${clang-sysrooted}/lib/clang/18/include/c++/v1/" >> $out/nix-support/cc-cflags
      #echo "--gcc-toolchain=${old.gccForLibs} --sysroot=${clang-sysrooted} -idirafter ${clang-sysrooted}/lib/clang/18/include/c++/v1/" >> $out/nix-support/cc-cflags
      #echo "--gcc-toolchain=${old.gccForLibs} --sysroot=${clang-sysrooted} -isystem ${clang-sysrooted}/lib/clang/18/include/c++/v1/" >> $out/nix-support/cc-cflags
      # echo "--gcc-install-dir="${old.gccForLibs}/lib/gcc/*/*/ >> $out/nix-support/cc-cflags

      #echo "-rtlib=compiler-rt -B${compiler-rt.dev} --gcc-toolchain=${old.gccForLibs} --gcc-install-dir="${old.gccForLibs}/lib/gcc/*/*/ -L"${old.gccForLibs}"/lib/gcc/*/*/ >> $out/nix-support/cc-cflags

      #echo "-rtlib=compiler-rt -B${compiler-rt.dev} --gcc-install-dir="${old.gccForLibs}/lib/gcc/*/*/ -B"${old.gccForLibs}"/lib/gcc/*/*/ >> $out/nix-support/libc-ldflags
      #echo "--sysroot=${clang-sysrooted}" >> $out/nix-support/cc-cflags
      #echo "-fuse-ld=lld" >> $out/nix-support/cc-cflags
      #echo "" >> $out/nix-support/cc-cxxflags
      #extraTools = (old.extraTools or []) ++ [clang-sysrooted];
    })).overrideAttrs {
    name = "rocm-clang-combined-llvm-libs";
    inherit version;
  };

  # overridden with more tools included in the same package for monolithic install emulation
  # should only be needed for some AMD projects which link LLVM and rely on ClangTargets.cmake
  # and isn't the clang we include in rocmClangStdenv
  clangWithMoreTools = (clang2.override (old: {
    extraBuildCommands = ''${old.extraBuildCommands or ""}
      ln -s $/bin/clang $out/bin/clang-${llvmMajorVersion}
      # clang-tools = {clang-{offload-{bundler,packager,wrapper},format,linker-wrapper} and more
      ln -s ${clang-tools}/bin/* $out/bin/

      # FIXME: should these be in clang-tools?
      ln -s ${clang-unwrapped}/bin/{diag*,modu*,find-all*,pp*,*-arch} $out/bin/
    '';
  })).overrideAttrs {
    name = "rocm-clang-combined-more-tools-llvm-libs";
    inherit version;
  };

  # clang dev and lib outputs pointed at the wrapper
  # required for rocm-comgr rocm-device-libs projects not to bypass the wrapper
  clangDevWrapped = runCommandNoCC "rocm-clang-dev-wrapped" { } ''
    set -eu
    cp --no-preserve=mode,ownership -r ${clang-unwrapped.lib} $out
    cp --no-preserve=mode,ownership -r ${clang-unwrapped.dev}/* $out/
    find $out -type f -exec sed -i 's|${clang-unwrapped.out}|${clangWithMoreTools}|g' {} +
    find $out -type f -exec sed -i "s|${clang-unwrapped.dev}|$out|g" {} +
  '';

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
      #clangWithMoreTools
      clang-sysrooted
      # clangDevWrapped
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
  clang-tools-extra = callPackage ./stage-3/clang-tools-extra.nix { inherit rocmUpdateScript llvm clang-unwrapped; stdenv = rocmClangStdenv; };
  libclc = callPackage ./stage-3/libclc.nix { inherit rocmUpdateScript llvm clang; stdenv = rocmClangStdenv; };
  lldb = callPackage ./stage-3/lldb.nix { inherit rocmUpdateScript clang; stdenv = rocmClangStdenv; };
  mlir = callPackage ./stage-3/mlir.nix { inherit rocmUpdateScript clr; stdenv = rocmClangStdenv; };
  polly = callPackage ./stage-3/polly.nix { inherit rocmUpdateScript; stdenv = rocmClangStdenv; };
  #flang = callPackage ./stage-3/flang.nix { inherit rocmUpdateScript clang-unwrapped mlir; stdenv = rocmClangStdenv; };
  openmp = (llvmPackagesRocm.openmp.override {
    stdenv = rocmClangStdenv;
    # FIXME: this is wrong for cross builds
    llvm = rocm-merged-llvm;
    targetLlvm = rocm-merged-llvm;
    clang-unwrapped = clang;
  }).overrideAttrs (old: {
    cmakeFlags = old.cmakeFlags ++ [
      "-DDEVICELIBS_ROOT=${rocm-device-libs.src}"
    ];
    env.LLVM = "${rocm-merged-llvm}";
    env.LLVM_DIR = "${rocm-merged-llvm}";
    env.NIX_DISABLE_WRAPPER_INCLUDES = 1;
    env.CCC_OVERRIDE_OPTIONS = "+-v";
    buildInputs = old.buildInputs ++ [
      rocm-device-libs
      # rocm-merged-llvm
      rocm-runtime
      rocm-thunk
      zlib
      zstd
      libxml2
      libffi
    ];
  });
  #openmp = callPackage ./stage-3/openmp.nix { inherit rocmUpdateScript llvm clang-unwrapped clang rocm-device-libs rocm-runtime rocm-thunk; stdenv = rocmClangStdenv; };

  # Runtimes
  pstl = callPackage ./stage-3/pstl.nix { inherit rocmUpdateScript; stdenv = rocmClangStdenv; };
}
