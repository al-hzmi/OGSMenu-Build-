#pragma once
#include "OGSGameplayPolicy.h"
namespace ogs47 {
// Receiver's explicit per-request approval permits an administrative team move.
// It does not bypass busy/unsupported-mode conditions or fabricate a team field.
inline ogs46::Denial approvedTeamDecision(int target, int current, int respawn,
                                         ogs46::Mode mode) {
    using namespace ogs46;
    if (target < 0 || target > 2 || current < 0 || current > 2) return Denial::Invalid;
    if (respawn != -1) return Denial::Busy;
    if (target == current) return Denial::SameTeam;
    if (!target) return Denial::None;
    if (mode == Mode::FFA) return target == 1 ? Denial::None : Denial::Mode;
    return mode == Mode::TDM || mode == Mode::Normal ? Denial::None : Denial::Mode;
}
inline bool canApply(ogs46::Identity requested, ogs46::Identity live,
                     int sender, int liveMaster, bool approved, double age) {
    return approved && ogs46::same(requested, live) && sender > 0 &&
        sender != live.actor && sender == liveMaster && std::isfinite(age) && age >= 0. && age < 30.;
}
}
