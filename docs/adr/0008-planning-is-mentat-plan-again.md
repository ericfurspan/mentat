# Planning is `/mentat:plan` again, with no alias

Planning was renamed from `/mentat:plan` to `/mentat:propose` before 1.0, while the rules and skills still call the step planning. It is `/mentat:plan` again, and `/mentat:propose` is removed with no alias, because the command should name the step it runs, and before 1.0 there is no compatibility promise that an alias would keep, only a second name for every skill, check and eval to carry; `tests/run` fails when any file but `CHANGELOG.md` and these records names the old skill.
