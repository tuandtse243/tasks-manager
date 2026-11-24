# Input (slurped): the checks recorded by scrum doctor, {group, id, status, message, fix?} each.
# Output: {checks, errors, warnings}, the checks in group order.
. as $c
| ["tools", "repo", "install", "governance", "board"] as $order
| { checks: ($c | sort_by(.group as $g | $order | index($g) // 99)),
    errors: ([$c[] | select(.status == "error")] | length),
    warnings: ([$c[] | select(.status == "warn")] | length) }
