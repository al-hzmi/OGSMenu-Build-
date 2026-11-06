#!/usr/bin/env python3
"""Static checks for the capacity grid and its fail-closed request path."""
from pathlib import Path

code = Path("OGSMenu/ModMenu.mm").read_text(encoding="utf-8")


def require(ok, why):
    if not ok:
        raise AssertionError(why)


start = code.index("- (void)promptRoomCapacity:(UIButton *)button {")
stop = code.index("- (void)refreshTraining51Marker", start)
picker = code[start:stop]
require("addTextFieldWithConfigurationHandler" not in picker,
        "old keyboard entry must not remain")
require("for (NSInteger desired = 2; desired <= 32; ++desired)" in picker,
        "all 31 supported values must be rendered")
require("choice.enabled = enabled;" in picker,
        "unavailable capacity buttons must not react to taps")
require("permitted && desired >= occupied && desired != current" in picker,
        "current and below-occupancy options must be disabled")
require("permitted = known && actor > 0 && master == actor" in picker,
        "a non-master must only see disabled capacity controls")
require("[self.menuPanel addSubview:panel]" in picker,
        "picker must be inside the game menu, not a stacked modal")
require("- (void)selectRoomCapacity:(UIButton *)button" in picker,
        "picker selection callback missing")
require("actor != master" in picker and "desired < occupied" in picker,
        "re-check host and live occupants at tap time")
require("gOGSRoomCapacityLastQueuedAt < 10.0" in picker,
        "preserve the existing operation cooldown")
require("gOGSRoomCapacityExpectedBefore = current" in picker,
        "preserve expected room state for the Photon frame")

rectangles = []
for n in range(2, 33):
    index = n - 2
    x = 8 + (index % 5) * 55
    y = 44 + (index // 5) * 39
    rectangles.append((x, y, x + 50, y + 31))
require(len(rectangles) == 31 and len(set(rectangles)) == 31,
        "every capacity must have a unique button")
require(all(0 <= x1 < x2 <= 290 and 0 <= y1 < y2 <= 316
            for x1, y1, x2, y2 in rectangles),
        "all capacity buttons must fit the compact menu")
for occupants in (1, 2, 8, 16, 31, 32):
    for current in range(max(occupants, 2), 33):
        enabled = [n for n in range(2, 33)
                   if n >= occupants and n != current]
        require(all(n >= occupants for n in enabled),
                "choice would admit below-occupancy capacity")
        require(current not in enabled, "choice would submit a no-op")
print("PASS capacity picker: 31 grid buttons, gray disabled states, "
      "in-bounds layout, identity/occupancy re-checks")
