# plan.html from its data (design 8). Pure: same input, same output.
# Input: the data (plan-html-data.jq). -r --rawfile t (share/plan.html)
# The text parts are written here as HTML, every value escaped with @html, so the page reads
# fully without JavaScript; the page's script only draws the dependency graph and its motion.
# The data for the script goes in a JSON <script> element with every "<" written as \u003c.
include "scrum";

. as $d
| $d.strings as $S
| def e: tostring | @html;
  def t($k): tr($S; $k) | @html;
  def t($k; $a): tr($S; $k; $a) | @html;
  def tn($k; $n; $a): trn($S; $k; $n; $a) | @html;
  def fcls($i): "f\(($i % 4) + 1)";
  def anchor($id): "task-" + ($id | gsub("[^A-Za-z0-9_-]"; "_"));
  def sec($n; $part; $title; $body):
    "<section data-part=\"\($part)\" id=\"sec-\($part)\">\n<h2><span class=\"n\">\($n)</span>\($title)</h2>\n\($body)\n</section>";
  def sprint_text($sp):
    if $sp.kind == "backlog" then t("plan_backlog")
    elif $sp.label != null then ($sp.label | e)
    else t("plan_current_sprint") end;
  def value_text($f; $v):
    if $v == null then (if $f == "sprint" then t("plan_backlog") else "–" end)
    elif ($v | type) == "array" then (if ($v | length) == 0 then "–" else ($v | map(tostring) | join(", ") | e) end)
    else ($v | e) end;
  def pct($x; $max): if $max <= 0 then 0 else (($x * 10000 / $max) | round) / 100 end;

  $d.summary as $sum
| $d.load as $L
| ($d.tasks | map({key: .id, value: .}) | from_entries) as $byid

