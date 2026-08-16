# Unit-test baseline

Image `0.0.2-gdf45cf7416` (sources.lock as of 2026-08-16, empty patch queue):

    1226 passed, 13 failed, 116 errors, 1 xfailed  (18.8s)

The 13 failures + 116 errors are the environment-specific tail of upstream's
unit subset (mostly `test_tasks.py` needing runner internals a test pod does
not have) — recorded, not hidden. The gate for every patch: these numbers do
not change without the patch header explaining why. Full log:
`pytest-unit-0.0.2-gdf45cf7416.txt`.
