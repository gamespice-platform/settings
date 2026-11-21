extends RefCounted

## GameSpice Settings' API level. The rule for bumping it is on [GSAddonApi].

# 1: everything before this file existed (an absent file reads as 1).
# 2: GSSettingsScratch: a per-process scratch settings directory (use, is_scratch, sweep_dead).

const LEVEL := 2

## The oldest level a game built against an earlier one still runs on.
const OLDEST := 1
