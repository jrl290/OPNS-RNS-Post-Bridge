# OPNS-RNS-Post-Bridge Roadmap

## Phase 1: Rust PostInterface (current)

- [ ] Add `PostInterface` to `reticulum_rust/src/interfaces/`
  - HTTP client using `reqwest` + `tokio`
  - msgpack exchange protocol matching PHP `/v1/interfaces/exchange`
  - Interface registration with remote PHP node
  - Poll loop with configurable interval
  - Wake mode support (idle until remote notification)
- [ ] Add `reqwest` dependency to `reticulum_rust/Cargo.toml`
  - Feature flags: `rustls-tls` (avoid OpenSSL on FreeBSD)
- [ ] Add `PostInterface` to `interfaces/mod.rs`
- [ ] Test with local PHP node

## Phase 2: Cross-compile & package

- [ ] Verify `cross` build for `x86_64-unknown-freebsd`
- [ ] Resolve any FreeBSD-specific compilation issues
  - `libc` crate bindings
  - Signal handling (SIGTERM vs SIGINT)
  - Filesystem paths (/usr/local prefix)
- [ ] Build `.txz` package
- [ ] Test install on OPNSense VM

## Phase 3: OPNSense integration

- [ ] Verify rc.d service script works on actual OPNSense
- [ ] Test web UI config → config generation → service restart
- [ ] Test service monitoring in OPNSense dashboard
- [ ] Test log rotation & log viewing in UI

## Phase 4: Production hardening

- [ ] Add health check endpoint
- [ ] Add metrics/statistics collection
- [ ] Add interface status to web UI
- [ ] Test with real Retichat backbone
- [ ] Test with real RTNode V3 downstream
- [ ] Load testing
- [ ] Documentation
