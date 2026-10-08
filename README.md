# TraceForge Chain

Blockchain infrastructure layer for **TraceForge**.

TraceForge Chain provides the Hyperledger Besu-based private blockchain network used by the TraceForge platform.

## Parent Project

This repository is the `chain/` submodule of
[TraceForge](https://github.com/aididalam/traceforge).
See the parent repository for all components, architecture and setup.

## Responsibilities

- Hyperledger Besu network configuration
- QBFT consensus configuration
- Genesis configuration
- Validator nodes
- RPC node
- Docker-based network orchestration
- Network startup, shutdown, reset, and health-check tooling

## Repository

[traceforge-chain](https://github.com/aididalam/traceforge-chain)

## Docker deployment

The parent repository provides Docker Compose configuration, private persistent
storage, runtime domain settings and backup/recovery commands. See the
[Docker deployment guide](https://github.com/aididalam/traceforge/blob/main/docs/docker-deployment.md).
Managed reference bootstrap is explicit; existing chains retain their genesis,
validator keys and storage format. Application updates do not reset validators.
