# frozen_string_literal: true

# Hooks the design/ doc-layer checks into rake (the layout is described in AGENTS.md, "Design docs").
# The bash script is the single implementation; this task only runs it. It needs bash and git —
# both present on a developer machine and on the CI image that runs `rake check`.

desc "Design docs: cited slugs resolve, AGENTS.md under its cap, CLAUDE.md is the shim."
task :design_tripwires do
  sh "design/verify_design_tripwires.sh"
end
