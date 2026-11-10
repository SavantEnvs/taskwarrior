#!/usr/bin/env bash
#
# mayhem/build.sh — build taskwarrior's fuzz harnesses and its own test suite.
# Runs inside the commit image (mayhem/Dockerfile) as `mayhem` in /mayhem, online at image build and
# again offline (--network none) at the PATCH tier: every Rust crate comes from the in-image CARGO_HOME.
set -euo pipefail

# clang rejects SOURCE_DATE_EPOCH='' (empty) — it must be unset or a valid integer.
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

# `=` (not `:=`): an explicit empty SANITIZER_FLAGS builds with no sanitizers.
: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${SRC:=/mayhem}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

# Rust (taskchampion) is linked in unsanitized and without DWARF, so the harness CU stays first and DWARF <= 3.
export CARGO_PROFILE_RELEASE_DEBUG=0
# Offline once the in-image registry cache is populated (first online build fills it); the re-run is air-gapped.
export CARGO_NET_OFFLINE="${CARGO_NET_OFFLINE:-}"
if [ -z "$CARGO_NET_OFFLINE" ] && [ -n "$(ls -A "${CARGO_HOME:-$HOME/.cargo}/registry/cache" 2>/dev/null)" ]; then
  CARGO_NET_OFFLINE=true
fi
[ -n "$CARGO_NET_OFFLINE" ] || unset CARGO_NET_OFFLINE

cd "$SRC"

# The image build may configure through rlenv's ccache masquerade (/opt/mayhem/ccache/bin/clang) while a
# re-run resolves plain clang; CMake then discards its cache mid-configure and loses the -D settings.
# Start the CMake trees fresh every time (objects come from ccache); cargo-target is kept.
rm -rf build-fuzz build-tests

# --- 1) The project, sanitized (fuzzed code is instrumented), into build-fuzz/ ---------------------
# Release for the Rust side; the C++ optimization level is pinned to -O1 with assertions kept (no -DNDEBUG).
# CORROSION_CARGO_TARGET_DIR: corrosion's default target dir is computed from the manifest path and
# lands outside the tree (/mayhem_<hash>) when the source root is /mayhem.
cmake -S . -B build-fuzz -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_COMPILER="$CC" -DCMAKE_CXX_COMPILER="$CXX" \
  -DCMAKE_C_FLAGS="$SANITIZER_FLAGS $DEBUG_FLAGS -fsanitize=fuzzer-no-link" \
  -DCMAKE_CXX_FLAGS="$SANITIZER_FLAGS $DEBUG_FLAGS -fsanitize=fuzzer-no-link" \
  -DCMAKE_C_FLAGS_RELEASE=-O1 -DCMAKE_CXX_FLAGS_RELEASE=-O1 \
  -DCMAKE_EXE_LINKER_FLAGS="$SANITIZER_FLAGS" \
  -DTASK_USE_CORROSION_SUBMODULE=ON -DENABLE_TLS_NATIVE_ROOTS=OFF \
  -DCORROSION_CARGO_TARGET_DIR=cargo-target \
  -DFETCHCONTENT_SOURCE_DIR_CORROSION="$SRC/src/taskchampion-cpp/corrosion" -DFETCHCONTENT_FULLY_DISCONNECTED=ON
cmake --build build-fuzz -j"$MAYHEM_JOBS" --target task libshared commands columns

B="$SRC/build-fuzz"
INCLUDES=$(python3 - "$B/compile_commands.json" <<'PY'
import json, shlex, sys
for e in json.load(open(sys.argv[1])):
    if e["file"].endswith("src/Context.cpp"):
        args = shlex.split(e["command"])
        print(" ".join(shlex.quote(a) for i, a in enumerate(args)
                       if a.startswith(("-I", "-isystem", "-D", "-std=")) or (i and args[i-1] == "-isystem")))
        break
PY
)
LIBS="-Wl,--start-group $B/src/libtask.a $B/src/commands/libcommands.a $B/src/columns/libcolumns.a \
 $B/src/liblibshared.a $B/src/taskchampion-cpp/libtaskchampion-cpp.a $B/src/taskchampion-cpp/libtaskchampion_lib.a \
 -Wl,--end-group -luuid -lgcc_s -lutil -lrt -lpthread -lm -ldl"

# --- 2) Harnesses: fuzzer binary + -standalone reproducer each ------------------------------------
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -c "$STANDALONE_FUZZ_MAIN" -o "$B/standalone_main.o"
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS -c "$SRC/mayhem/lsan_off.cc" -o "$B/lsan_off.o"
for t in fuzz_lexer fuzz_eval fuzz_task fuzz_datetime; do
  # shellcheck disable=SC2086
  $CXX $SANITIZER_FLAGS $DEBUG_FLAGS -O1 -fsanitize=fuzzer-no-link $INCLUDES -I"$SRC/mayhem/harnesses" \
    -c "$SRC/mayhem/harnesses/$t.cpp" -o "$B/$t.o"
  # shellcheck disable=SC2086
  $CXX $SANITIZER_FLAGS $LIB_FUZZING_ENGINE "$B/$t.o" "$B/lsan_off.o" $LIBS -o "$SRC/$t"
  # shellcheck disable=SC2086
  $CXX $SANITIZER_FLAGS "$B/$t.o" "$B/standalone_main.o" "$B/lsan_off.o" $LIBS -o "$SRC/$t-standalone"
done

# --- 3) The project's own test suite, normal flags, clean tree (test.sh only RUNS it) -------------
env -u CFLAGS -u CXXFLAGS -u LDFLAGS cmake -S . -B build-tests -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_COMPILER="$CC" -DCMAKE_CXX_COMPILER="$CXX" \
  -DCMAKE_C_FLAGS="$COVERAGE_FLAGS" -DCMAKE_CXX_FLAGS="$COVERAGE_FLAGS" \
  -DTASK_USE_CORROSION_SUBMODULE=ON -DENABLE_TLS_NATIVE_ROOTS=OFF \
  -DCORROSION_CARGO_TARGET_DIR=cargo-target \
  -DFETCHCONTENT_SOURCE_DIR_CORROSION="$SRC/src/taskchampion-cpp/corrosion" -DFETCHCONTENT_FULLY_DISCONNECTED=ON
cmake --build build-tests -j"$MAYHEM_JOBS" --target task_executable calc_executable lex_executable test_runner
