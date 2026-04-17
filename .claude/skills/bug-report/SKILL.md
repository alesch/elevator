---
name: bug-report
description: >
  Format a bug report using the project template and publish it as a GitHub issue.
  Use when a bug, logic gap, or specification contradiction has been identified.
---

# Bug Report Skill

You are creating a structured bug report and publishing it as a GitHub issue.

## Step 1: Gather Information

If the user has not already provided it, ask for:
- A short descriptive title
- The component affected
- The incorrect behavior (and root cause if known)
- The expected behavior
- How to reproduce it (failing test command, scenario name, observed error)
- A proposed solution (can be "unknown" if not yet determined)

## Step 2: Format the Report

Use this exact template — no emojis or icons:

```markdown
# [Short Descriptive Title]

## Context
- **Scenario**: @[Scenario-ID] (if applicable)
- **Component**: [Component Name]
- **Source Reference**: [filename](file:///path/to/file)

## Current Status / Issue
[Describe the incorrect behavior and root cause if known.]

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

## Step 3: Review with User

Render the formatted report and ask the user to confirm before publishing.

## Step 4: Publish to GitHub

Once the user approves:

1. Write the report body to a temp file, e.g. `/tmp/bug-report-[slug].md`
2. Run:
   ```bash
   gh issue create --title "[Title]" --body-file /tmp/bug-report-[slug].md --label "bug"
   ```
3. Report the issue URL back to the user.

## Rules

- One bug per issue — never combine separate root causes.
- Always link to the Gherkin Scenario (`@S-...`) or Technical Requirement (`@R-...`) being violated.
- Use `file:///` URIs for source references so agents and developers can navigate directly.
- If multiple bugs share a root cause, merge them into a single consolidated report.
- Do NOT include `[BUG]` in the title — the `bug` label handles that.
