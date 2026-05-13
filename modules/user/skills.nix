{ lib, ... }:

let
  crossAgentSkills = [
    { n = "handoff";  s = ../../agent-skills/handoff; }
    { n = "pickup";   s = ../../agent-skills/pickup; }
    { n = "gpu-lock"; s = ../../agent-skills/gpu-lock; }
    { n = "hotkeys";  s = ../../agent-skills/hotkeys; }
    { n = "nrp";      s = ../../agent-skills/nrp; }
  ];

  mkEntries = prefix: skills: lib.listToAttrs (map (e: {
    name = "${prefix}/${e.n}";
    value = { source = e.s; };
  }) skills);
in
{
  home.file =
    mkEntries ".claude/skills" crossAgentSkills
    // mkEntries ".gemini/skills" crossAgentSkills;
}
