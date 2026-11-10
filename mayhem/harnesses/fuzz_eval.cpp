#include "common.h"

#include <Eval.h>
#include <Variant.h>

namespace {
bool get(const std::string& name, Variant& value) {
  if (name == "x") {
    value = Variant(true);
    return true;
  }
  return false;
}
}  // namespace

extern "C" int LLVMFuzzerInitialize(int*, char***) {
  mayhem_init_context();
  return 0;
}

extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size) {
  if (size > kMaxInput) return -1;
  std::string expression(reinterpret_cast<const char*>(data), size);

  Eval eval;
  eval.addSource(get);
  Variant result;

  try {
    eval.evaluateInfixExpression(expression, result);
    (void)static_cast<std::string>(result);
  } catch (const std::string&) {
  } catch (...) {
  }

  try {
    eval.evaluatePostfixExpression(expression, result);
    (void)static_cast<std::string>(result);
  } catch (const std::string&) {
  } catch (...) {
  }
  return 0;
}
