The parts the tests read.

`golden_simple_through_hole.step` is a plate with a through hole, taken from
quiddity's own test suite (Apache-2.0); the tests stand a sensor at
`[15.0, 0.0, 23.0]` because that is the point that suite uses to reach the boss.

Nothing here is generated at test time: a fixture that has to be made first is a
test that fails on a fresh clone.
