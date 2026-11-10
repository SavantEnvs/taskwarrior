// cmake.h include header must come first
#include <cmake.h>

#include <Context.h>
#include <Datetime.h>
#include <Duration.h>
#include <Lexer.h>

#include <cstddef>
#include <cstdint>
#include <string>

// One global Context for the whole process, built once; Task, Eval and the
// Datetime/Duration parsers read process-wide configuration through it.
// Same operating parameters as Context::staticInitialization.
static inline void mayhem_init_context() {
  static Context* ctx = new Context();
  Context::setContext(ctx);
  Datetime::standaloneDateEnabled = false;
  Datetime::standaloneTimeEnabled = false;
  Duration::standaloneSecondsEnabled = false;
}

static constexpr size_t kMaxInput = 4096;
