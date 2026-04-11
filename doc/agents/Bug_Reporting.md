# Agent Guide: Reporting and Publishing Bugs

All identifications of bugs, logic gaps, or specification contradictions must be formatted according to the standard project template and published as GitHub issues for traceability.

## 1. The Bug Report Template

Use the following Markdown structure (no icons or emojis):

```markdown
# [Short Descriptive Title]

## Context
- **Scenario**: @[Scenario-ID] (if applicable)
- **Component**: [Component Name]
- **Source Reference**: [filename](file:///path/to/file)

## Current Status / Issue
[Describe the incorrect behavior and the root cause if known.]

## Expected Behavior
[Describe the correct behavior according to technical specs or Gherkin features.]

## How to Reproduce
- **Failing Test**: mix test [test_file].exs:[line_number]
- **Scenario**: [Scenario Name]
- **Observed**: [Specific mismatch or error message]

## Proposed Solution
[Outline the high-level steps or architectural changes needed.]

## Verification Plan
- [ ] [Specific test command or manual verification step]
```

## 2. Publishing to GitHub

Once the bug is identified and formatted:

1. **Save as Artifact**: Store the bug report in an artifact for iteration with the user.
2. **Publish via CLI**: Use the `gh` CLI to create the issue. Avoid including `[BUG]` in the title as the `bug` label should be used instead.

```bash
gh issue create --title "[Title]" --body-file [path/to/artifact.md] --label "bug"
```

## 3. Best Practices

- **Atomic Issues**: Record one bug per issue.
- **Traceability**: Always link to the Gherkin Scenario (`@S-...`) or Technical Requirement (`@R-...`) that is being violated.
- **Merge First**: If multiple identified bugs share a root cause, merge them into a single consolidated report before publishing to avoid duplicates.
- **Reference Code**: Use relative `file:///` URIs in the report to allow AI agents and developers to jump directly to the relevant code.
