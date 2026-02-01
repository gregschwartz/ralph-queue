# ralph-tasks Specification

## Overview
Unified task management CLI for Ralph task queue system.

## CLI Commands

### Priority Shortcuts (Default Behavior)
- `ralph-tasks h "description"` - Add high priority task
- `ralph-tasks m "description"` - Add medium priority task
- `ralph-tasks l "description"` - Add low priority task
- `ralph-tasks "description"` - Add medium priority task (default)

### Commands
| Command | Aliases | Description |
|---------|---------|-------------|
| `add` | `a` | Add a new task |
| `list` | `ls` | List all tasks |
| `next` | `n` | Show next task in queue |
| `show` | `s` | Show task details |
| `done` | `d`, `complete` | Mark task as done |
| `skip` | - | Skip current task |
| `queue` | `q` | Show queue status |
| `start` | `run` | Process all tasks automatically |
| `failed` | `fail`, `f` | Mark task as failed |
| `count` | `c` | Count pending tasks |
| `help` | `--help`, `-h` | Show help |

### Command Options
- `add`: `-p/--priority H|M|L`, `--project`
- `list`: `--project`, `--status pending|done|all`
- `start`: `--max-tasks N`
- `queue`: `--load`

## Task File Format

### Naming: `{PRIORITY}_{DATE}_{SLUG}.md`
Example: `H_2026-01-31_fix_critical_bug.md`

### Content Template
```markdown
# {description}

**Priority:** H|M|L
**Created:** {datetime}
**Status:** Active

## Description
{description}

## Subtasks
- [ ]

## Notes

## Blockers
None

## Attempts
```

## Queue Management

### Priority Order: H > M > L

### Files
- `.ralph/.task_queue` - List of pending task paths
- `.ralph/.current_task` - Path to active task
- `.ralph/PROMPT.md` - Generated prompt for ralph_loop

### Queue Patterns Recognized
- `H_*.md`, `M_*.md`, `L_*.md`
- `H-*.md`, `M-*.md`, `L-*.md`
- `*_H_*.md`, `*_M_*.md`, `*_L_*.md`

## Retry Logic

### Configuration
- `RALPH_TASK_MAX_ATTEMPTS=3`

### Attempt Tracking (IN TASK FILE)
```markdown
## Attempts
- **Attempt 1**: 2026-01-31 10:30:45
  - Error: {error message}
  - Why: {explanation}
```

### Flow
1. Check attempts BEFORE running
2. If >= max, skip and move to failed/
3. Run ralph_loop, capture exit code
4. On failure: log attempt, increment count, retry or fail
5. On success: log completion, move to done/

## Task Completion Detection

### Exit Code Handling
- `> 128`: Killed by signal (signal = code - 128) → FAILED
- `!= 0`: Error → FAILED
- `== 0`: Check completion signals

### Completion Signals (when exit code == 0)
1. `.response_analysis` JSON: `exit_signal == "true"` or `status == "COMPLETE"`
2. Output contains `TASK_COMPLETE`

If neither found → FAILED (didn't complete)

## Logging Requirements

### CRITICAL: Dual Output
ALL output from `start` command MUST go to:
1. Screen (stdout) - real-time
2. Log file (`/tmp/ralph-tasks.log`) - persistent

Use: `run_function 2>&1 | tee /tmp/ralph-tasks.log`

### Debug Output
Always show:
- Exit code from ralph_loop
- Completion detection results
- Final task status

## Configuration

### Environment Variables
| Variable | Default | Description |
|----------|---------|-------------|
| `RALPH_DIR` | `.ralph` | Working directory |
| `RALPH_LOOP_SCRIPT` | `~/.ralph/ralph_loop.sh` | Ralph script |
| `RALPH_TASK_MAX_ATTEMPTS` | `3` | Max retries |
| `RALPH_TASK_DIRS` | (auto) | Task directories |

### Config Files
- `./.ralphrc`
- `~/.ralphrc`

## Directory Structure
```
project/
  tasks/
    H_*.md, M_*.md, L_*.md
    done/
    failed/
.ralph/
  .current_task
  .task_queue
  .response_analysis
  .last_ralph_output
  PROMPT.md
```
