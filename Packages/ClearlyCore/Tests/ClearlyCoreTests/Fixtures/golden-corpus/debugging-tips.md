# Debugging Tips

The order in which I work through a real bug.

1. **Reproduce it.** If you can't reproduce, you can't fix. The first half-hour goes to creating a reliable reproduction, even if the bug is flaky.
2. **Read the error.** Actually read it. Twice. The number of times the answer is in the first line of the stack trace and people skip past it is embarrassing.
3. **Bisect with git.** If it worked yesterday, `git bisect` finds the offending commit faster than you'd guess. Even on a non-test-suite codebase, manual bisect is a winning move.
4. **Print, don't reason.** The thing you "know" is true is exactly the thing the bug is hiding behind. Print the value. The fastest debuggers I've worked with print first, hypothesize second.
5. **Check the obvious assumption.** Off-by-one. Null. Empty string vs missing key. Timezone. Encoding. Caching. Ten times out of ten the bug is in the boring layer, not the clever one.
6. **Take a walk.** Stuck for an hour with no progress means the model in your head is wrong. Walking forces a re-read; you'll spot the wrong assumption faster than you would by staring.
