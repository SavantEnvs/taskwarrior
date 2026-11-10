#include "common.h"

#include <recur.h>

#include <optional>

// Input: <datetime>\n<format-or-period>\n<duration>; missing lines are empty.
extern "C" int LLVMFuzzerInitialize(int*, char***) {
  mayhem_init_context();
  return 0;
}

extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size) {
  if (size > kMaxInput) return -1;
  std::string text(reinterpret_cast<const char*>(data), size);

  std::string line[3];
  std::string::size_type start = 0;
  for (int i = 0; i < 3; ++i) {
    auto end = text.find('\n', start);
    if (end == std::string::npos || i == 2) {
      line[i] = text.substr(start);
      break;
    }
    line[i] = text.substr(start, end - start);
    start = end + 1;
  }

  try {
    Datetime dt(line[0]);
    (void)dt.toISO();
    (void)dt.toEpochString();
    (void)dt.toString("Y-M-D H:N:S");
    (void)dt.dayOfWeek();
    (void)dt.week();
    (void)dt.startOfWeek();
    (void)dt.startOfMonth();
    (void)dt.startOfYear();
    (void)Datetime::valid(line[0]);
    Datetime dt_fmt(line[0], line[1]);
    (void)dt_fmt.toString(line[1]);
  } catch (const std::string&) {
  } catch (...) {
  }

  try {
    Duration dur(line[2]);
    (void)dur.format();
    (void)dur.formatISO();
    (void)dur.formatVague();
    (void)dur.formatHours();
  } catch (const std::string&) {
  } catch (...) {
  }

  try {
    Datetime base(line[0]);
    auto next = getNextRecurrence(base, line[1]);
    if (next) (void)next->toISO();
    Datetime base2(static_cast<time_t>(1700000000));
    auto next2 = getNextRecurrence(base2, line[2]);
    if (next2) (void)next2->toISO();
  } catch (const std::string&) {
  } catch (...) {
  }
  return 0;
}
