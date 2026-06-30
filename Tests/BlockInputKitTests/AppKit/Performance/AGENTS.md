## Performance Tests

- Keep large-document tests focused on bounded work for visible rows, granular mutations, coalesced snapshots, and hot typing/Return/Undo paths.
- Benchmark same-row replacements and large-document mutation flows with `--benchmark-100k-mutations` when behavior changes could affect visible-row reuse or store-backed operations.
