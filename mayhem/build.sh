#!/usr/bin/env bash
#
# mayhem/build.sh — build gdk-pixbuf's fuzz harnesses + the project's own test suite.
#
# Produces (all under /mayhem):
#   build/<harness>              sanitized + libFuzzer  -> Mayhem targets (5 in-process libFuzzer harnesses)
#   build/<harness>-standalone   sanitized + StandaloneFuzzTargetMain -> run-once reproducers
#   build-tests/                 CLEAN meson build with tests=true      -> upstream `meson test` suite
#   build-oracle/oracle          CLEAN behavioral oracle binary         -> known-answer decode check
#
# The gdk-pixbuf LIBRARY itself is compiled with $SANITIZER_FLAGS + $DEBUG_FLAGS and all image
# loaders built in (-Dbuiltin_loaders=all), so ASan/UBSan instrument the decoders the harnesses
# drive — not just the harness. Fully air-gapped: every dependency (glib, libpng, libjpeg, libtiff,
# meson, ninja) is an apt package baked into the image by mayhem/Dockerfile, so no meson subproject
# (glib.wrap/libpng.wrap/...) is ever fetched. Additive only — no upstream files are edited.
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
: "${STANDALONE_FUZZ_MAIN:=/opt/mayhem/StandaloneFuzzTargetMain.c}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

SRC="${SRC:-/mayhem}"
cd "$SRC"

PREFIX="$SRC/prefix"
HARNESSES="animation_fuzzer pixbuf_cons_fuzzer pixbuf_file_fuzzer pixbuf_scale_fuzzer stream_fuzzer"

rm -rf build build-fuzz build-tests build-oracle "$PREFIX"
mkdir -p build build-oracle

# Meson options common to both trees: build every loader in-tree, disable everything we don't need
# (introspection/docs/man/thumbnailer/glycin/android) so the build is self-contained and offline.
COMMON_OPTS=(
  -Dbuiltin_loaders=all
  -Dintrospection=disabled -Dman=false -Ddocumentation=false
  -Dthumbnailer=disabled -Dglycin=disabled -Dandroid=disabled
  -Dgio_sniffing=false -Dinstalled_tests=false
)

# 1) Build the gdk-pixbuf LIBRARY, sanitized + DWARF<4, as a static lib and install to $PREFIX so we
#    can link the harnesses against it via pkg-config (loaders are built in, so png/jpeg/tiff decode
#    paths are instrumented).
CC="$CC" CXX="$CXX" meson setup build-fuzz \
  "${COMMON_OPTS[@]}" -Dtests=false \
  --default-library=static --prefix="$PREFIX" --libdir=lib \
  -Dc_args="$SANITIZER_FLAGS $DEBUG_FLAGS" \
  -Dc_link_args="$SANITIZER_FLAGS"
ninja -C build-fuzz -j"$MAYHEM_JOBS"
ninja -C build-fuzz install

export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig"
PC_CFLAGS="$(pkg-config --cflags gdk-pixbuf-2.0)"
PC_LIBS="$(pkg-config --static --libs gdk-pixbuf-2.0)"

# 2) Each harness twice: a libFuzzer binary (the Mayhem target) and a StandaloneFuzzTargetMain
#    run-once reproducer. Both keep $SANITIZER_FLAGS + $DEBUG_FLAGS.
for h in $HARNESSES; do
  # shellcheck disable=SC2086
  $CC $SANITIZER_FLAGS $DEBUG_FLAGS $LIB_FUZZING_ENGINE \
      -I"$SRC/mayhem/targets" $PC_CFLAGS \
      "$SRC/mayhem/targets/$h.c" $PC_LIBS -o "build/$h"
  # shellcheck disable=SC2086
  $CC $SANITIZER_FLAGS $DEBUG_FLAGS \
      -I"$SRC/mayhem/targets" $PC_CFLAGS \
      "$STANDALONE_FUZZ_MAIN" "$SRC/mayhem/targets/$h.c" $PC_LIBS -o "build/$h-standalone"
done

# 3) The project's OWN test suite: a CLEAN (no sanitizer/fuzzer) shared build with tests=true, so
#    mayhem/test.sh only has to RUN `meson test`. $COVERAGE_FLAGS (empty by default) instruments it
#    when a coverage build is requested.
CC="$CC" CXX="$CXX" meson setup build-tests \
  "${COMMON_OPTS[@]}" -Dtests=true \
  --default-library=shared \
  -Dc_args="$COVERAGE_FLAGS" -Dc_link_args="$COVERAGE_FLAGS"
ninja -C build-tests -j"$MAYHEM_JOBS"

# 3b) A CLEAN behavioral oracle binary (decodes an image via the public API and prints its
#     geometry). test.sh asserts known-answer output — a neutered library prints nothing and fails.
SODIR="$SRC/build-tests/gdk-pixbuf"
# shellcheck disable=SC2086
$CC -O2 $COVERAGE_FLAGS \
    -I"$SRC" -I"$SRC/build-tests" \
    $(pkg-config --cflags glib-2.0 gobject-2.0) \
    "$SRC/mayhem/oracle.c" \
    -L"$SODIR" -lgdk_pixbuf-2.0 $(pkg-config --libs glib-2.0 gobject-2.0) \
    -Wl,-rpath,"$SODIR" -o build-oracle/oracle

echo "build.sh: built harnesses [$HARNESSES] (+ -standalone), build-tests suite, and build-oracle/oracle"
