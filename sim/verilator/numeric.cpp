#include "numeric.h"

#include <charconv>
#include <system_error>

namespace dc_sim {

bool parse_unsigned(std::string_view text, std::uint64_t *value) {
  if (text.empty() || value == nullptr) {
    return false;
  }

  int base = 10;
  if (text.size() >= 2 && text[0] == '0' &&
      (text[1] == 'x' || text[1] == 'X')) {
    base = 16;
    text.remove_prefix(2);
    if (text.empty()) {
      return false;
    }
  }

  for (char character : text) {
    const bool decimal_digit = character >= '0' && character <= '9';
    const bool lowercase_hex = character >= 'a' && character <= 'f';
    const bool uppercase_hex = character >= 'A' && character <= 'F';
    if (!decimal_digit &&
        (base != 16 || (!lowercase_hex && !uppercase_hex))) {
      return false;
    }
  }

  std::uint64_t parsed = 0;
  const auto result =
      std::from_chars(text.data(), text.data() + text.size(), parsed, base);
  if (result.ec != std::errc() || result.ptr != text.data() + text.size()) {
    return false;
  }
  *value = parsed;
  return true;
}

}  // namespace dc_sim
