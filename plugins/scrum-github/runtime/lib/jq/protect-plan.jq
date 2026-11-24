# scrum protect (spec repo-governance, design 9): what the repository needs to match the preset.
#
# Merge methods: checked on 2026-11-24 against the GitHub REST docs "Repository rules"
# (docs.github.com/en/rest/repos/rules, API version 2022-11-28): the pull_request rule of a
# ruleset has the optional parameter `allowed_merge_methods`, an array of "merge", "squash" and
# "rebase" (at least one). So the merge methods are enforced per branch by the ruleset; the
# repository-level settings (allow_*_merge) are set to the union of the methods the preset uses.
# The same page documents the `update` rule with the required parameter
# `update_allows_fetch_and_merge`, and `deletion` / `non_fast_forward` without parameters.
#
# Named arguments; step "plan" (default):
#   $cfg        the configuration
#   $templates  {working, staging, release, tags}: the texts of templates/rulesets/*.json
#   $branches   {"<name>": {exists, sha}} for each long-lived branch of the preset
#   $rulesets   the rulesets of the repository named "scrum: ...", in full (GET rulesets/{id}),
#               or null when they could not be read
#   $rules_error  why the rulesets could not be read ("" when they could)
#   $settings   the repository (GET repos/{r}), or null when it could not be read
#   $check      the name of the plugin's own required check (the job of scrum-pr-link-check.yml)
# Output: {repo_preset, branches: [...], rulesets: [...], obsolete: [...], settings: {...},
#          rules_error, changes, problems}
# step "text": input is a plan (optionally with .results); output: lines for a person.
include "scrum";

