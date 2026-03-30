# Bloodlust Active-Only Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Bloodlust Sound trigger icon, timer, and audio only while a bloodlust-family buff is active, never from the exhaustion debuff cooldown.

**Architecture:** Keep the existing `BloodlustSound` module structure, but replace exhaustion-based aura detection with active-buff detection using the existing `BLOODLUST_AURA_IDS` catalog. Add a focused Lua runtime regression test that exercises `PLAYER_LOGIN` and `UNIT_AURA` with mocked player auras.

**Tech Stack:** Lua addon runtime, Lua test harness via `lupa`, Python pytest for source assertions.

---
