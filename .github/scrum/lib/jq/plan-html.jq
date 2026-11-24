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
  def r1: (. * 10 | round) / 10;
  def cut($n): if length > $n then .[0:($n - 1)] + "…" else . end;
  # The timeline, to scale (spec work-plan "Dòng thời gian trong plan.html"): one work bar per
  # estimated task at the start of its wave, a merge gap after each wave, then the review bar.
  # Drawn here as SVG so it reads without JavaScript; the "now" line moves by SMIL <animate>,
  # hidden under prefers-reduced-motion.
  def timeline_svg($tm):
    920 as $W | 200 as $X0 | 22 as $TOP | 32 as $ROW
    | ($tm.rows | length) as $n
    | ([$tm.total, 1] | max) as $total
    | (($W - $X0 - 82) / $total) as $sc
    | def x($m): ($X0 + $m * $sc) | r1;
      def w($m): ($m * $sc) | r1;
    ($TOP + $n * $ROW + 16) as $ry
    | ($ry + 38) as $gb
    | ($gb + 20) as $ay
    | ([5, 10, 15, 20, 30, 60, 90, 120, 180, 240, 360, 480, 720, 960, 1440, 2880] | map(select($total / . <= 6)) | .[0] // 2880) as $step
    | [range(0; 100) | . * $step | select(x(.) <= $W - 20)] as $ticks
    | ($tm.rows | to_entries) as $rows
    | "<svg class=\"tl\" viewBox=\"0 0 \($W) \($ay + 14)\" role=\"img\" aria-label=\"\(t("plan_tl_aria"; {work: ($tm.work | fmt_duration), review: ($tm.review | fmt_duration), total: ($tm.total | fmt_duration)}))\">"
      + "<g font-size=\"10.5\">"
      + ([$ticks[] | "<line x1=\"\(x(.))\" y1=\"14\" x2=\"\(x(.))\" y2=\"\($gb)\" class=\"grid\"/><text x=\"\(x(.))\" y=\"\($ay)\" text-anchor=\"middle\" class=\"tm\">\(if . == 0 then "0" else fmt_duration end)</text>"] | join(""))
      + "</g><g font-size=\"12\">"
      + ([$rows[] | "<text x=\"10\" y=\"\($TOP + .key * $ROW + 14)\">\("\(.value.id) \(.value.title)" | cut(26) | e)</text>"] | join(""))
      + "<text x=\"10\" y=\"\($ry + 15)\" font-weight=\"700\" class=\"th\">\(t("plan_tl_review"))</text></g>"
      + ([$rows[] | select(.value.work > 0) | .key as $i | .value as $r
          | "<rect x=\"\(x($r.start))\" y=\"\($TOP + $i * $ROW)\" width=\"\(w($r.work))\" height=\"20\" rx=\"4\" class=\"\(if $r.by == "human" then "b-hw" else "b-ai" end)\"><title>"
            + ("\($r.id) · \(tr($S; "est_work"; {by: tr($S; "est_by_\($r.by)"), d: ($r.work | fmt_duration)})) · \(tr($S; "est_review"; {d: ($r.review | fmt_duration)}))" | e)
            + "</title></rect>"] | join(""))
      + (if $tm.merge > 0 then
           ([$tm.waves[] as $wv | [$rows[] | select(.value.wave == $wv.wave) | .key] as $ks
             | select(($ks | length) > 0)
             | "<rect x=\"\(x($wv.start + $wv.work))\" y=\"\($TOP + ($ks | min) * $ROW)\" width=\"\(w($tm.merge))\" height=\"\((($ks | max) - ($ks | min)) * $ROW + 20)\" rx=\"2\" class=\"b-merge\"><title>\(t("plan_tl_merge")) · \($tm.merge | fmt_duration)</title></rect>"] | join(""))
         else "" end)
      + "<line x1=\"\(x($tm.work))\" y1=\"14\" x2=\"\(x($tm.work))\" y2=\"\($gb)\" class=\"done\"/>"
      + "<text x=\"\(x($tm.work) + 6)\" y=\"\($ry - 12)\" font-size=\"11\" class=\"tai\">\(t("plan_tl_done"; {d: ($tm.work | fmt_duration)}))</text>"
      + (if $tm.review > 0 then
           "<rect x=\"\(x($tm.work))\" y=\"\($ry)\" width=\"\(w($tm.review))\" height=\"22\" rx=\"4\" class=\"b-h\"><title>\(t("plan_tl_review_bar"; {d: ($tm.review | fmt_duration)}))</title></rect>"
           + (if w($tm.review) >= 170 then "<text x=\"\(x($tm.work + $tm.review / 2))\" y=\"\($ry + 15)\" text-anchor=\"middle\" font-size=\"11.5\" font-weight=\"700\" class=\"onbar\">\(t("plan_tl_review_bar"; {d: ($tm.review | fmt_duration)}))</text>" else "" end)
         else "" end)
      + "<text x=\"\(x($tm.total) + 6)\" y=\"\($ry + 15)\" font-size=\"11\" class=\"th mono\">\($tm.total | fmt_duration)</text>"
      + "<line class=\"now mover\" x1=\"\($X0)\" y1=\"14\" x2=\"\($X0)\" y2=\"\($gb)\">"
        + "<animate attributeName=\"x1\" values=\"\($X0);\(x($tm.total))\" dur=\"9s\" repeatCount=\"indefinite\"/>"
        + "<animate attributeName=\"x2\" values=\"\($X0);\(x($tm.total))\" dur=\"9s\" repeatCount=\"indefinite\"/></line>"
      + "</svg>";

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
    + (if $d.time == null then "" else
         "<div class=\"kpi ai\"><b>\(t("plan_kpi_time"; {d: ($d.time.work | fmt_duration)}))</b><span>\(tn("plan_kpi_work_sub"; ($d.time.waves | length); {}))</span></div>"
         + "<div class=\"kpi hu\"><b>\(t("plan_kpi_time"; {d: ($d.time.review | fmt_duration)}))</b><span>\(t("plan_kpi_review_sub"))"
           + (if $d.time.missing > 0 then " · " + tn("plan_kpi_time_missing"; $d.time.missing; {}) else "" end) + "</span></div>" end)
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

# ---------- 3b. timeline (only with time estimates) ----------
| (if $d.time == null then 0 else 1 end) as $tl
| ( if $d.time == null then null
    else $d.time as $tm
      | sec(3; "timeline"; t("plan_sec_timeline");
          "<div class=\"legend\"><span><i class=\"sw tl-ai\"></i>\(t("plan_tl_ai"))</span>"
          + (if $tm.humans then "<span><i class=\"sw tl-hw\"></i>\(t("plan_tl_human"))</span>" else "" end)
          + "<span><i class=\"sw tl-merge\"></i>\(t("plan_tl_merge"))</span><span><i class=\"sw tl-h\"></i>\(t("plan_tl_review"))</span></div>\n"
          + "<div class=\"panel scroll\">" + timeline_svg($tm) + "</div>\n"
          + "<p class=\"small muted\">\(t("plan_tl_note"; {merge: ($tm.merge | fmt_duration), sum: ($tm.sum_work | fmt_duration)}))"
          + (if $tm.missing > 0 then " " + tn("plan_tl_missing"; $tm.missing; {ids: ($tm.missing_ids | join(", "))}) else "" end) + "</p>")
    end ) as $p3b

# ---------- 4. load and capacity ----------
| ( if $L.unreadable then sec(3 + $tl; "load"; t("plan_sec_load_nosprint"); "<p class=\"muted offline\">\(t("plan_load_unreadable"))</p>")
    elif ($L.online | not) then sec(3 + $tl; "load"; t("plan_sec_load_nosprint"); "<p class=\"muted offline\">\(t("plan_load_offline"))</p>")
    elif $L.sprint == null then sec(3 + $tl; "load"; t("plan_sec_load_nosprint"); "<p class=\"muted\">\(t("plan_load_no_sprint"))</p>")
    else
      ([$L.capacity // 0, $L.after] | max) as $scale
      | sec(3 + $tl; "load"; t("plan_sec_load"; {sprint: $L.sprint.title});
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
| sec(4 + $tl; "tasks"; t("plan_sec_tasks");
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
            + (if $k.estimate == null then ""
               else (if $k.estimate.work_minutes != null then "<span class=\"fact \(if $k.estimate.by == "human" then "hu" else "ai" end)\">\(t("est_work"; {by: tr($S; "est_by_\($k.estimate.by)"), d: ($k.estimate.work_minutes | fmt_duration)}))</span>" else "" end)
                    + (if $k.estimate.review_minutes != null then "<span class=\"fact hu\">\(t("est_review"; {d: ($k.estimate.review_minutes | fmt_duration)}))</span>" else "" end) end)
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
| sec(5 + $tl; "review"; t("plan_sec_review");
    if ($d.review | length) == 0 then "<p class=\"muted\">\(t("plan_review_none"))</p>"
    else "<div class=\"list\">"
      + ([$d.review[] | "<div class=\"item\"><span class=\"tick \(if .status == "fixed" then "done" else "keep" end)\">\(if .status == "fixed" then t("plan_review_fixed") else t("plan_review_kept") end)</span>"
          + "<span><b>\(($S["plan_kind_" + (.kind | tostring)] // .kind) | e):</b> \(.text | e)</span></div>"] | join(""))
      + "</div>" end) as $p6

# ---------- 7. actions ----------
| ( $d.actions as $A
    | if $A == null then sec(6 + $tl; "actions"; t("plan_sec_actions"); "<p class=\"muted offline\">\(t("plan_actions_offline"))</p>")
      elif ($A.errors | length) > 0 then sec(6 + $tl; "actions"; t("plan_sec_actions");
        "<div class=\"warnings\"><b>\(t("plan_actions_errors"))</b><ul>" + ([$A.errors[] | "<li>\(e)</li>"] | join("")) + "</ul></div>")
      elif ($A.epic + $A.features + $A.tasks + $A.link_sub + $A.link_blocked) == 0 then
        sec(6 + $tl; "actions"; (if $d.applied then t("plan_sec_actions_done") else t("plan_sec_actions") end); "<p class=\"muted\">\(t("plan_actions_none"))</p>")
      else
        sec(6 + $tl; "actions"; (if $A.done then t("plan_sec_actions_done") else t("plan_sec_actions") end);
          "<div class=\"acts\">"
          + "<div class=\"act\"><b>\($A.epic + $A.features + $A.tasks)</b><span>"
            + t(if $A.done then "plan_act_issues_done" else "plan_act_issues" end; {detail: ([ (if $A.epic > 0 then trn($S; "plan_act_epic"; $A.epic; {}) else empty end),
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
| sec(7 + $tl; "assumptions"; t("plan_sec_assumptions");
    "<div class=\"two\">"
    + "<div class=\"panel\"><h3>\(t("plan_assumptions"))</h3>"
      + (if ($d.assumptions | length) == 0 then "<p class=\"muted\">\(t("plan_none"))</p>" else "<ul>" + ([$d.assumptions[] | "<li>\(e)</li>"] | join("")) + "</ul>" end) + "</div>"
    + "<div class=\"panel\"><h3>\(t("plan_out_of_scope"))</h3>"
      + (if ($d.out_of_scope | length) == 0 then "<p class=\"muted\">\(t("plan_none"))</p>" else "<ul>" + ([$d.out_of_scope[] | "<li>\(e)</li>"] | join("")) + "</ul>" end) + "</div>"
    + "</div>") as $p8

| ( if $d.applied then ""
    else "<div class=\"confirm\"><h3>\(t("plan_confirm_title"))</h3><p class=\"small\">\(t("plan_confirm_text"))</p>"
      + "<span class=\"say\">\(t("plan_confirm_say"))</span><p class=\"small muted\">\(t("plan_confirm_note"))</p></div>" end ) as $confirm

| ([$p1, $p2, $p3, ($p3b // empty), $p4, $p5, $p6, $p7, $p8, $confirm] | join("\n\n")) as $body
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
