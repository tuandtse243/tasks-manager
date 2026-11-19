# Input: array of raw project items (pages of items.graphql). --arg repo owner/name
# Output: the repository's issues on the board, normalized.
include "project";
project_items($repo)
