# Architecture

**Status:** active

## Overview
Architecture of the **Hypercasual LLM** system — a Godot port of Moveborne split across three runtime services. A hard determinism wall runs through all of them: the **Client** ports the canonical TS rules engine byte-for-byte, the **Validator** re-runs that same engine to sign authoritative state, and the **Server** (Nakama) orchestrates matches and accepts validated actions.

Each service node links its **major subsystems** as child pages. The Client and Validator are fully documented; the Server is a stub (Nakama / Go, omitted in this port).

## Contents
- **Runtime Services** — The three deployable units. Client and Validator share the same engine and serialization; the Server ties them to multiplayer/persistence.
  - [Client](architecture:mq1c2hbg-000f-9qyhmz)
  - [Validator](architecture:mq1c2ixi-000h-kd018q)
  - [Server](architecture:mq1c2nid-000j-6cf0hr)
