#!/usr/bin/env python3
import re
import sys
import os
import glob
from collections import defaultdict

# -----------------------------------------------------------------------------
# Regex Cleaning Logic
# -----------------------------------------------------------------------------

def _replace_quoted_capture(match):
    """
    Helper for clean_regex. Simplifies "Floor (?<floor>.+)" -> <floor>
    """
    quoted_content = match.group(1)
    # Find if there's a named capture group inside
    name_match = re.search(r'\(\?<([^>]+)>[^)]+\)', quoted_content)
    if name_match:
        return f"<{name_match.group(1)}>"
    return match.group(0) # Keep as is if no named capture

def clean_regex(regex):
    """
    Simplifies an Elixir regex string into a human-readable Gherkin step.
    """
    # Remove ^ and $ anchors
    regex = regex.lstrip('^').rstrip('$')
    
    # Target quoted strings that contain named captures
    regex = re.sub(r'"([^"]*)"', _replace_quoted_capture, regex)
    
    # Catch any remaining named captures outside quotes
    # e.g., floor (?<floor>.+) -> floor <floor>
    regex = re.sub(r'\(\?<([^>]+)>[^)]+\)', r'<\1>', regex)
    
    # Remove escaping for quotes
    regex = regex.replace('\\"', '"')
    
    return regex.strip()

# -----------------------------------------------------------------------------
# File Processing Logic
# -----------------------------------------------------------------------------

def collect_files(args):
    """
    Expands globs and directories into a list of .exs files.
    """
    files_to_process = []
    for arg in args:
        if '*' in arg:
            files_to_process.extend(glob.glob(arg, recursive=True))
        elif os.path.isdir(arg):
            files_to_process.extend(glob.glob(os.path.join(arg, "**/*.exs"), recursive=True))
        else:
            files_to_process.append(arg)
    return [f for f in files_to_process if f.endswith('.exs')]

def extract_steps_from_file(file_path):
    """
    Parses a single Elixir file for Cabbage step definitions.
    """
    with open(file_path, 'r') as f:
        content = f.read()

    # Pattern for Cabbage step definitions: defgiven ~r/pattern/, ...
    pattern = r'def(given|when|then)\s+~r/([^/]+)/'
    matches = re.finditer(pattern, content, re.IGNORECASE)
    
    steps = []
    filename = os.path.basename(file_path)
    for match in matches:
        step_type = match.group(1).lower()
        raw_regex = match.group(2)
        
        # Calculate line number: count newlines before the match start index
        line_number = content.count('\n', 0, match.start()) + 1
        
        steps.append({
            'type': step_type,
            'text': clean_regex(raw_regex),
            'file': filename,
            'line': line_number
        })
    
    return steps

# -----------------------------------------------------------------------------
# Output & Grouping Logic
# -----------------------------------------------------------------------------

def group_steps(all_steps):
    """
    Groups steps by type (given, when, then).
    """
    grouped = defaultdict(list)
    for step in all_steps:
        grouped[step['type']].append(step)
    return grouped

def render_markdown(grouped_steps):
    """
    Prints the grouped steps as a Markdown glossary.
    """
    print("# Cabbage Step Definitions Glossary\n")

    # Fixed Gherkin order
    for step_type in ["given", "when", "then"]:
        if step_type not in grouped_steps:
            continue
            
        print(f"## {step_type.capitalize()} Steps\n")
        print("| Step | Source |")
        print("| :--- | :--- |")
        
        # Sort alphabetically and handle unique (text, file) pairs
        sorted_steps = sorted(grouped_steps[step_type], key=lambda x: x['text'])
        for step in sorted_steps:
            # Italicize placeholders: <name> -> _\<name\>_
            display_text = re.sub(r'<([^>]+)>', r'_\<\1\>_', step['text'])
            # Format: | _text_ | file:line |
            print(f"| {display_text} | {step['file']}:{step['line']} |")
        print()

# -----------------------------------------------------------------------------
# Main Entry Point
# -----------------------------------------------------------------------------

def main():
    if len(sys.argv) < 2:
        print(f"Usage: {os.path.basename(sys.argv[0])} <file_or_glob> ...")
        sys.exit(1)

    # 1. Collect files
    files = collect_files(sys.argv[1:])
    
    # 2. Extract steps
    all_steps = []
    for file_path in files:
        all_steps.extend(extract_steps_from_file(file_path))

    # 3. Group and Render
    grouped = group_steps(all_steps)
    render_markdown(grouped)

if __name__ == "__main__":
    main()
