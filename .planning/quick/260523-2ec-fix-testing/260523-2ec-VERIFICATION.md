---
status: passed
quick_id: 260523-2ec
---

# Verification: fix Testing

## Must-haves

| Truth | Status | Evidence |
|-------|--------|----------|
| swift test compiles all targets | PASS | Build completed without module errors |
| XCTest used consistently | PASS | No `import Testing` in Tests/ |
| Zero test failures | PASS | 149 executed, 0 failures |

## Command

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

## Result

```
Executed 149 tests, with 6 tests skipped and 0 failures (0 unexpected)
```

## Notes

- Six skips are expected when system audio recording permission is not granted.
- Use `./scripts/test.sh` when `xcode-select` targets Command Line Tools only.
