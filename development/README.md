# Development Specifications

This directory contains plans and specifications for substantial changes that are difficult to reason about safely as isolated patches.

Use it when a change:

- crosses repository or module boundaries;
- changes a binary interface or shared data layout;
- introduces or changes architectural state;
- requires an ordered migration with intermediate validation;
- would be expensive to diagnose after later features depend on it.

Small fixes and local refactors do not require a document here.

## Document lifecycle

Each specification must state one of these statuses near the top:

- `Draft`: discussion is active and implementation is not approved.
- `Accepted`: scope, decisions, risks, and acceptance criteria are approved.
- `In Progress`: implementation follows the accepted specification.
- `Completed`: implementation and required validation are complete.
- `Superseded`: another document replaces this specification.

Changing a status does not replace verification. A document may only become `Completed` after it records the exact validation commands and result summary.

## Required content

Specifications should contain:

- context and observed baseline;
- goals and explicit non-goals;
- affected modules and interfaces;
- confirmed decisions;
- proposals that still require approval;
- invariants and ownership boundaries;
- migration and rollback order;
- risks and failure modes;
- acceptance criteria and validation commands;
- open questions.

Keep confirmed decisions separate from proposals. Do not present an unresolved design as repository policy.

## Maintenance

- Use lowercase, hyphen-separated filenames.
- Prefer one document per coherent architectural change.
- Update the document when an approved decision changes.
- Preserve completed specifications as design history.
- Link a superseding document instead of silently rewriting historical decisions.
- Treat source code, tests, and generated checks as the final executable evidence; this directory records intent and reasoning.
