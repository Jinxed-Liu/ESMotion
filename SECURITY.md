# Security policy

ESMotion 0.2 performs no networking, remote asset loading, script execution, or
runtime shader compilation. It captures only views explicitly registered as
portal source or destination, and applies a hard combined byte budget before
keeping snapshots.

Custom `MotionPortalSnapshotProvider` closures execute in the host process on
the main actor. Treat their inputs as local rendering requests: do not perform
networking, query sensitive business data, decode unbounded input, or return
images larger than the requested budget.

Please report vulnerabilities privately through GitHub Security Advisories. Do
not open a public issue containing exploit details or user data.

The latest minor release receives security fixes during the 0.x series.
