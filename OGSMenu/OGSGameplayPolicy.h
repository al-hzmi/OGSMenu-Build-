#pragma once
#include <cmath>
#include <cstdint>

namespace ogs46 {
enum class Mode { Unknown, TDM, Normal, FFA };
enum class Denial { None, Invalid, Busy, SameTeam, Mode, Balance };
// Reproduces ScoreboardWindow's actual enable conditions. Team 0 is spectator.
inline Denial teamDecision(int target, int current, int respawn, int a, int b, Mode mode) {
    if (target < 0 || target > 2 || current < 0 || current > 2 || a < 0 || b < 0)
        return Denial::Invalid;
    if (respawn != -1) return Denial::Busy;
    if (target == current) return Denial::SameTeam;
    if (!target) return current ? Denial::None : Denial::SameTeam;
    if (mode == Mode::FFA) return target == 1 ? Denial::None : Denial::Mode;
    if (mode != Mode::TDM && mode != Mode::Normal) return Denial::Mode;
    bool balanced = target == 1 ? b > a : a > b;
    if (current == 0 && a == b) balanced = true;
    return balanced ? Denial::None : Denial::Balance;
}
struct Identity { uintptr_t room = 0, controller = 0, player = 0; int actor = 0; };
inline bool same(Identity a, Identity b) {
    return a.room && a.controller && a.actor > 0 && a.room == b.room &&
        a.controller == b.controller && a.actor == b.actor && a.player == b.player;
}
inline float verticalStep(int axis, float dt, bool paused) {
    if (paused || !std::isfinite(dt) || dt <= 0.f || dt > .1f) return 0.f;
    return (axis > 0 ? 1.f : axis < 0 ? -1.f : 0.f) * 5.f * dt;
}
// Flight must use a monotonic REAL interval. Unity's Time.deltaTime changes
// when the menu adjusts Time.timeScale, making flight appear to stall at high
// speed (deltaTime > .1) or crawl at low speed. Skip long pauses/lag spikes.
inline float realFlightInterval(double current, double previous) {
    if (!std::isfinite(current) || !std::isfinite(previous) || previous <= 0.) return 0.f;
    double elapsed = current - previous;
    return elapsed > 0. && elapsed <= .1 ? static_cast<float>(elapsed) : 0.f;
}
// Restores configuration on normal return and C++ stack unwinding. Values are
// borrowed for one native Update only; never retained across scene destruction.
struct MovementLease {
    float &gravity; uint8_t &air; float previousGravity; uint8_t previousAir;
    MovementLease(float &g, uint8_t &a) : gravity(g), air(a), previousGravity(g), previousAir(a) {
        gravity = 0.f; air = 1;
    }
    ~MovementLease() { gravity = previousGravity; air = previousAir; }
    MovementLease(const MovementLease &) = delete;
    MovementLease &operator=(const MovementLease &) = delete;
};
}