def method_order: {merge: 0, squash: 1, rebase: 2};
def sort_methods: sort_by(method_order[.] // 9);

# Merge methods of a long-lived branch by its kind (spec "Branch rules").
def merge_methods($cfg; $kind):
  if preset($cfg) == "trunk" then ["squash"]
  elif $kind == "working" then ["merge", "squash"]
  else ["merge"] end;

def render($tpl; $vars):
  reduce ($vars | to_entries[]) as $e ($tpl; gsub("\\{\\{" + $e.key + "\\}\\}"; $e.value))
  | fromjson;

def canon:
  if type == "array" then map(if type == "object" and has("context") then {context} else . end) | sort
  else . end;
def params_match($want; $have):
  all($want | to_entries[]; ($have[.key] | canon) == (.value | canon));
def ruleset_matches($want; $have):
  $have != null
  and $have.target == $want.target
  and ($have.enforcement // "") == $want.enforcement
  and (($have.conditions.ref_name.include // []) | sort) == ($want.conditions.ref_name.include | sort)
  and ([$have.rules[]?.type] | sort) == ([$want.rules[].type] | sort)
  and all($want.rules[]; . as $w
        | ([$have.rules[]? | select(.type == $w.type)] | .[0].parameters // {}) as $hp
        | params_match($w.parameters // {}; $hp));

def plan:
  $ARGS.named as {cfg: $cfg, templates: $templates, branches: $branches, rulesets: $rulesets,
                  rules_error: $rules_error, settings: $settings, check: $check}
  | branching($cfg) as $b
  | (reduce ([$check] + ($cfg.governance.required_checks // []))[] as $c ([]; if index([$c]) then . else . + [$c] end)) as $checks
  | ($cfg.governance.approvals // 1) as $approvals
  | ($branches[$b.release] // {exists: false}) as $rel
  # ---- long-lived branches: created from the head of the release branch, never moved ----
  | [ $b.chain | reverse | .[] as $name
      | ($branches[$name] // {exists: false}) as $st
      | {name: $name, kind: branch_kind($cfg; $name), exists: ($st.exists == true)}
      + if $st.exists == true then {action: "none"}
        elif $name == $b.release then {action: "missing", reason: "the release branch \($name) does not exist; push a first commit to it"}
        elif $rel.exists != true or ($rel.sha // "") == "" then {action: "missing", reason: "cannot create \($name): the release branch \($b.release) does not exist"}
        else {action: "create", from: $b.release, sha: $rel.sha} end ] as $branch_items
  # ---- rulesets ----
  | ( [ (if has_working_branch($cfg) then {key: "working", branch: $b.working} else empty end),
        (if $b.staging != null then {key: "staging", branch: $b.staging} else empty end),
        {key: "release", branch: $b.release} ]
      | map(. as $r | branch_kind($cfg; $r.branch) as $kind
            | merge_methods($cfg; $kind) as $m
            | $r + {target: "branch", merge_methods: $m, approvals: $approvals, checks: $checks,
                    body: render($templates[$r.key]; {
                      BRANCH: $r.branch, APPROVALS: ($approvals | tostring),
                      MERGE_METHODS: ($m | tojson),
                      REQUIRED_CHECKS: ([$checks[] | {context: .}] | tojson)})}) )
    + [ {key: "tags", branch: null, target: "tag", pattern: "\($cfg.release.tag_prefix // "v")*",
         body: render($templates.tags; {TAG_PREFIX: ($cfg.release.tag_prefix // "v")})} ]
    as $wanted
  | ($rulesets // []) as $have_all
  | [ $wanted[] | . as $w
      | ([$have_all[] | select(.name == $w.body.name)] | .[0]) as $have
      | $w + (if $have == null then {action: "create", id: null}
              elif ruleset_matches($w.body; $have) then {action: "none", id: $have.id}
              else {action: "update", id: $have.id} end) ] as $ruleset_items
  | [ $have_all[] | select(.name as $n | ($wanted | map(.body.name) | index($n)) == null)
      | {id, name} ] as $obsolete
  # ---- repository settings ----
  | ([ $b.chain[] | merge_methods($cfg; branch_kind($cfg; .))[] ] | unique) as $all_methods
  | { delete_branch_on_merge: true, allow_auto_merge: true,
      allow_squash_merge: ($all_methods | index("squash") != null),
      allow_merge_commit: ($all_methods | index("merge") != null),
      allow_rebase_merge: ($all_methods | index("rebase") != null) } as $want_settings
  | [ $want_settings | to_entries[] | .key as $k
      | select($settings == null or $settings[$k] != .value)
      | {key: $k, from: (if $settings == null then null else $settings[$k] end), to: .value} ] as $setting_changes
  | { preset: $b.preset,
      branches: $branch_items,
      rulesets: $ruleset_items,
      obsolete: $obsolete,
      rules_error: $rules_error,
      settings: {action: (if ($setting_changes | length) > 0 then "update" else "none" end),
                 methods: ($all_methods | sort_methods), desired: $want_settings, changes: $setting_changes,
                 readable: ($settings != null)},
      changes: (([$branch_items[] | select(.action == "create")] | length)
                + ([$ruleset_items[] | select(.action != "none")] | length)
                + (if ($setting_changes | length) > 0 then 1 else 0 end)),
      problems: ([$branch_items[] | select(.action == "missing")] | length) };

# ---- text for a person ----
def mark($a): {none: "ok      ", create: "create  ", update: "update  ", missing: "missing ", failed: "FAILED  ", done: "done    "}[$a] // $a;
def joinl: join(", ");
def ruleset_line:
  if .target == "tag" then
    "\(.body.name): tags \(.pattern): no update, no deletion"
  else
    "\(.body.name) on \(.branch): pull request required, "
    + (if .approvals == 0 then "no approval" elif .approvals == 1 then "1 approval" else "\(.approvals) approvals" end)
    + ", checks \(.checks | joinl), merge methods \(.merge_methods | map(if . == "merge" then "merge commit" else . end) | joinl)"
    + ", no force push, no deletion"
  end;
def result_of($item): (.results // []) as $r | [$r[] | select(.item == $item)] | .[0];

def text:
  . as $p
  | (if (.results // null) != null then "Protection applied (preset \(.preset))" else "Protection for preset \(.preset)" end),
    "",
    "Branches",
    (.branches[] | . as $i | ($p | result_of("branch:\($i.name)")) as $res
      | "  \(mark(if $res then $res.status else .action end))\(.name)"
        + (if .action == "create" then " (from \(.from) at \(.sha[0:7]))" elif .action == "missing" then ": \(.reason)" else "" end)
        + (if $res and $res.status == "failed" then ": \($res.message)" else "" end)),
    "",
    "Rules",
    (if .rules_error != "" then "  note    the rules could not be read: \(.rules_error)" else empty end),
    (.rulesets[] | . as $i | ($p | result_of("ruleset:\($i.key)")) as $res
      | "  \(mark(if $res then $res.status else .action end))\(ruleset_line)"
        + (if $res and $res.status == "failed" then "\n          \($res.message)" else "" end)),
    (.obsolete[] | "  obsolete \(.name) (not in preset \($p.preset); not deleted)"),
    "",
    "Repository settings",
    ( (.settings) as $s | ($p | result_of("settings")) as $res
      | if $s.action == "none" then
          "  ok      merge methods \($s.methods | joinl); delete head branches after merge; auto-merge allowed"
        else
          "  \(mark(if $res then $res.status else "update" end))"
          + ($s.changes | map("\(.key): \(if .from == null then "?" else .from end) -> \(.to)") | join("; "))
          + (if $res and $res.status == "failed" then "\n          \($res.message)" else "" end)
        end ),
    "",
    ( if (.results // null) != null then
        ([.results[] | select(.status == "failed")] | length) as $f
        | if $f == 0 then "Done." else "\($f) item\(if $f == 1 then "" else "s" end) failed; the others were applied. See the lines marked FAILED." end
      elif .changes == 0 and .problems == 0 then "Nothing to change: the repository already matches preset \(.preset)."
      elif .changes == 0 then "Nothing to apply; fix the missing branches above first."
      else "Nothing was changed. To apply, run again with --yes." end );

if ($ARGS.named.step // "plan") == "text" then text else plan end
