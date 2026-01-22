#pragma once

#include "state_store.h"

namespace quoodle {

class ReplayCache {
public:
    explicit ReplayCache(AgentStateStore &state);
    bool Load();
    long NextSeq();
    long CurrentSeq() const;

private:
    AgentStateStore &state_;
};

}  // namespace quoodle
