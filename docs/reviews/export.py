#!/usr/bin/env python3
"""Turn a pull request's review into a Markdown transcript.

GitHub cannot move a pull request between repositories, and a review is often
the only record of why a rule reads the way it does. This writes the review out
as a file the new repository can keep.

    gh api repos/OWNER/REPO/pulls/N/comments --paginate            > rc.json
    gh api repos/OWNER/REPO/issues/N/comments --paginate           > ic.json
    gh api repos/OWNER/REPO/pulls/N/reviews  --paginate            > rv.json
    gh api graphql -f query="$(cat threads.graphql)" \
      -F owner=OWNER -F name=REPO > threads.json                   # see below
    docs/reviews/export.py . OWNER/REPO N > out.md

threads.graphql asks for the resolution state REST does not expose:

    query($owner:String!,$name:String!){
      repository(owner:$owner,name:$name){
        pullRequest(number:N){
          title createdAt
          reviewThreads(first:100){
            nodes{ isResolved isOutdated path line originalLine
                   resolvedBy{login}
                   comments(first:50){nodes{databaseId author{login} createdAt}} }
          }
        }
      }
    }
"""
import json
import pathlib
import sys

HUNK_LINES = 8  # of a diff hunk, enough to see what was meant


def when(iso):
    return (iso or '').replace('T', ' ').replace('Z', ' UTC')


def quote(body):
    body = (body or '').replace('\r\n', '\n').rstrip()
    if not body:
        return '> _(no text)_'
    return '\n'.join('> ' + line if line else '>' for line in body.split('\n'))


def hunk_tail(hunk):
    """The last few lines of a diff hunk. The full hunks of a long review run
    to megabytes, which is not something to carry in a repository."""
    lines = (hunk or '').replace('\r\n', '\n').rstrip().split('\n')
    if lines == ['']:
        return None
    prefix = '' if len(lines) <= HUNK_LINES else '@@ …\n'
    return prefix + '\n'.join(lines[-HUNK_LINES:])


def main(argv):
    if len(argv) != 4:
        sys.exit(__doc__)
    here, slug, number = pathlib.Path(argv[1]), argv[2], argv[3]

    inline = json.loads((here / 'rc.json').read_text())
    conversation = json.loads((here / 'ic.json').read_text())
    summaries = json.loads((here / 'rv.json').read_text())
    pr = json.loads((here / 'threads.json').read_text())
    pr = pr['data']['repository']['pullRequest']
    threads = pr['reviewThreads']['nodes']

    inline_by_id = {c['id']: c for c in inline}
    written = sum(1 for r in summaries if (r.get('body') or '').strip())

    out = []
    w = out.append

    w(f'# Review history — {slug}#{number}')
    w('')
    w("The `commit-msg` hook was written in a pull request against the community")
    w('website, before it had a repository of its own. This is that review, kept')
    w("here because it is the only record of why a good many of the hook's rules")
    w('look the way they do.')
    w('')
    w(f'- **Pull request:** [{slug}#{number}](https://github.com/{slug}/pull/{number})'
      f' — {pr["title"]}')
    w(f'- **Opened:** {when(pr["createdAt"])}')
    w(f'- **Review threads:** {len(threads)} '
      f'({sum(1 for t in threads if t["isResolved"])} resolved, '
      f'{sum(1 for t in threads if t["isOutdated"])} since made obsolete by a later change)')
    w(f'- **Inline comments:** {len(inline)} · **review summaries:** {written} · '
      f'**conversation comments:** {len(conversation)}')
    w('')
    w('GitHub cannot move a pull request between repositories, so nothing here is')
    w('live: the threads are not resolvable and the line numbers refer to')
    w('`.githooks/commit-msg` as it stood in that branch, which is `commit-msg`')
    w('here. Diff excerpts are trimmed to the last few lines of each hunk.')
    w('')
    w('---')
    w('')
    w('## Review threads')
    w('')

    def started(thread):
        stamps = [inline_by_id[c['databaseId']]['created_at']
                  for c in thread['comments']['nodes']
                  if c['databaseId'] in inline_by_id]
        return min(stamps) if stamps else '9999'

    for n, thread in enumerate(sorted(threads, key=started), 1):
        state = []
        if thread['isResolved']:
            by = (thread.get('resolvedBy') or {}).get('login')
            state.append(f'resolved by {by}' if by else 'resolved')
        else:
            state.append('**unresolved**')
        if thread['isOutdated']:
            state.append('outdated')

        line = thread['line'] or thread['originalLine']
        w(f'### {n}. `{thread["path"]}`' + (f' line {line}' if line else '')
          + f' — {", ".join(state)}')
        w('')

        for i, comment in enumerate(thread['comments']['nodes']):
            full = inline_by_id.get(comment['databaseId'])
            if full is None:
                # Not in the REST listing: deleted, or written by an account
                # whose comments are no longer served.
                author = (comment.get('author') or {}).get('login', 'unknown')
                w(f'**{author}** · {when(comment["createdAt"])}')
                w('')
                w('> _(comment no longer available through the API)_')
                w('')
                continue

            w(f'**{(full.get("user") or {}).get("login", "unknown")}**'
              f' · {when(full["created_at"])}')
            w('')
            # Only the first comment carries the anchor; the replies are to it.
            hunk = hunk_tail(full.get('diff_hunk')) if i == 0 else None
            if hunk:
                w('```diff')
                w(hunk)
                w('```')
                w('')
            w(quote(full.get('body')))
            w('')

    w('---')
    w('')
    w('## Review summaries')
    w('')
    for review in sorted((r for r in summaries if (r.get('body') or '').strip()),
                         key=lambda r: r.get('submitted_at') or ''):
        w(f'### {(review.get("user") or {}).get("login", "unknown")}'
          f' · {when(review.get("submitted_at"))} · {review.get("state", "")}')
        w('')
        w(quote(review['body']))
        w('')

    w('---')
    w('')
    w('## Conversation')
    w('')
    for comment in sorted(conversation, key=lambda c: c['created_at']):
        w(f'### {(comment.get("user") or {}).get("login", "unknown")}'
          f' · {when(comment["created_at"])}')
        w('')
        w(quote(comment.get('body')))
        w('')

    sys.stdout.write('\n'.join(out).rstrip() + '\n')


if __name__ == '__main__':
    main(sys.argv)
