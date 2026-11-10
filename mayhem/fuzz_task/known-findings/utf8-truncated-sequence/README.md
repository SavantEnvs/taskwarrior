# Truncated UTF-8 sequence reads past the end of the string (heap-buffer-overflow)

- **Reproducer:** `crash-1byte` (the single byte `0xEA`, a 3-byte UTF-8 lead byte with nothing after it);
  `./<target>-standalone crash-1byte`.
- **Cause:** `utf8_next_char()` in `src/libshared/src/utf8.cpp` trusts the lead byte's sequence length and does
  `i += length` without checking that the sequence fits in the string, so the cursor ends up past
  `input.length()`. Callers (`Pig::getUntilWS`, `Pig::skipWS`, `Pig::eos`, `Lexer::readWord`, ...) then read
  `input[i]` out of bounds. Reached from `Datetime::parse_named` (so from every `Lexer::isDate`), the JSON
  parser and the legacy task parser, i.e. from any command-line argument, filter, or imported task that ends
  in an incomplete multi-byte character.
- **Impact:** heap out-of-bounds read of attacker-chosen input (ASan: heap-buffer-overflow READ of 1 byte, and
  a size-N over-read in `utf8_next_char` itself).
- **Fix (one line, after `int length = utf8_sequence (input[i]);`):** clamp the sequence to the bytes that
  remain, e.g. `if (i + length > input.length ()) length = input.length () - i;`, and treat the clipped lead
  as a single character.
