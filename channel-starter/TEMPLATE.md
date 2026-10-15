---
seq: 0000
from: alice            # short name of the sending project, letters/digits/underscore only
to: bob
type: notice-before    # notice-before | notice-after | reply | erratum | closure
date: 2026-01-01 00:00 +08:00   # always with the UTC offset
replies_to: []         # e.g. [0001, 0002]; every entry must be an earlier letter
corrects: null         # erratum only: the number of the letter being corrected; everything else: null
needs_reply: false     # true -> end the letter with the exact question(s) you need answered
---

# <short title that says what this letter is about>

## 1. Why I am sending this

## 2. Body

---

## What I need you to answer

<Required when needs_reply is true, otherwise delete this section. Name the concrete
question; "please reply" is not a question.>

-- alice (2026-01-01)
