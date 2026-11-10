# `"string" * 0` (or a negative count) loops and allocates until out of memory (DoS)

- **Reproducer:** `oom-string-times-zero` (`"ab" * 0`); `./fuzz_eval-standalone oom-string-times-zero`.
  libFuzzer reports `out-of-memory (malloc(2013265921))` (or a timeout, depending on its limits).
- **Cause:** `Variant::operator*=` (`src/Variant.cpp`, `case type_string` / `case type_integer`) repeats the
  string with `int limit = right._integer - 1; while (limit--) _string += fragment;`. For a count of `0`
  (or any negative count) `limit` starts negative, so the loop runs ~2^31 times, doubling the string's
  length each pass of the `+=`, until memory runs out; very large positive counts behave the same way. The
  `// assert (limit < 128)` next to it was never replaced by a real bound.
- **Impact:** denial of service (CPU + memory) from any expression evaluated by `task calc`, a filter, or a
  report definition, e.g. `task calc "'ab' * 0"`.
- **Fix:** before the loop, reject counts below 1 (or return the empty string for `0`) and cap the result
  size, throwing a `std::string` like the neighbouring invalid-operand cases.
