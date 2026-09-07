# Antigravity Agent Rules: Society Management Application

## 🚨 P0 Rule: Architecture Consistency, Code Reuse & Professional Standards
> **CRITICAL & MANDATORY:** Whenever new code is written in this codebase:
> 1. **Follow Current Architecture & Patterns:** Always adhere to the existing architectural approach, established patterns, and directory conventions of the codebase.
> 2. **Maximize Code Reuse:** Always check and reuse existing domain models (`MaintenanceDueModel`, `SocietyTransactionModel`, `AppUser`), shared utilities (`AppFormatters`, `FlatUtils`), centralized configuration (`SocietyConfig`), and shared services (`NotificationService`) before creating new logic or duplicating code. Never write redundant one-off inline boilerplate.
> 3. **Professional Coding Standards:** Write code to production-grade standards — strong typing, atomic multi-document operations (`WriteBatch`), robust error handling, full null safety, zero static analysis warnings/errors (`flutter analyze`), and strict separation of UI, business logic, and data layers.

## 1. Project Context & Objectives
You are operating within a Society Management Application. This system handles resident directories, maintenance billing, facility bookings, visitor management, and helpdesk ticketing. 
* **Primary Goal:** Write clean, modular, and secure code while providing verifiable artifacts for all changes.
* **Security First:** Multi-tenant data isolation and role-based access control (Admin, Resident, Security) are critical. Never expose sensitive PII (Personally Identifiable Information).

## 2. Antigravity Agent Orchestration & Workflows
As an Antigravity Agent, you must leverage your orchestration capabilities and follow these workflow constraints:

* **Artifact Generation:** Before writing or modifying code, always generate an **Implementation Plan** (Markdown blueprint) and a **Task List**. Wait for developer approval unless the workspace review policy is set to `Always Proceed`.
* **Subagent Delegation:** Do not crowd the parent agent's context window. Use the `invoke_subagent` tool for multi-step tasks:
  * Spin up a `research` subagent when analyzing large repository dependencies or architecture.
  * Spin up a `browser` subagent for headless UI testing and web integration tasks.
* **Workspace Modes:** 
  * Use `branch` mode to spin up a dedicated, isolated Git worktree when developing new features (e.g., building the facility booking module).
  * Use `inherit` mode for minor bug fixes or linting directly in the current folder.
* **Context-Lean Handoffs:** Ensure child agents return structured, concise summaries to the parent agent upon completion, then terminate cleanly.

## 3. Code Writing & Architecture Best Practices
* **Component Modularity:** Break down features into independent modules (e.g., `billing`, `visitors`, `users`). 
* **State Management & UI:** When generating frontend code, ensure the UI is responsive and accessible. Leave inline diffs for the developer to review one hunk at a time.
* **Database & MCP:** If interacting with external databases via the Model Context Protocol (MCP), use parameterized queries or an ORM to prevent SQL injection. 
* **Error Handling:** Fail gracefully. Provide user-friendly error messages on the frontend and detailed stack traces in the backend logs.

## 4. Testing, Verification, and Auditable Evidence
Do not just claim a task is done; prove it using Antigravity's evidence-based artifacts:
* **UI Verification:** Use the `browser` subagent to navigate the frontend. Generate **Screenshots** (before and after) and **Browser Recordings** for dynamic interactions (e.g., "Click the login button, verify the resident dashboard loads").
* **Automated Tests:** Write unit tests for all business logic (like maintenance fee calculations). Provide structured logs of passing/failing tests in the artifact viewer.
* **Terminal Operations:** Respect the developer's terminal execution settings (Off, Auto, or Turbo). Always prompt for permission (`Request Review`) before running database migrations, destructive file operations, or installing unverified packages.

## 5. Final Walkthrough 
Upon completion of a task, compile a **Walkthrough** artifact summarizing the changes, files modified, and exact steps the developer should take to manually verify the deployment locally.