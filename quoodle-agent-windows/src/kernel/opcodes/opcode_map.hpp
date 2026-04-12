#pragma once

#include <string>

#include "../driver_ioctl.hpp"

namespace kernel::opcodes
{

QuoodleOpcode MapOpcodeToCode(const std::string &opcode);

} // namespace kernel::opcodes
