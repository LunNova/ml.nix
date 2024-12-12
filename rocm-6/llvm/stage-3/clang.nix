{ stdenv
, wrapCCWith
, llvm
, lld
, rocm-merged-llvm
, clang-unwrapped
, clang-tools
, bintools
, libunwind
, libcxx
, compiler-rt
, symlinkJoin
}:
let bintools' = builtins.trace "bintools ${bintools} bintools.libc_dev ${bintools.libc_dev}" bintools;

in
wrapCCWith rec {
  inherit libcxx;
  bintools = bintools'; #bintools';
  #libc = compiler-rt;

  # We do this to avoid HIP pathing problems, and mimic a monolithic install
  cc = stdenv.mkDerivation (_finalAttrs: {
    inherit (clang-unwrapped) version;
    pname = "rocm-llvm-clang";
    dontUnpack = true;

    installPhase = ''
      runHook preInstall

      # FIXME: rstdenv version of this was picking /18.0.0/include but /18/include was what existed
      clang_version=`${clang-unwrapped}/bin/clang -v 2>&1 | grep "clang version " | grep -E -o '[0-9]+' | head -n1`
      mkdir -p $out/{bin,include/c++/v1,lib/{cmake,clang/$clang_version/{include,lib}},libexec,share}

      for path in ${rocm-merged-llvm}; do
        cp -as $path/* $out
        chmod +w $out/{*,include/c++/v1,lib/{clang/$clang_version/include,cmake}}
        #rm -f $out/lib/libc++.so
      done

      #rm $out/bin/ld
      #ln -s ${lld}/bin/ld.lld $out/bin/ld
      ln -s $out/lib/* $out/lib/clang/$clang_version/lib
      ln -sf $out/include/* $out/lib/clang/$clang_version/include

      runHook postInstall
    '';

    passthru.isClang = true;
  });

  extraPackages = [
    llvm
    lld
    libcxx
    libunwind
    compiler-rt
    clang-tools
  ];

  nixSupport.cc-cflags = [
    # "-resource-dir=$out/resource-root"
    # "-fuse-ld=lld"
    # "-rtlib=compiler-rt"
    # "-unwindlib=libunwind"
    # "-Wno-unused-command-line-argument"
  ];

  nixSupport.cc-cxxflags = [
    # "-resource-dir=$out/resource-root"
    # "-fuse-ld=lld"
    # "-rtlib=compiler-rt"
    # "-unwindlib=libunwind"
    # "-Wno-unused-command-line-argument"

  ];

  extraBuildCommands = ''
    set -eu
    clang_version=`${cc}/bin/clang -v 2>&1 | grep "clang version " | grep -E -o '[0-9]+' | head -n1`
    mkdir -p $out/resource-root
    ln -s ${cc}/lib/clang/$clang_version/{include,lib} $out/resource-root
    ln -s ${rocm-merged-llvm}/lib/clang/$clang_version/{include,lib} $out/
    #ln -s ${rocm-merged-llvm}/ $out/resource-root
    #exit 1

    # Not sure why, but hardening seems to make things break
    echo "" > $out/nix-support/add-hardening.sh

    # GPU compilation uses builtin `lld`
    substituteInPlace $out/bin/{clang,clang++} \
      --replace-fail "-MM) dontLink=1 ;;" "-MM | --cuda-device-only) dontLink=1 ;;''\n--cuda-host-only | --cuda-compile-host-device) dontLink=0 ;;"
  '';
}
