{ lib, inputs, ... }:

let
  m = inputs.bmad-method;
  c = inputs.bmad-cis;
  t = inputs.bmad-tea;
  b = inputs.bmad-builder;

  bmadSkills = [
    { n = "bmad-advanced-elicitation";              s = "${m}/src/core-skills/bmad-advanced-elicitation"; }
    { n = "bmad-agent-analyst";                     s = "${m}/src/bmm-skills/1-analysis/bmad-agent-analyst"; }
    { n = "bmad-agent-architect";                   s = "${m}/src/bmm-skills/3-solutioning/bmad-agent-architect"; }
    { n = "bmad-agent-builder";                     s = "${b}/skills/bmad-agent-builder"; }
    { n = "bmad-agent-dev";                         s = "${m}/src/bmm-skills/4-implementation/bmad-agent-dev"; }
    { n = "bmad-agent-pm";                          s = "${m}/src/bmm-skills/2-plan-workflows/bmad-agent-pm"; }
    { n = "bmad-agent-tech-writer";                 s = "${m}/src/bmm-skills/1-analysis/bmad-agent-tech-writer"; }
    { n = "bmad-agent-ux-designer";                 s = "${m}/src/bmm-skills/2-plan-workflows/bmad-agent-ux-designer"; }
    { n = "bmad-bmb-setup";                         s = "${b}/skills/bmad-bmb-setup"; }
    { n = "bmad-brainstorming";                     s = "${m}/src/core-skills/bmad-brainstorming"; }
    { n = "bmad-check-implementation-readiness";    s = "${m}/src/bmm-skills/3-solutioning/bmad-check-implementation-readiness"; }
    { n = "bmad-checkpoint-preview";                s = "${m}/src/bmm-skills/4-implementation/bmad-checkpoint-preview"; }
    { n = "bmad-cis-agent-brainstorming-coach";     s = "${c}/src/skills/bmad-cis-agent-brainstorming-coach"; }
    { n = "bmad-cis-agent-creative-problem-solver"; s = "${c}/src/skills/bmad-cis-agent-creative-problem-solver"; }
    { n = "bmad-cis-agent-design-thinking-coach";   s = "${c}/src/skills/bmad-cis-agent-design-thinking-coach"; }
    { n = "bmad-cis-agent-innovation-strategist";   s = "${c}/src/skills/bmad-cis-agent-innovation-strategist"; }
    { n = "bmad-cis-agent-presentation-master";     s = "${c}/src/skills/bmad-cis-agent-presentation-master"; }
    { n = "bmad-cis-agent-storyteller";             s = "${c}/src/skills/bmad-cis-agent-storyteller"; }
    { n = "bmad-cis-design-thinking";               s = "${c}/src/skills/bmad-cis-design-thinking"; }
    { n = "bmad-cis-innovation-strategy";           s = "${c}/src/skills/bmad-cis-innovation-strategy"; }
    { n = "bmad-cis-problem-solving";               s = "${c}/src/skills/bmad-cis-problem-solving"; }
    { n = "bmad-cis-storytelling";                  s = "${c}/src/skills/bmad-cis-storytelling"; }
    { n = "bmad-code-review";                       s = "${m}/src/bmm-skills/4-implementation/bmad-code-review"; }
    { n = "bmad-correct-course";                    s = "${m}/src/bmm-skills/4-implementation/bmad-correct-course"; }
    { n = "bmad-create-architecture";               s = "${m}/src/bmm-skills/3-solutioning/bmad-create-architecture"; }
    { n = "bmad-create-epics-and-stories";          s = "${m}/src/bmm-skills/3-solutioning/bmad-create-epics-and-stories"; }
    { n = "bmad-create-prd";                        s = "${m}/src/bmm-skills/2-plan-workflows/bmad-create-prd"; }
    { n = "bmad-create-story";                      s = "${m}/src/bmm-skills/4-implementation/bmad-create-story"; }
    { n = "bmad-create-ux-design";                  s = "${m}/src/bmm-skills/2-plan-workflows/bmad-create-ux-design"; }
    { n = "bmad-dev-story";                         s = "${m}/src/bmm-skills/4-implementation/bmad-dev-story"; }
    { n = "bmad-distillator";                       s = "${m}/src/core-skills/bmad-distillator"; }
    { n = "bmad-document-project";                  s = "${m}/src/bmm-skills/1-analysis/bmad-document-project"; }
    { n = "bmad-domain-research";                   s = "${m}/src/bmm-skills/1-analysis/research/bmad-domain-research"; }
    { n = "bmad-edit-prd";                          s = "${m}/src/bmm-skills/2-plan-workflows/bmad-edit-prd"; }
    { n = "bmad-editorial-review-prose";            s = "${m}/src/core-skills/bmad-editorial-review-prose"; }
    { n = "bmad-editorial-review-structure";        s = "${m}/src/core-skills/bmad-editorial-review-structure"; }
    { n = "bmad-generate-project-context";          s = "${m}/src/bmm-skills/3-solutioning/bmad-generate-project-context"; }
    { n = "bmad-help";                              s = "${m}/src/core-skills/bmad-help"; }
    { n = "bmad-index-docs";                        s = "${m}/src/core-skills/bmad-index-docs"; }
    { n = "bmad-market-research";                   s = "${m}/src/bmm-skills/1-analysis/research/bmad-market-research"; }
    { n = "bmad-module-builder";                    s = "${b}/skills/bmad-module-builder"; }
    { n = "bmad-party-mode";                        s = "${m}/src/core-skills/bmad-party-mode"; }
    { n = "bmad-prfaq";                             s = "${m}/src/bmm-skills/1-analysis/bmad-prfaq"; }
    { n = "bmad-product-brief";                     s = "${m}/src/bmm-skills/1-analysis/bmad-product-brief"; }
    { n = "bmad-qa-generate-e2e-tests";             s = "${m}/src/bmm-skills/4-implementation/bmad-qa-generate-e2e-tests"; }
    { n = "bmad-quick-dev";                         s = "${m}/src/bmm-skills/4-implementation/bmad-quick-dev"; }
    { n = "bmad-retrospective";                     s = "${m}/src/bmm-skills/4-implementation/bmad-retrospective"; }
    { n = "bmad-review-adversarial-general";        s = "${m}/src/core-skills/bmad-review-adversarial-general"; }
    { n = "bmad-review-edge-case-hunter";           s = "${m}/src/core-skills/bmad-review-edge-case-hunter"; }
    { n = "bmad-shard-doc";                         s = "${m}/src/core-skills/bmad-shard-doc"; }
    { n = "bmad-sprint-planning";                   s = "${m}/src/bmm-skills/4-implementation/bmad-sprint-planning"; }
    { n = "bmad-sprint-status";                     s = "${m}/src/bmm-skills/4-implementation/bmad-sprint-status"; }
    { n = "bmad-tea";                               s = "${t}/src/agents/bmad-tea"; }
    { n = "bmad-teach-me-testing";                  s = "${t}/src/workflows/testarch/bmad-teach-me-testing"; }
    { n = "bmad-technical-research";                s = "${m}/src/bmm-skills/1-analysis/research/bmad-technical-research"; }
    { n = "bmad-testarch-atdd";                     s = "${t}/src/workflows/testarch/bmad-testarch-atdd"; }
    { n = "bmad-testarch-automate";                 s = "${t}/src/workflows/testarch/bmad-testarch-automate"; }
    { n = "bmad-testarch-ci";                       s = "${t}/src/workflows/testarch/bmad-testarch-ci"; }
    { n = "bmad-testarch-framework";                s = "${t}/src/workflows/testarch/bmad-testarch-framework"; }
    { n = "bmad-testarch-nfr";                      s = "${t}/src/workflows/testarch/bmad-testarch-nfr"; }
    { n = "bmad-testarch-test-design";              s = "${t}/src/workflows/testarch/bmad-testarch-test-design"; }
    { n = "bmad-testarch-test-review";              s = "${t}/src/workflows/testarch/bmad-testarch-test-review"; }
    { n = "bmad-testarch-trace";                    s = "${t}/src/workflows/testarch/bmad-testarch-trace"; }
    { n = "bmad-validate-prd";                      s = "${m}/src/bmm-skills/2-plan-workflows/bmad-validate-prd"; }
    { n = "bmad-workflow-builder";                  s = "${b}/skills/bmad-workflow-builder"; }
  ];

  mkSkillEntries = prefix: lib.listToAttrs (map (e: {
    name = "${prefix}/${e.n}";
    value = { source = e.s; };
  }) bmadSkills);

  localExtras = { };
in
{
  home.file =
    mkSkillEntries ".claude/skills"
    // mkSkillEntries ".gemini/skills"
    // localExtras;
}
