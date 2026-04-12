#pragma once

namespace command
{

// Returns true when argv declares screenshot helper mode.
bool IsScreenshotHelperInvocation(int argc, char **argv);

// Runs helper mode if requested. Returns:
//   >=0 process exit code if helper mode was handled
//   -1 if argv is not helper mode
int TryRunScreenshotHelper(int argc, char **argv);

} // namespace command
