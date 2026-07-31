# 02-cancellationtoken-propagation-aspnet.md

## Prompt

Write a minimal ASP.NET Core 8 minimal-API endpoint
`GET /search?q=...` that calls a downstream `ISearchService` and returns
the results as JSON. The downstream call may take up to 5 seconds. The
endpoint must:

1. Honour client cancellation (browsers closing the tab).
2. Time out after 3 seconds with HTTP 504 if the downstream is slow.
3. Return HTTP 503 with a structured error body if `ISearchService`
   throws `SearchUnavailableException`.

## Acceptance

- [ ] Endpoint signature uses `async Task<IResult>`.
- [ ] `CancellationToken` is taken as a parameter and passed to
      `ISearchService.SearchAsync`.
- [ ] Timeout implemented via `CancellationTokenSource.CreateLinkedTokenSource`
      and `CancelAfter(TimeSpan.FromSeconds(3))`.
- [ ] Exception mapping uses a try/catch on the specific exception type,
      not `catch (Exception)`.
- [ ] DI registration shown (`AddScoped<ISearchService, ...>()`).
- [ ] Response DTOs are `record` types with PascalCase properties
      serialised as camelCase (default in minimal APIs).
- [ ] No `Thread.Sleep` anywhere; no `.Wait()` or `.Result`.

## Difficulty

Medium. Tests cancellation, timeout composition, and exception mapping.