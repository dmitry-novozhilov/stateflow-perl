# StateFlow (perl implementation)

## What is StateFlow

This is a library for manipulation data in a DB, in which all data structures and data flow are specified once declaratively, and then data updates are simply applied, which the library distributes over this structure in accordance with the declaration.

At the same time, it takes into account the statistics of the use of this data and, on its basis, can optimize the actual data flow, choosing the degree of aggressiveness of materialization of secondary data structures.

## Exsample

We have `comments` table with next user fields:

- `id` - comment id
- `topic_id` - id of the commented topic
- `author_id` - comment author id

And next automatic fields:

- `likes_cnt = comments_votes[ id = id, is_like = true ].count` - likes count.
- `dislikes_cnt = comments_votes[ id = id, is_like = false ].count` - dislikes count.

Then, if there are much more writes into the `comments_votes` table than the reads from `comments`, then the automatic fields `likes_cnt` and` dislikes_cnt` will stop materializing, and will be calculated by a separate query to the `comments_votes` table at each reading.

And if there are much more reads from the `comments` table than the writes into `comments_votes` (which is most often the case), then the automatic fields `likes_cnt` and` dislikes_cnt` will be materialized. Each time `comments_votes` changes, `comments` will be updated.

## Magic

The key feature of StateFlow will be the ability to recognize most effectively update policies for all data. Here we can use a lot of different interesting dataflow statistics analysis.

## Among other things

It is planned to implement a dataflow dashboard panel, in which it is convenient to graphically represent the dataflow and present the key statistics data.

