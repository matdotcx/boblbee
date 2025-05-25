# Global Claude Code Preferences

## Core Principles
- Always use Test-Driven Development (TDD)
- Keep code clean, maintainable, and well-documented
- Think before coding - plan architecture and approach first
- Batch related tasks to maximize plan efficiency

## Code Standards
- Preferred language: Python
- Testing framework: pytest
- Code style: 2 spaces, trailing commas, single quotes
- Commit format: conventional commits (feat:/fix:/docs:/test:/refactor:/chore:)
- Import order: stdlib, third-party, local

## Communication Style
- Be concise and direct
- NEVER use emojis in code, commits, documentation, or responses unless explicitly requested
- Report completion of major steps
- Flag concerns early

## Development Workflow
- Write failing tests first (red phase)
- Implement minimal code to pass tests (green phase)
- Refactor for clarity and performance (refactor phase)
- Run linting and type checking before marking complete
- Self-review checklist before marking complete

## Task Management
- Create comprehensive todo lists for all non-trivial tasks
- Mark items as in_progress when starting, completed when done
- RETAIN completed todo lists for review - do not clear them
- Break down complex tasks into specific, actionable items

## Python Specific
- Use type hints for all function signatures
- Prefer f-strings for string formatting
- Use pytest fixtures for test setup
- Prefer pathlib over os.path
- Use context managers for resource handling
- Use `if __name__ == '__main__':` for scripts

## Documentation
- Document public APIs and interfaces
- Include examples in documentation
- Keep README files up to date
- Document breaking changes clearly