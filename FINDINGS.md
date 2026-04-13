# Mentorio AI Response Issue - Audit Findings

## Issue
AI returns conversational text ("Окей, я готов") instead of raw JSON

## Root Cause
**File:** MentorioAIService.swift
**Line:** 205
**Problem:** The getCoreHighlightChoices function contains conflicting instructions

In the selectedTopic branch (when user focuses on a specific topic):
```swift
"TASK:\n" +
"1. Act as a \"Thinking Friend\".\n" +
"2. Map the user's bottleneck..."
```

This explicitly tells the model to adopt a conversational, helpful role.

But earlier in focusPrompt, the instruction is:
```
"ВОЗВРАЩАЙ ТОЛЬКО JSON" (Return ONLY JSON)
```

## Why This Causes the Problem
The model receives two contradictory directives:
1. "Be a helpful friend and engage conversationally" 
2. "Return only JSON"

When an AI receives conflicting instructions, it prioritizes the first one it encounters. The conversational role directive comes after the JSON requirement, so the model says "Okay, let me be helpful" ("Окей, я готов") instead of returning JSON.

## Contributing Factors
1. **focusPrompt line 59:** Conversational opening "Ты — Mentorio. Intelligent Mirror..." primes role-playing behavior
2. **focusPrompt examples:** Hardcoded personal data (Никита, FL Studio, EKOF, Белград) causes hallucination when user input differs
3. **cleanJSONText function:** Silently returns non-JSON text instead of throwing an error, masking the real issue

## MentorioViewModel.swift
Status: ✅ No issues. Correctly implements state machine and error handling.

## Required Fix
Remove or eliminate the "Act as a Thinking Friend" instruction from line 205-207 in getCoreHighlightChoices. Replace with a unified prompt that uses only focusPrompt (which should be simplified to focus on JSON-only generation).

---

**Audit Date:** Current Session
**Status:** Complete
**Recommendation:** Implement unified prompt system in getCoreHighlightChoices with pure JSON-focused instructions and removal of all conversational framing.
