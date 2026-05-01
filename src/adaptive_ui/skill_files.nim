import std/[algorithm, os, strutils]

type
  SkillInfo* = object
    name*: string
    description*: string
    path*: string
    content*: string

  SkillLibrary* = object
    skills*: seq[SkillInfo]

proc parentDirName(path: string): string =
  let parent = splitPath(path).head
  result = splitPath(parent).tail
  if result.len == 0:
    result = splitFile(path).name

proc parseFrontmatter(content: string; name, description: var string) =
  let lines = content.splitLines()
  if lines.len == 0 or lines[0].strip() != "---":
    return

  var i = 1
  var closed = false
  while i < lines.len and not closed:
    let line = lines[i].strip()
    if line == "---":
      closed = true
    else:
      let colon = line.find(':')
      if colon > 0:
        let key = line[0 ..< colon].strip()
        var value = ""
        if colon + 1 < line.len:
          value = line[colon + 1 .. ^1].strip()
        case key
        of "name":
          name = value
        of "description":
          description = value
        else:
          discard
    inc i

proc loadSkillFile*(path: string): SkillInfo =
  let content = readFile(path)
  var name = parentDirName(path)
  var description = ""
  parseFrontmatter(content, name, description)
  SkillInfo(
    name: name,
    description: description,
    path: path,
    content: content
  )

proc findSkillPaths(root: string; paths: var seq[string]) =
  if dirExists(root):
    for path in walkDirRec(root):
      if extractFilename(path) == "SKILL.md":
        paths.add path

proc loadSkills*(roots: openArray[string]): SkillLibrary =
  var paths: seq[string]
  for root in roots:
    findSkillPaths(root, paths)
  paths.sort(system.cmp[string])

  for path in paths:
    result.skills.add loadSkillFile(path)

proc findSkill*(lib: SkillLibrary; name: string; skill: var SkillInfo): bool =
  for item in lib.skills:
    if item.name == name:
      skill = item
      return true
  result = false

proc hasSkill*(lib: SkillLibrary; name: string): bool =
  var skill: SkillInfo
  result = lib.findSkill(name, skill)

proc skillSummary*(lib: SkillLibrary; maxSkills = 50): string =
  let limit = min(maxSkills, lib.skills.len)
  for i in 0 ..< limit:
    let skill = lib.skills[i]
    if result.len > 0:
      result.add "\n"
    result.add "- "
    result.add skill.name
    if skill.description.len > 0:
      result.add ": "
      result.add skill.description
