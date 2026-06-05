# Ablation Evaluation Datasets

This folder contains the datasets used by the ablation evaluation scripts.

## Files

- `thingate_scenarios.json`
  - Source: `eval/datasets/thingate_scenarios.json`
  - Used by `eval/ablation_eval.py`.
  - 100 balanced scenarios for operational ablation.
  - Compares `none`, `3i4k_only`, `kote_only`, and `both`.

- `diagnostic_scenarios.json`
  - Source: `eval/datasets/diagnostic_scenarios.json`
  - Used by `eval/pure_ablation_eval.py`.
  - 100 diagnostic scenarios for pure-mode ablation.
  - Compares `none`, `kote_pure`, `3i4k_pure`, `both_pure`, and `current`.

- `diagnostic_dataset.md`
  - Source: `eval/datasets/diagnostic_dataset.md`
  - Human-readable explanation of the diagnostic ablation dataset.

## Original Scripts

```bash
python3 -m eval.ablation_eval --csv eval/out/ablation.csv
python3 -m eval.pure_ablation_eval --csv eval/out/pure_ablation.csv
```

The scripts still read from `eval/datasets/` by default. This folder is a
separate organized copy for reporting and submission.
