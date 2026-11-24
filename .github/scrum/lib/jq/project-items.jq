# Input: array of raw project items (pages of items.graphql). --arg repo owner/name
# Output: the repository's issues on the board, normalized.
include "scrum";
project_items($repo)
