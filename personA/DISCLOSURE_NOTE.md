# Disclosure note — Person A's rebuilt pipeline

Use this in your video narration or written submission, adapted to your own
voice. The goal is one honest sentence, not a lengthy justification.

## Suggested wording

> "Person A's original Azure resources were torn down between sessions to
> avoid ongoing cost. Their pipeline was already fully built and demonstrated
> working correctly — data cleaning, caching, and the analyze endpoint all
> confirmed live in an earlier test. To keep integration testing moving
> ahead of the deadline, I redeployed their exact code under my own Azure
> subscription, in a separate resource group, using the same function code
> and configuration they originally wrote and tested."

## Why this framing is accurate
- It doesn't claim continuity that isn't there ("respinning" implies the
  same resource coming back up — this is new resource, disclosed as such)
- It credits Person A's actual work (the code, the design, the earlier
  successful test) rather than implying you built the pipeline logic
- It gives the instructor the real timeline, so nothing looks concealed

## Where to put it
- Spoken, briefly, in the video right before/during the performance-
  optimization demo section
- Or as a one-paragraph note in your written submission / README, near
  wherever you describe the architecture

## What NOT to say
- Don't say "I respun Person A's resource" — say you redeployed a copy of
  their code under your own subscription
- Don't leave it unstated and let the video imply Julia's original resource
  is what's running
