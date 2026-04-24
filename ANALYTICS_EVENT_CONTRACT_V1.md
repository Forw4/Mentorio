# Mentorio Analytics Event Contract (v1)

This contract defines product analytics events for the core loop:

braindump_started -> intent_route_detected -> intent_route_outcome -> choice_selected -> one_action_requested -> one_action_generated -> one_action_started -> reality_check_selected/reality_check_skipped -> one_action_completed

## Global Rules

- All product events MUST include:
  - channel = product
  - note_id
  - route
  - high_stakes (true/false)
  - attempts (clarifying attempts)
  - note_state
- Debug-only events MUST include channel = debug.
- Event names are snake_case and immutable.
- Timestamps are taken from event creation time.

## Product Events

### braindump_started
- Trigger: a new note is created.
- Required fields:
  - entry_point (main_input, diagnostics_seed, ...)

### intent_route_detected
- Trigger: route detected before AI request.
- Required fields: global only.

### intent_route_outcome
- Trigger: note transitions into a branch after response normalization.
- Required fields:
  - outcome (topics, question, choices, invalid)

### clarification_submitted
- Trigger: user submits clarification answer.
- Required fields: global only.

### choice_selected
- Trigger: user selects one of two tactics.
- Required fields:
  - choice_index
  - choice_text

### one_action_requested
- Trigger: app requests One Action from AI.
- Required fields:
  - choice_text

### one_action_generated
- Trigger: One Action generated and set to executing.
- Required fields: global only.

### one_action_started
- Trigger: user starts hold interaction for action completion.
- Required fields:
  - source (hold_button)
  - hold_duration_target_sec (3)

### reality_check_selected
- Trigger: user chooses a Reality Check option.
- Required fields:
  - reality_check_value

### reality_check_skipped
- Trigger: user bypasses Reality Check and keeps note in focus.
- Required fields:
  - skip_reason (keep_in_focus)

### one_action_completed
- Trigger: action is completed and archived.
- Required fields:
  - reality_check_value

### action_skipped
- Trigger: user continues with next step instead of completion.
- Required fields:
  - skip_reason

## Debug Events

Examples (non-exhaustive):
- gate_branch_triggered
- mirror_viewed
- diagnostics_seed_scenarios_spawned
- diagnostics_seed_scenarios_cleared
- test_scenarios_cleared

These events MUST use channel = debug and are excluded from product KPI dashboards.

## KPI Formulas

- Time to First Action (TFA):
  - per note: t(one_action_started) - t(braindump_started)
  - dashboard: average across notes with both events

- Time to First Completion (TFC):
  - per note: t(one_action_completed) - t(braindump_started)
  - dashboard: average across notes with both events

- Core Loop Completion Rate:
  - unique notes with one_action_completed / unique notes with one_action_generated

- Reality Check Capture Rate:
  - unique notes with reality_check_selected / unique notes with (reality_check_selected OR reality_check_skipped)
