#!/usr/bin/env bash
#
# mayhem/test.sh — RUN gdk-pixbuf's OWN upstream functional test suite (built by mayhem/build.sh),
# then a behavioral known-answer oracle. Never compiles here.
#
#  * Upstream suite: `meson test -C build-tests` — the full tests/meson.build suite (io/format/ops/
#    conform/security: pixbuf-jpeg, pixbuf-gif, cve-2015-4491, pixbuf-scale, pixbuf-randomly-modified,
#    ...). These are the project's real GLib/GTest assertions.
#  * Behavioral oracle: build-oracle/oracle decodes bundled test images and prints their geometry;
#    we assert the known-answer DIMS lines. This is what makes test.sh sabotage-proof: the meson
#    test BINARIES are themselves project executables, so the §6.3 neuter (_exit(0) in every project
#    binary) makes them exit 0 and meson would still see "OK" — but the neutered oracle prints
#    nothing, so its known-answer grep FAILS and test.sh fails. A no-op PATCH cannot pass this.
#  * Emits a CTRF summary and exits nonzero on any failure.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${MAYHEM_JOBS:=$(nproc)}"
SRC="${SRC:-/mayhem}"
cd "$SRC"

emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

passed=0; failed=0; skipped=0

# --- 1) upstream meson test suite ------------------------------------------------------------------
if [ ! -d build-tests ]; then
  echo "test.sh: build-tests/ missing — mayhem/build.sh must build the test suite" >&2
  emit_ctrf gdk-pixbuf 0 1 0; exit 1
fi
mout="$(meson test -C build-tests --no-rebuild --print-errorlogs 2>&1)" || true
echo "$mout"
m_ok=$(printf '%s\n' "$mout"      | sed -n 's/^Ok:[[:space:]]*\([0-9][0-9]*\).*/\1/p'          | tail -1)
m_fail=$(printf '%s\n' "$mout"    | sed -n 's/^Fail:[[:space:]]*\([0-9][0-9]*\).*/\1/p'        | tail -1)
m_xfail=$(printf '%s\n' "$mout"   | sed -n 's/^Expected Fail:[[:space:]]*\([0-9][0-9]*\).*/\1/p' | tail -1)
m_skip=$(printf '%s\n' "$mout"    | sed -n 's/^Skipped:[[:space:]]*\([0-9][0-9]*\).*/\1/p'     | tail -1)
m_tmo=$(printf '%s\n' "$mout"     | sed -n 's/^Timeout:[[:space:]]*\([0-9][0-9]*\).*/\1/p'     | tail -1)
: "${m_ok:=0}" "${m_fail:=0}" "${m_xfail:=0}" "${m_skip:=0}" "${m_tmo:=0}"
# A meson run that produced no summary at all is a harness/build failure, not "0 tests".
if ! printf '%s\n' "$mout" | grep -q '^Ok:'; then
  echo "test.sh: meson test produced no summary — treating as failure" >&2
  emit_ctrf gdk-pixbuf "$passed" $(( failed + 1 )) "$skipped"; exit 1
fi
passed=$(( passed + m_ok + m_xfail ))
failed=$(( failed + m_fail + m_tmo ))
skipped=$(( skipped + m_skip ))
echo "meson test: ok=$m_ok fail=$m_fail xfail=$m_xfail skipped=$m_skip timeout=$m_tmo"

# --- 2) behavioral known-answer oracle -------------------------------------------------------------
ORACLE=build-oracle/oracle
check() { if [ "$2" = "$3" ]; then echo "  ok   - $1"; passed=$((passed+1)); else echo "  FAIL - $1 (got '$2' want '$3')"; failed=$((failed+1)); fi; }
if [ ! -x "$ORACLE" ]; then
  echo "test.sh: $ORACLE missing — build.sh must build it" >&2
  emit_ctrf gdk-pixbuf "$passed" $(( failed + 1 )) "$skipped"; exit 1
fi
# image -> expected `DIMS WxH ch=.. bps=.. alpha=..` (deterministic across the png/gif/jpeg/tiff loaders)
oracle_case() { check "oracle decodes $(basename "$1")" "$("$ORACLE" "$1" 2>/dev/null)" "$2"; }
oracle_case tests/dpi.png  "DIMS 48x48 ch=4 bps=8 alpha=1"
oracle_case tests/dpi.jpeg "DIMS 48x48 ch=3 bps=8 alpha=0"
oracle_case tests/dpi.tiff "DIMS 48x48 ch=4 bps=8 alpha=1"
oracle_case tests/aero.gif "DIMS 350x189 ch=4 bps=8 alpha=1"

echo "test.sh: passed=$passed failed=$failed skipped=$skipped"
emit_ctrf gdk-pixbuf "$passed" "$failed" "$skipped"
