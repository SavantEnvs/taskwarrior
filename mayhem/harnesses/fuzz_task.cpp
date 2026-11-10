#include "common.h"

#include <JSON.h>
#include <Task.h>

#include <memory>

namespace {
void exercise(Task& task) {
  (void)task.composeJSON();
  (void)task.composeJSON(true);
  (void)task.get("description");
  (void)task.getAnnotations();
  (void)task.getTags();
  (void)task.getDependencyUUIDs();
  (void)task.getStatus();
  (void)task.is_empty();
}
}  // namespace

extern "C" int LLVMFuzzerInitialize(int*, char***) {
  mayhem_init_context();
  return 0;
}

extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size) {
  if (size > kMaxInput) return -1;
  std::string text(reinterpret_cast<const char*>(data), size);

  // Legacy "[name:"value" ...]" format and JSON, auto-detected by Task::parse.
  try {
    Task task(text);
    exercise(task);
  } catch (const std::string&) {
  } catch (...) {
  }

  // `task import` path: free-form JSON object or array of objects.
  try {
    std::unique_ptr<json::value> root(json::parse(text));
    if (root) {
      if (root->type() == json::j_object) {
        Task task(static_cast<const json::object*>(root.get()));
        exercise(task);
      } else if (root->type() == json::j_array) {
        for (auto* element : static_cast<json::array*>(root.get())->_data) {
          if (element->type() != json::j_object) continue;
          Task task(static_cast<const json::object*>(element));
          exercise(task);
        }
      }
    }
  } catch (const std::string&) {
  } catch (...) {
  }
  return 0;
}
