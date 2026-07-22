# OPNS-RNS-Post-Bridge — Planning & Architecture

## What exists

| Component | Status | Notes |
|-----------|--------|-------|
| `rnsd` (Rust binary) | ✅ Built | From `../Reticulum-rust/` |
| `BackboneInterface` | ✅ Built | TCP server, spawns per-client interfaces |
| `TcpClientInterface` | ✅ Built | TCP client with HDLC/KISS framing |
| `reticulum_rust` config parser | ✅ Built | TOML config file reader |
| OPNSense plugin scaffold | ✅ Built | This project |
| OPNSense MVC (UI forms) | ✅ Built | Web UI for config |
| Reticulum-PHP PostInterface | ✅ Built | HTTP exchange at `/v1/interfaces/exchange` |

## What needs to be built

### 1. Rust `PostInterface` (HTTP client) — **MISSING**

The core missing piece. `rnsd` has no way to talk to PHP PostInterface nodes
because it lacks an HTTP-based interface. We need to add a
`PostInterface` to `reticulum_rust/src/interfaces/` that:

```
┌─────────────────────┐                         ┌──────────────────────┐
│  rnsd (Rust)        │  HTTP POST              │  Reticulum-PHP Node  │
│                     │  ──────────────────────► │  (Retichat/selectiv) │
│  PostInterface      │  /v1/interfaces/exchange │                      │
│  (HTTP client)      │  ◄────────────────────── │  PostInterface       │
│                     │  msgpack body            │  (HTTP server)       │
└─────────────────────┘                         └──────────────────────┘
```

**Exchange protocol** (reverse-engineered from PHP `post_interface.php`):

1. **Poll mode**: Periodically POST to `{node_url}/v1/interfaces/exchange`
   - Body: msgpack-encoded array of outbound packets
   - Response: msgpack-encoded array of delivery packets
   - The PHP side handles rate limiting via `idle_exchange_interval_ms`

2. **Wake mode**: Idle until the remote sends a wake notification, then poll.
   - Wake URL: `{wake_url}` — the remote POSTs to this to trigger a poll.

**Implementation plan for `post_interface.rs`:**

```rust
// reticulum_rust/src/interfaces/post_interface.rs

pub struct PostInterface {
    pub base: Interface,
    pub node_url: String,          // e.g. "https://retichat.com/reticulum"
    pub wake_url: Option<String>,  // optional wake endpoint
    pub poll_interval: f64,        // seconds between polls (min 2.0)
    pub interface_hash: Vec<u8>,  // registered ifac hash with remote
    pub running: Arc<AtomicBool>,
}

impl PostInterface {
    pub fn new(config: &HashMap<String, String>) -> Result<Self, String>;
    pub fn start_poll_loop(iface: Arc<Mutex<Self>>);
    
    // HTTP exchange
    async fn exchange(&self) -> Result<ExchangeResult>;
    
    // Register this interface with the remote PHP node
    async fn register_with_remote(&self) -> Result<Vec<u8>>;
    
    // Process incoming packets from exchange response
    fn process_inbound(&self, packets: Vec<Vec<u8>>);
    
    // Collect outbound packets for exchange request
    fn collect_outbound(&self) -> Vec<Vec<u8>>;
}
```

**Dependencies needed:**
- `reqwest` (HTTP client with TLS support for HTTPS nodes)
- `tokio` (already a dependency)
- Message format: msgpack (already available via `rmpv`)

**Key design decisions:**
- Follow DESIGN_PRINCIPLES.md §1: no retries, no timeout hacks
- Uses `Interface::process_incoming()` for inbound packet handling
- Uses `Transport::outbound()` for outbound packet queuing
- Registration flow: POST to `/v1/interfaces/register` to get an ifac hash

### 2. Bridge config wiring

The OPNSense config template already generates the right TOML for the bridge.
When `PostInterface` is implemented in Rust, the config section:

```toml
[[PostInterface Bridge]]
type = PostInterface
enabled = yes
node_url = "https://retichat.com/reticulum"
```

...will be parsed by `reticulum_rust::config` and instantiate a `PostInterface`.

### 3. Cross-compilation & packaging

- `cross` (cross-rs) for FreeBSD/amd64 builds — Dockerfile ready
- FreeBSD `.txz` package with +MANIFEST — scaffold ready
- `rc.d` service script — ready

## Build order

1. **Add `PostInterface` to `reticulum_rust`** — the core work
2. **Test locally** — spin up PHP test node, connect from Rust
3. **Cross-compile** — build `rnsd` for FreeBSD/amd64
4. **Package** — create `.txz` with all plugin files
5. **Install on OPNSense** — test end-to-end
6. **Iterate** — fix any FreeBSD-specific issues (signal handling, file paths)

## Config flow

```
OPNSense Web UI                    OPNSense config.xml
┌──────────────────┐              ┌──────────────────────┐
│ Services →       │   save       │ <OPNsense>           │
│ Reticulum Bridge │─────────────►│   <Rnsd>             │
│                  │              │     <general>        │
│  [Enable]  ☑     │              │       <enabled>1     │
│  [Node URL] ____ │              │       <NodeUrl>...   │
│  [Bind Port] 4242│              │       ...            │
│  [Save]          │              │     </general>       │
└──────────────────┘              │   </Rnsd>            │
                                  │ </OPNsense>          │
                                  └──────────┬───────────┘
                                             │
                                    reconfigure.php
                                             │
                                             ▼
                                  ┌──────────────────────┐
                                  │ /usr/local/etc/      │
                                  │   reticulum/config   │
                                  │ (TOML, generated)    │
                                  └──────────┬───────────┘
                                             │
                                    service rnsd restart
                                             │
                                             ▼
                                  ┌──────────────────────┐
                                  │       rnsd           │
                                  │  (reads config,      │
                                  │   starts interfaces) │
                                  └──────────────────────┘
```

## OPNSense plugin file layout

```
/usr/local/
├── bin/rnsd                                    # Rust binary
├── etc/
│   ├── rc.d/rnsd                               # rc.d service script
│   └── reticulum/
│       └── config                              # Generated config (TOML)
├── opnsense/
│   ├── mvc/app/
│   │   ├── controllers/OPNsense/Rnsd/
│   │   │   ├── IndexController.php
│   │   │   └── forms/general.xml
│   │   └── models/OPNsense/Rnsd/
│   │       ├── General.php
│   │       └── Menu/Menu.xml
│   ├── scripts/OPNsense/Rnsd/
│   │   └── reconfigure.php
│   └── service/
│       ├── conf/actions.d/actions_rnsd.conf
│       └── templates/OPNsense/Rnsd/rnsd.conf
├── share/reticulum/
│   └── reticulum.conf.example
└── var/log/reticulum/
    └── rnsd.log
```
