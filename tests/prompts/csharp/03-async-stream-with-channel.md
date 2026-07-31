# 03-async-stream-with-channel.md

## Prompt

Write a C# 12 class `LiveEventStream` that uses `System.Threading.Channels`
to push `LiveEvent` records to multiple async consumers. Producers
call `Publish(LiveEvent)`. Consumers call `SubscribeAsync(CancellationToken)`
which returns an `IAsyncEnumerable<LiveEvent>`. The stream must
complete cleanly when the producer calls `Complete()` and must respect
consumer cancellation.

## Acceptance

- [ ] Channel choice (`Unbounded` vs `Bounded`) justified in a comment.
- [ ] `SubscribeAsync` returns `IAsyncEnumerable<LiveEvent>`.
- [ ] On cancellation, the consumer's enumeration stops and the
      producer is **not** unsubscribed (other consumers keep working).
- [ ] `Complete()` causes all live enumerables to terminate after
      draining buffered items.
- [ ] No `lock` statements; channel is the synchronisation primitive.
- [ ] Tests use `Task.Delay` to simulate producers and consumers.
- [ ] `ConfigureAwait(false)` is used in library code (the class is
      library code; if the user marks it as application code, then
      it's not required — note this trade-off).

## Difficulty

Hard. Tests channels, async streams, and cancellation semantics.