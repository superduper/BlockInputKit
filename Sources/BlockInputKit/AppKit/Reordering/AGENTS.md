## Reordering

- Keep only one visible reorder handle revealed at a time.
- Cancel multi-selection when block reordering starts from either the collection-view drag path or the leading reorder handle; do not wait for the drop.
- When reordering ordered-list blocks, keep nested marker starts normalized and publish replacement mutations from the model-reported changed blocks; large-document store-backed reorders should use the bounded list move path instead of full snapshots or whole-document diffs.
- For marker-adjusting stores, use move-plus-marker-transaction sync for top-level numbered-list reorders instead of marker-only replacement storms.
