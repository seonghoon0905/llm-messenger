# LLM Result Cases Dataset

This folder contains the C01-C25 dialogue scenarios used to inspect actual GPT
coaching outputs from `/analyze-draft` and `/llm-assist`.

## Files

- `llm_cases_c01_c25.json`
  - Source: `실습_Test/run_all_cases.py`
  - 25 dialogue scenarios (`C01`-`C25`)
  - Each item includes `relation`, `situation`, `register`, `messages`,
    `partner_last`, and `draft`.

- `llm_results_c01_c25.json`
  - Source: `실습_Test/results.json`
  - Saved GPT output from a previous run.
  - Contains `shouldInvokeLlm`, `shouldFeedback`, `feedback`, `rewrite`,
    `reason`, and `gate_msg` where the request succeeded.
  - In the saved run, `C18`-`C25` failed with `HTTP Error 502: Bad Gateway`.

## Original Runner

The original runner remains at:

```bash
python3 실습_Test/run_all_cases.py
```

It sends each case to `/analyze-draft`, then calls `/llm-assist` when ThinGate
decides that LLM review is needed.
