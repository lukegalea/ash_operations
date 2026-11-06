# Contributing

Thanks for helping. Run what CI runs before opening a pull request (Elixir 1.20 or later):

```sh
mix deps.get
mix format --check-formatted
mix compile --warnings-as-errors
mix test
mix credo --strict
mix docs --warnings-as-errors
mix spark.cheat_sheets --check
mix deps.unlock --check-unused
mix dialyzer   # informational, not blocking
```

If you change the DSL, run `mix spark.cheat_sheets` and commit the regenerated
`documentation/dsls/DSL-AshOperations.md`, and `mix spark.formatter` if you added an option.

## Tests

- Tests are plain ExUnit and run with `async: true` unless they share global state; say why in a
  comment when they do.
- Tests never touch the network. Use the local test server in `test/support` or a fixture.
- Add a test with every behaviour change, and a CHANGELOG line under "Unreleased".

Use short imperative commit subjects ("Refuse a spec without a pin").
