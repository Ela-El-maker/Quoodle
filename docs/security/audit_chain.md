# Audit Chain

Audit entries are hash-linked (prev_hash + payload_hash) and signed. Webhook handlers append to udit_trails via AuditTrailController. Stored hash returned to upstream systems for verification. Hash chain ensures tamper evidence for command, update, policy, and security events.
