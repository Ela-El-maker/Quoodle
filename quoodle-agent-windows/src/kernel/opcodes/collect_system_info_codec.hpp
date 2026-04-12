#pragma once

#include <string>
#include "../driver_ioctl.hpp"

namespace kernel::opcodes
{

bool TryTranslateCollectSystemInfoBinaryResult(
    const QuoodleIoctlResponse &response,
    std::string &out_json);

} // namespace kernel::opcodes
