#!/usr/bin/env python3
"""Static play-menu checks; does not assert Photon authority or live gameplay."""

from pathlib import Path
import re


source = Path("OGSMenu/ModMenu.mm").read_text(encoding="utf-8")
start = source.index("- (void)setupMenu {")
end = source.index("- (void)showQuickNotice:", start)
menu = source[start:end]


def check(condition, message):
    if not condition:
        raise AssertionError(message)


check(source.count('self.titleLabel.text = @"OGS54";') == 2,
      "release label must be exactly OGS54 on create and refresh")
check('self.titleLabel.text = @"OGS53";' not in source,
      "stale release title")
check('self.menuPanel.contentSize = CGSizeMake(290, 352);' in menu,
      "all controls must fit within the compact scrolling canvas")
check('self.menuPanel.showsVerticalScrollIndicator = YES;' in menu,
      "show scroll affordance on compact screens")
for forbidden in (
    "toggleAdvancedMenu", "advancedControls", "advancedVisible",
    "remoteTeamLabel", "gameplayLabel", "إخفاء إعدادات الروم",
    "المزيد من إعدادات الروم", "واصل التنقل",
):
    check(forbidden not in source, f"obsolete menu/status control: {forbidden}")

# All requested actions remain mounted in the main scroll view. Each selector
# may have other occurrences elsewhere; scope this to the UI setup method.
actions = (
    "prevPlayer:", "claimHostNow:", "nextPlayer:",
    "changeSelectedTeam:", "toggleSelfFlight:", "toggleGodMode:",
    "speedDown:", "promptCustomSpeed:", "speedUp:",
    "giveHostToSelected:", "kickSelected:",
    "copySelectedName:", "showSelectedNameHistory:",
    "promptSelfNickname:", "toggleAutoHost:",
    "toggleAntiKickHardLock:", "togglePrivacyHidden:",
    "togglePrivacyClosed:", "toggleGrenade31:",
    "promptRoomCapacity:",
)
for action in actions:
    check(f"@selector({action})" in menu, f"missing play-menu action: {action}")

# The last action is above the declared 352pt content edge. All fixed-size
# button rectangles stay within the 290pt canvas and do not require a submenu.
fixed = re.findall(r"makeBtn:CGRectMake\((\d+), (\d+), (\d+), (\d+)\)", menu)
check(len(fixed) >= 19, "unexpected reduction of directly accessible actions")
for x, y, width, height in fixed:
    x, y, width, height = map(int, (x, y, width, height))
    check(x >= 0 and y >= 0 and x + width <= 290 and y + height <= 352,
          f"off-canvas button {(x, y, width, height)}")

check("[self.menuPanel setContentOffset:CGPointZero animated:NO];" in source,
      "reopening must start at the roster/team selector")
print(f"PASS OGS54 UI: {len(actions)} actions, no expander/status strips, "
      f"{len(fixed)} in-bounds fixed rectangles, scroll reset")