# ---------- 1. summary (header) ----------
| ( "<header class=\"head\" data-part=\"summary\" id=\"sec-summary\">\n"
    + "<span class=\"crumbs\">\(t("plan_crumbs"; {path: $d.path, rev: $d.diff.revision, at: ($d.generated_at | sub("T"; " ") | sub("Z$"; " UTC"))}))</span>\n"
    + "<div class=\"titlerow\"><h1>\($d.title | e)</h1><span class=\"state\(if $d.applied then " done" else "" end)\"><i></i>\(if $d.applied then t("plan_state_applied") else t("plan_state_review") end)</span></div>\n"
    + (if $d.epic != null then "<p class=\"muted\">Epic: \($d.epic.title | e)\(if $d.epic.issue != null then " (#\($d.epic.issue))" else "" end)</p>\n" else "" end)
    + "<div class=\"legend\">" + ([$d.features[] | "<span><i class=\"sw \(fcls(.index))\"></i>\(.id | e) \(.title | e)\(if .issue != null then " (#\(.issue))" else "" end)</span>"] | join("")) + "</div>\n"
    + "<div class=\"kpis\">"
    + "<div class=\"kpi\"><b>\(tn("plan_kpi_tasks"; $sum.tasks; {}))</b><span>"
      + (if $L.sprint != null then t("plan_kpi_tasks_sub"; {in: $sum.into, sprint: $L.sprint.title, out: $sum.backlog})
         else t("plan_kpi_tasks_sub_nosprint"; {out: $sum.backlog}) end) + "</span></div>"
    + "<div class=\"kpi\"><b>\(t("plan_kpi_points"; {n: $sum.points}))</b><span>\(t("plan_kpi_points_sub"; {unest: $sum.unestimated}))</span></div>"
    + (if $L.online and $L.sprint != null then
         "<div class=\"kpi\(if $L.over_sprint then " warn" else "" end)\"><b>"
         + (if $L.capacity != null then t("plan_kpi_capacity"; {after: $L.after, cap: $L.capacity}) else t("plan_kpi_points"; {n: $L.after}) end)
         + "</b><span>" + (if $L.capacity != null then t("plan_kpi_capacity_sub"; {sprint: $L.sprint.title}) else t("plan_kpi_capacity_unknown"; {sprint: $L.sprint.title}) end) + "</span></div>"
       else "" end)
    + "<div class=\"kpi\"><b>\(tn("plan_kpi_waves"; $sum.waves; {}))</b><span>\(t("plan_kpi_waves_sub"))</span></div>"
    + "</div>\n"
    + (if ($d.warnings | length) > 0 then
         "<div class=\"warnings\"><b>\(t("plan_warnings"))</b><ul>" + ([$d.warnings[] | "<li>\(e)</li>"] | join("")) + "</ul></div>\n"
       else "" end)
    + "</header>" ) as $p1

# ---------- 2. changes ----------
| ( $d.diff as $df
    | if $df.first then sec(1; "changes"; t("plan_sec_changes_first"); "<p class=\"muted\">\(t("plan_changes_first"))</p>")
      else sec(1; "changes"; t("plan_sec_changes"; {rev: $df.previous});
        (if ($df.added + $df.removed + $df.changed | length) == 0 then "<p class=\"muted\">\(t("plan_changes_none"))</p>"
         else "<div class=\"diff\">"
           + ([ ($df.added[] | "<span class=\"chip add\"><b>+ \(.id | e)</b><span>\(.title | e)</span></span>"),
                ($df.changed[] | "<span class=\"chip chg\"><b>~ \(.id | e)</b><span>"
                   + ([.fields[] | .field as $f
                       | if $f == "title" then "\(t("plan_field_title")): \(.from | e) → \(.to | e)"
                         else "\(t("plan_field_" + $f)): \(value_text($f; .from)) → \(value_text($f; .to))" end] | join(" · "))
                   + "</span></span>"),
                ($df.removed[] | "<span class=\"chip del\"><b>- \(.id | e)</b><span>\(.title | e)</span></span>") ] | join(""))
           + "</div>" end)
        + "\n<p class=\"small muted\">\(t("plan_changes_note"))</p>")
      end ) as $p2

# ---------- 3. graph ----------
| sec(2; "graph"; t("plan_sec_graph");
    "<div class=\"legend\">"
    + ([$d.features[] | "<span><i class=\"sw \(fcls(.index))\"></i>\(.id | e) \(.title | e)</span>"] | join(""))
    + "<span>\(t("plan_legend_backlog"))</span><span>\(t("plan_graph_hint"))</span></div>\n"
    + "<div class=\"panel scroll\"><svg id=\"dag\" role=\"img\" aria-label=\"\(t("plan_sec_graph"))\"></svg></div>\n"
    + "<ol class=\"waves\">"
    + ([$d.waves | to_entries[] | (.value | length) as $n
        | "<li><b>\(if $n > 1 then t("plan_wave_parallel"; {n: (.key + 1)}) else t("plan_wave"; {n: (.key + 1)}) end)</b> "
          + ([.value[] | "<a href=\"#\(anchor(.))\">\(e)</a>"] | join(", ")) + "</li>"] | join(""))
    + "</ol>") as $p3

# ---------- 4. load and capacity ----------
| ( if ($L.online | not) then sec(3; "load"; t("plan_sec_load_nosprint"); "<p class=\"muted offline\">\(t("plan_load_offline"))</p>")
    elif $L.sprint == null then sec(3; "load"; t("plan_sec_load_nosprint"); "<p class=\"muted\">\(t("plan_load_no_sprint"))</p>")
    else
      ([$L.capacity // 0, $L.after] | max) as $scale
      | sec(3; "load"; t("plan_sec_load"; {sprint: $L.sprint.title});
          "<div class=\"panel load\">\n"
          + "<div class=\"cap-track\">"
          + (if $L.planned > 0 then "<div class=\"seg now\" style=\"width:\(pct($L.planned; $scale))%\" title=\"\(t("plan_load_now"; {n: $L.planned}))\">\($L.planned)</div>" else "" end)
          + ([$L.into_tasks[] | select((.points // 0) > 0)
              | "<div class=\"seg \(fcls(.feature_index))\" style=\"width:\(pct(.points; $scale))%\" title=\"\(.id | e) · \(.points)\">\(.id | e) \(.points)</div>"] | join(""))
          + (if $L.capacity != null and $L.after > $L.capacity then "<div class=\"capline\" style=\"left:\(pct($L.capacity; $scale))%\"></div>" else "" end)
          + "</div>\n"
          + "<div class=\"cap-legend\"><span>\($L.sprint.title | e)\(if $L.sprint.start != null then " · \($L.sprint.start) → \($L.sprint.end // "?")" else "" end)\(if $L.planned > 0 then " · \(t("plan_load_now"; {n: $L.planned}))" else "" end)</span><span>"
            + (if $L.capacity == null then t("plan_load_cap_unknown"; {after: $L.after})
               elif $L.after > $L.capacity then t("plan_load_cap_over"; {after: $L.after, cap: $L.capacity, over: ($L.after - $L.capacity)})
               else t("plan_load_cap"; {after: $L.after, cap: $L.capacity, free: ($L.capacity - $L.after)}) end)
            + "</span></div>\n"
          + ([$L.backlog_tasks[] | "<div class=\"over\"><span class=\"ghost\">\(.id | e) · \(if .points == null then t("plan_not_estimated") else t("plan_kpi_points"; {n: .points}) end)</span><span>\(t("plan_backlog"))\(if .reason != null then ": " + t("plan_load_reason_" + .reason) else "" end)</span></div>\n"] | join(""))
          + "<hr>\n"
          + (([$L.people[] | .total, (.capacity // 0)] | max // 0) as $pmax
             | [$L.people[] | ([.total, (.capacity // 0)] | max) as $ps
                | "<div class=\"lrow\(if .over then " over-row" else "" end)\"><span class=\"who\">@\(.login | e)\(if .in_team | not then " <small>(\(t("plan_not_in_team")))</small>" else "" end)</span>"
                  + "<div class=\"track\">"
                  + (if .current > 0 then "<i class=\"now\" style=\"width:\(pct(.current; ([$ps, $pmax] | max)))%\"></i>" else "" end)
                  + (if .adding > 0 then "<i class=\"add\" style=\"width:\(pct(.adding; ([$ps, $pmax] | max)))%\"></i>" else "" end)
                  + "</div><span class=\"val\">"
                  + (if .capacity == null then t("plan_load_person_nocap"; {total: .total}) else t("plan_load_person"; {total: .total, cap: .capacity}) end)
                  + (if .over then " · <b>\(t("plan_load_person_over"))</b>" else "" end)
                  + "</span></div>\n"] | join(""))
          + "<p class=\"small muted\">\(if $L.team_source == "github" then t("plan_load_team_github") else t("plan_load_note") end)</p>\n"
          + "</div>")
    end ) as $p4

# ---------- 5. tasks ----------
| sec(4; "tasks"; t("plan_sec_tasks");
    "<div class=\"cards\">\n"
    + ([$d.tasks[] as $k
        | "<article class=\"card \(fcls($k.feature_index))\(if $k.sprint.kind == "backlog" then " backlog" else "" end)\" id=\"\(anchor($k.id))\">"
          + "<div class=\"top\"><span class=\"id\">\($k.id | e) · \($k.feature | e)"
            + (if ($k.depends_on | length) > 0 then " · " + t("plan_needs"; {ids: ($k.depends_on | join(", "))}) else "" end) + "</span>"
            + (if $k.issue != null then "<span class=\"issue\">#\($k.issue)</span>" else "" end)
            + (if $k.change == "added" then "<span class=\"badge add\">\(t("plan_badge_added"))</span>"
               elif $k.change == "changed" then "<span class=\"badge chg\">\(t("plan_badge_changed"))</span>" else "" end)
          + "</div>"
          + "<h3>\($k.title | e)</h3>"
          + "<div class=\"facts\">"
            + "<span class=\"fact\">\(if $k.points == null then t("plan_not_estimated") else t("plan_kpi_points"; {n: $k.points}) end)</span>"
            + (if ($k.assignees | length) == 0 then "<span class=\"fact dim\">\(t("plan_unassigned"))</span>"
               else ([$k.assignees[] | "<span class=\"fact\">@\(e)</span>"] | join("")) end)
            + "<span class=\"fact\(if $k.sprint.kind == "backlog" then " bl" else "" end)\">\(sprint_text($k.sprint))</span>"
            + (if $k.bug then "<span class=\"fact\">\(t("plan_bug"))</span>" else "" end)
          + "</div>"
          + (if $k.body != "" then "<p class=\"small body\">\($k.body | e)</p>" else "" end)
          + (if ($k.acceptance | length) > 0 then "<ul class=\"check\">" + ([$k.acceptance[] | "<li>\(e)</li>"] | join("")) + "</ul>" else "" end)
          + (if ($k.subtasks | length) > 0 then "<p class=\"small muted\">\(t("plan_subtasks"))</p><ul class=\"check\">" + ([$k.subtasks[] | "<li>\(e)</li>"] | join("")) + "</ul>" else "" end)
          + "</article>\n"] | join(""))
    + "</div>") as $p5

# ---------- 6. review ----------
| sec(5; "review"; t("plan_sec_review");
    if ($d.review | length) == 0 then "<p class=\"muted\">\(t("plan_review_none"))</p>"
    else "<div class=\"list\">"
      + ([$d.review[] | "<div class=\"item\"><span class=\"tick \(if .status == "fixed" then "done" else "keep" end)\">\(if .status == "fixed" then t("plan_review_fixed") else t("plan_review_kept") end)</span>"
          + "<span><b>\(($S["plan_kind_" + (.kind | tostring)] // .kind) | e):</b> \(.text | e)</span></div>"] | join(""))
      + "</div>" end) as $p6

# ---------- 7. actions ----------
| ( $d.actions as $A
    | if $A == null then sec(6; "actions"; t("plan_sec_actions"); "<p class=\"muted offline\">\(t("plan_actions_offline"))</p>")
      elif ($A.errors | length) > 0 then sec(6; "actions"; t("plan_sec_actions");
        "<div class=\"warnings\"><b>\(t("plan_actions_errors"))</b><ul>" + ([$A.errors[] | "<li>\(e)</li>"] | join("")) + "</ul></div>")
      elif ($A.epic + $A.features + $A.tasks + $A.link_sub + $A.link_blocked) == 0 then
        sec(6; "actions"; (if $d.applied then t("plan_sec_actions_done") else t("plan_sec_actions") end); "<p class=\"muted\">\(t("plan_actions_none"))</p>")
      else
        sec(6; "actions"; t("plan_sec_actions");
          "<div class=\"acts\">"
          + "<div class=\"act\"><b>\($A.epic + $A.features + $A.tasks)</b><span>"
            + t("plan_act_issues"; {detail: ([ (if $A.epic > 0 then trn($S; "plan_act_epic"; $A.epic; {}) else empty end),
                                               (if $A.features > 0 then trn($S; "plan_act_features"; $A.features; {}) else empty end),
                                               (if $A.tasks > 0 then trn($S; "plan_act_tasks"; $A.tasks; {}) else empty end)] | join(", "))}) + "</span></div>"
          + (if $A.link_sub > 0 then "<div class=\"act\"><b>\($A.link_sub)</b><span>\(t("plan_act_sub"))</span></div>" else "" end)
          + (if $A.link_blocked > 0 then "<div class=\"act\"><b>\($A.link_blocked)</b><span>\(t("plan_act_blocked"))</span></div>" else "" end)
          + (if $A.into > 0 then "<div class=\"act\"><b>\($A.into)</b><span>\(t("plan_act_sprint"; {sprint: ($L.sprint.title // "sprint")}))</span></div>" else "" end)
          + (if $A.backlog > 0 then "<div class=\"act\"><b>\($A.backlog)</b><span>\(t("plan_act_backlog"))</span></div>" else "" end)
          + (if $A.assigned > 0 then "<div class=\"act\"><b>\($A.assigned)</b><span>\(t("plan_act_assigned"; {people: $A.people}))</span></div>" else "" end)
          + (if $A.existing > 0 then "<div class=\"act\"><b>\($A.existing)</b><span>\(t("plan_act_existing"))</span></div>" else "" end)
          + "</div>\n<details><summary class=\"small muted\">scrum plan apply</summary><pre>" + ($A.lines | join("\n") | e) + "</pre></details>")
      end ) as $p7

# ---------- 8. assumptions and out of scope ----------
| sec(7; "assumptions"; t("plan_sec_assumptions");
    "<div class=\"two\">"
    + "<div class=\"panel\"><h3>\(t("plan_assumptions"))</h3>"
      + (if ($d.assumptions | length) == 0 then "<p class=\"muted\">\(t("plan_none"))</p>" else "<ul>" + ([$d.assumptions[] | "<li>\(e)</li>"] | join("")) + "</ul>" end) + "</div>"
    + "<div class=\"panel\"><h3>\(t("plan_out_of_scope"))</h3>"
      + (if ($d.out_of_scope | length) == 0 then "<p class=\"muted\">\(t("plan_none"))</p>" else "<ul>" + ([$d.out_of_scope[] | "<li>\(e)</li>"] | join("")) + "</ul>" end) + "</div>"
    + "</div>") as $p8

| ( if $d.applied then ""
    else "<div class=\"confirm\"><h3>\(t("plan_confirm_title"))</h3><p class=\"small\">\(t("plan_confirm_text"))</p>"
      + "<span class=\"say\">\(t("plan_confirm_say"))</span><p class=\"small muted\">\(t("plan_confirm_note"))</p></div>" end ) as $confirm

| ([$p1, $p2, $p3, $p4, $p5, $p6, $p7, $p8, $confirm] | join("\n\n")) as $body
| ( $d | {language, tasks: [.tasks[] | {id, title, feature_index, points, depends_on, assignees, wave, sprint, issue}], waves,
           strings: {plan_wave: .strings.plan_wave, plan_wave_parallel: .strings.plan_wave_parallel, plan_backlog: .strings.plan_backlog,
                     plan_kpi_points: .strings.plan_kpi_points, plan_not_estimated: .strings.plan_not_estimated}}
    | tojson | gsub("<"; "\\u003c") ) as $json
# The template is cut at its placeholders first, so text from the plan is never searched for one.
| ($t | split("__SCRUM_DATA__")) as [$pre, $post]
| ($pre | split("__SCRUM_BODY__")) as [$head, $mid]
| ($head | split("__SCRUM_LANG__") | join($d.language | e)
         | split("__SCRUM_TITLE__") | join(tr($S; "plan_page_title"; {title: $d.title}) | e))
  + $body + $mid + $json + $post
