import std/[os, strutils]
import adaptive_ui/skill_files

let root = getCurrentDir() / "tests" / "fixtures" / "skills"

block loadLibrary:
  let lib = loadSkills([root])
  doAssert lib.skills.len == 2
  doAssert lib.skills[0].path < lib.skills[1].path

block frontmatter:
  let lib = loadSkills([root])
  var skill: SkillInfo
  doAssert lib.findSkill("math-tutor", skill)
  doAssert lib.hasSkill("math-tutor")
  doAssert skill.description == "Explain math problems one step at a time."
  doAssert "# Math Tutor" in skill.content
  doAssert skill.path.endsWith("math" / "SKILL.md")

block missingFrontmatter:
  let lib = loadSkills([root])
  var skill: SkillInfo
  doAssert lib.findSkill("plain", skill)
  doAssert skill.description == ""
  doAssert "Plain Skill" in skill.content

block missingRoot:
  let lib = loadSkills([root / "does-not-exist"])
  doAssert lib.skills.len == 0
  doAssert not lib.hasSkill("math-tutor")

block summary:
  let lib = loadSkills([root])
  let text = lib.skillSummary()
  doAssert "- math-tutor: Explain math problems one step at a time." in text
  doAssert "- plain" in text
  doAssert "SKILL.md" notin text
