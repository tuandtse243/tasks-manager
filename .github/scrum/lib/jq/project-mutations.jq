# Input: ops from project-sync-plan. --argjson meta PROJECT_META [--argjson size N]
# Output: array of GraphQL mutation documents for the board ops.
include "scrum";
board_mutations($meta; ($ARGS.named.size // 20))
