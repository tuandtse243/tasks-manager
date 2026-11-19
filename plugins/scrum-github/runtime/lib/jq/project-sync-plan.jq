# Input: normalized items. --argjson cfg CONFIG --argjson meta PROJECT_META
# Output: {ops, warnings, changed, unchanged}. Ops for one issue come in the order they must run:
# set_labels, close/reopen, comment, then the board fields.
include "project";
sync_plan($cfg; $meta)
