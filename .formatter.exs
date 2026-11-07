spark_locals_without_parens = [
  disclosure_gate: 1,
  documented_at: 1,
  effect: 1,
  idempotent?: 1,
  operation: 3,
  param: 2,
  param: 3,
  provider: 1,
  reconcile_with: 1,
  request: 1,
  response: 1,
  spec: 1,
  spec_sha256: 1,
  telemetry_prefix: 1,
  timeout: 1,
  transport: 1,
  discloses?: 1
]

[
  import_deps:
    [:ash, :spark] ++
      if(System.get_env("ASH_OPERATIONS_NO_A2UI") in ["1", "true"], do: [], else: [:ash_a2ui]),
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"],
  locals_without_parens: spark_locals_without_parens,
  export: [locals_without_parens: spark_locals_without_parens]
]
