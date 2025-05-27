# Claude Code Working Agreement

## Core Principles
- Always use Test-Driven Development (TDD) - write tests first, then implementation
- Keep code clean, maintainable, and well-documented
- Think before coding - plan architecture and approach first
- Batch related tasks to maximize plan efficiency
- Maintain tidy git history with meaningful commits

## Development Workflow

### 1. Planning Phase
- Research existing codebase patterns before implementing
- Create detailed implementation plan before coding
- Consider edge cases and error handling upfront
- Use "think hard" for complex architectural decisions

### 2. Implementation Phase
- Write failing tests first (red phase)
- Implement minimal code to pass tests (green phase)
- Refactor for clarity and performance (refactor phase)
- Update documentation alongside code changes

### 3. Quality Assurance
- Run all tests before marking tasks complete
- Execute linting and type checking if available
- Verify no regression in existing functionality
- Clean up any debugging code or console logs

### 4. Git Hygiene
- Make atomic commits with clear messages
- Never commit commented-out code
- Update .gitignore for new generated files
- Create descriptive PR summaries

## Code Standards

### General
- Prefer clarity over cleverness
- Use descriptive variable and function names
- Keep functions small and focused (single responsibility)
- Add comments only when the "why" isn't obvious
- Remove dead code immediately

### Error Handling
- Always handle errors explicitly
- Provide meaningful error messages
- Log errors appropriately for debugging
- Never silently swallow exceptions

### Testing
- Aim for high test coverage on business logic
- Test edge cases and error paths
- Use descriptive test names that explain the scenario
- Keep tests independent and idempotent

### Python Specific
- Use type hints for all function signatures
- Follow PEP 8 with 2-space modification
- Prefer f-strings for string formatting
- Use pytest fixtures for test setup
- Import order: stdlib, third-party, local
- Use `if __name__ == '__main__':` for scripts
- Prefer pathlib over os.path
- Use context managers for resource handling

## Documentation

### Code Documentation
- Document public APIs and interfaces
- Include examples in documentation
- Keep README files up to date
- Document breaking changes clearly

### Project Documentation
- Maintain architecture decision records (ADRs)
- Document setup steps for new developers
- Keep dependency documentation current
- Note any non-obvious design decisions

## Task Management

### Todo Lists
- Create comprehensive todo lists for all non-trivial tasks
- Break down complex tasks into specific, actionable items
- Mark items as in_progress when starting, completed when done
- RETAIN completed todo lists for review - do not clear them
- Use todo lists to track progress and ensure nothing is missed

## Session Efficiency

### Planning Requests
- "Research and create a detailed plan for [feature]"
- "Think hard about the architecture for [system]"
- "Analyze existing patterns before implementing [component]"

### Implementation Requests
- "Using TDD, implement [feature] with comprehensive tests"
- "Refactor [module] for better maintainability, preserving all tests"
- "Add error handling and tests for edge cases in [component]"

### Batch Operations
- Combine related tasks in single requests
- Group file reads/edits efficiently
- Plan multi-step operations upfront

## Project Maintenance

### Regular Tasks
- Review and update dependencies safely
- Refactor code when patterns emerge
- Update documentation with code changes
- Clean up technical debt incrementally

### Before Completing Features
- Ensure all tests pass
- Run linting and formatting tools
- Update relevant documentation
- Verify feature works end-to-end

## Communication Style

### Progress Updates
- Be concise but informative
- Report completion of major steps
- Flag any concerns or blockers early
- Suggest improvements when found
- NEVER use emojis in code, commits, documentation, or responses unless explicitly requested

### Problem Solving
- Explain reasoning for technical decisions
- Present tradeoffs clearly
- Recommend best practices
- Identify potential future issues

## Gotchas & Reminders

### Always
- Check for existing implementations before creating new ones
- Verify file paths before creating new files
- Test edge cases and error conditions
- Consider security implications

### Never
- Commit secrets or API keys
- Leave console.log statements in production code
- Create files without explicit need
- Make assumptions about external dependencies
- Use emojis anywhere (code, commits, docs, responses) unless explicitly requested

## Quick Commands Reference
- Start with research: "analyze the codebase for [pattern]"
- TDD implementation: "write tests then implement [feature]"
- Refactor safely: "refactor [code] maintaining all tests"
- Document changes: "update docs to reflect [changes]"

## Personal Preferences
- Preferred testing framework: pytest (Python)
- Code style: 2 spaces, trailing commas, single quotes
- Commit format: conventional commits (feat:/fix:/docs:/test:/refactor:/chore:)
- Review process: self-review checklist before marking complete
- Todo lists: Create comprehensive todo lists for all tasks and RETAIN them after completion for review