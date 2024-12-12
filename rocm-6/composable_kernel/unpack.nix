{ runCommandLocal
, composable_kernel_build
, zstd
}:
let
  ck = composable_kernel_build;
in
runCommandLocal "unpack-${ck.name}"
{
  nativeBuildInputs = [ zstd ];
  inherit (ck) meta;
} ''
  mkdir -p $out
  cp -r --no-preserve=mode ${ck}/* $out
  for zs in $out/lib/libdevice_*_operations.a.zst; do
    zstd -dv --rm "$zs" -o "''${zs/.zst}"
  done
  substituteInPlace $out/lib/cmake/composable_kernel/*.cmake \
    --replace "${ck}" "$out"
''
