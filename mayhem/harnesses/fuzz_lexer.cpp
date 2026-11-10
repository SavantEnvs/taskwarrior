#include "common.h"

#include <format.h>
#include <shared.h>

extern "C" int LLVMFuzzerInitialize(int*, char***) {
  mayhem_init_context();
  return 0;
}

extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size) {
  if (size > kMaxInput) return -1;
  std::string text(reinterpret_cast<const char*>(data), size);

  try {
    Lexer lexer(text);
    std::string token;
    Lexer::Type type;
    while (lexer.token(token, type)) (void)Lexer::typeToString(type);

    for (const auto& word : Lexer::split(text)) (void)word.size();

    std::string a, b, c, d;
    Lexer::decomposePair(text, a, b, c, d);
    Lexer::decomposeSubstitution(text, a, b, c);
    Lexer::decomposePattern(text, a, b);
    (void)Lexer::isDOM(text);
    (void)Lexer::isAllDigits(text);
    (void)Lexer::commify(text);
    (void)Lexer::trim(text, " \t");

    std::string quoted = text;
    Lexer::dequote(quoted);
    (void)Lexer::wasQuoted(text);

    std::string::size_type cursor = 0;
    std::string word;
    Lexer::readWord(text, cursor, word);
  } catch (const std::string&) {
  } catch (...) {
  }
  return 0;
}
