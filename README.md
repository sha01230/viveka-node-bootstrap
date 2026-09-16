# VIVEKA Node Bootstrap

Public, auditable Windows bootstrap for preparing a host for later VIVEKA enrollment.

## Trust boundary

`PUBLIC BOOTSTRAP -> AUTHENTICATED ENROLLMENT -> PRIVATE RUNTIME`

Downloading or running this installer does **not** enroll or activate a node. It creates a local ECDSA P-256 enrollment identity using Windows CNG, protects the private key material with machine-scoped DPAPI plus restricted ACLs, enables Windows OpenSSH Server, records observed host facts, and writes a `PENDING` enrollment request with a human-verifiable pairing code.

The private key remains on the host. No Reality Lab source code, GitHub credential, enrollment token, global password, or reusable secret is embedded in this repository or installer.

## Output

After successful execution, the Desktop receives:

`VIVEKA_NODE_ENROLLMENT_REQUEST.json`

A durable copy and log live under:

`C:\ProgramData\VIVEKA_NODE\`

Enrollment requires explicit approval by a trusted VIVEKA authority holding the separate `ENROLLMENT_ISSUER` capability.
