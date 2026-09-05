# Recalculate history from the current Daily Target

Open Habit stores Completions and one current Daily Target for each Habit, then derives Daily Progress whenever it presents a Habit Day. Changing the Daily Target therefore reinterprets the entire history instead of preserving historical targets or stored success states. This keeps the data model truthful and small, with the deliberate consequence that changing a Habit can change how its past tiles appear.
