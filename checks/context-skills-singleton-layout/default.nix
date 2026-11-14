{ pkgs, ... }:

pkgs.runCommand "context-skills-singleton-layout" {
  nativeBuildInputs = [ pkgs.babashka pkgs.coreutils pkgs.diffutils pkgs.gnugrep ];
} ''
  set -eu
  generator=${../../packages/context-skills/generate.clj}

  valid="$TMPDIR/valid"
  mkdir -p "$valid/vision/nexus" "$valid/inquiry/question" "$valid/role"
  cat > "$valid/vision/nexus/0.md" <<'MODULE'
---
description: First Nexus account
---
zero body
MODULE
  cat > "$valid/vision/nexus/1.md" <<'MODULE'
---
description: Current Nexus account
---
one body
MODULE
  printf '%s\n' 'question body' > "$valid/inquiry/question/12.md"
  printf '%s\n' 'procedure body' > "$valid/role/book-reader-procedure.md"

  bb "$generator" "$TMPDIR/out" "$valid=revision-one"
  cat > "$TMPDIR/expected-modules" <<'EXPECTED'
inquiry:question:12 revision-one inquiry/question/12.md
role:book-reader-procedure revision-one role/book-reader-procedure.md
vision:nexus:0 revision-one vision/nexus/0.md
vision:nexus:1 revision-one vision/nexus/1.md
EXPECTED
  diff -u "$TMPDIR/expected-modules" "$TMPDIR/out/modules"
  grep -F 'description: First Nexus account' "$TMPDIR/out/.claude/skills/vision:nexus:0/SKILL.md"
  grep -F 'zero body' "$TMPDIR/out/.claude/skills/vision:nexus:0/SKILL.md"
  grep -F 'one body' "$TMPDIR/out/.agents/skills/vision:nexus:1/SKILL.md"
  grep -F 'question body' "$TMPDIR/out/.opencode/skills/inquiry:question:12/SKILL.md"
  grep -F 'procedure body' "$TMPDIR/out/.pi/skills/role:book-reader-procedure/SKILL.md"

  expect_failure() {
    name="$1"
    root="$2"
    expected="$3"
    if bb "$generator" "$TMPDIR/out-$name" "$root=revision-$name" >"$TMPDIR/$name.out" 2>"$TMPDIR/$name.err"; then
      echo "expected $name fixture to fail" >&2
      exit 1
    fi
    grep -F "$expected" "$TMPDIR/$name.err"
  }

  wrong_kind_flat="$TMPDIR/wrong-kind-flat"
  mkdir -p "$wrong_kind_flat/vision"
  printf '%s\n' flat > "$wrong_kind_flat/vision/nexus.md"
  expect_failure wrong-kind-flat "$wrong_kind_flat" 'not a module topic directory:'

  bad_topic="$TMPDIR/bad-topic"
  mkdir -p "$bad_topic/vision/Bad_Topic"
  printf '%s\n' bad > "$bad_topic/vision/Bad_Topic/0.md"
  expect_failure bad-topic "$bad_topic" 'invalid topic:'

  leading_zero="$TMPDIR/leading-zero"
  mkdir -p "$leading_zero/vision/nexus"
  printf '%s\n' bad > "$leading_zero/vision/nexus/01.md"
  expect_failure leading-zero "$leading_zero" 'invalid version:'

  span="$TMPDIR/span"
  mkdir -p "$span/vision/nexus"
  printf '%s\n' held > "$span/vision/nexus/0-1.md"
  expect_failure span "$span" 'invalid version:'

  nested="$TMPDIR/nested"
  mkdir -p "$nested/vision/nexus/deeper"
  expect_failure nested "$nested" 'not a module source:'

  symlinked="$TMPDIR/symlinked"
  mkdir -p "$symlinked/vision/nexus" "$symlinked/source"
  printf '%s\n' linked > "$symlinked/source/0.md"
  ln -s "$symlinked/source/0.md" "$symlinked/vision/nexus/0.md"
  expect_failure symlinked "$symlinked" 'not a module source:'

  duplicate="$TMPDIR/duplicate"
  mkdir -p "$duplicate/vision/nexus"
  printf '%s\n' duplicate > "$duplicate/vision/nexus/0.md"
  if bb "$generator" "$TMPDIR/out-duplicate" "$valid=revision-one" "$duplicate=revision-two" \
      >"$TMPDIR/duplicate.out" 2>"$TMPDIR/duplicate.err"; then
    echo 'expected duplicate identity fixture to fail' >&2
    exit 1
  fi
  grep -F 'duplicate module ids: vision:nexus:0' "$TMPDIR/duplicate.err"

  duplicate_role="$TMPDIR/duplicate-role"
  mkdir -p "$duplicate_role/role"
  printf '%s\n' duplicate > "$duplicate_role/role/book-reader-procedure.md"
  if bb "$generator" "$TMPDIR/out-duplicate-role" "$valid=revision-one" "$duplicate_role=revision-two" \
      >"$TMPDIR/duplicate-role.out" 2>"$TMPDIR/duplicate-role.err"; then
    echo 'expected duplicate flat role identity fixture to fail' >&2
    exit 1
  fi
  grep -F 'duplicate module ids: role:book-reader-procedure' "$TMPDIR/duplicate-role.err"

  touch "$out"
''
