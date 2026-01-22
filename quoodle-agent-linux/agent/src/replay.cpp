#include "replay.h"

namespace quoodle {

ReplayCache::ReplayCache(AgentStateStore &state) : state_(state) {}

bool ReplayCache::Load() {
    return state_.Load();
}

long ReplayCache::NextSeq() {
    return state_.NextSequence();
}

long ReplayCache::CurrentSeq() const {
    return state_.CurrentSequence();
}

}  // namespace quoodle
