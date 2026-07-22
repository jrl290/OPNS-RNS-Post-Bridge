# OPNS-RNS-Post-Bridge

**Reticulum Network Stack Daemon (`rnsd`) packaged as an OPNSense plugin.**

This project compiles the Rust `rnsd` for FreeBSD/amd64 and packages it
as a native OPNSense plugin so it can be installed, configured via the
OPNSense web UI, and run as a managed service.

## Role

The bridge runs `rnsd` on an OPNSense router, connecting the local
Reticulum-PHP PostInterface backbone to the wider Reticulum network. It:

1. **Connects to a PostInterface PHP node** (e.g. Retichat or selectiv)
   via its HTTP exchange endpoint, acting as a TCP client interface that
   polls for packets.
2. **Serves as a BackboneInterface** for downstream RNS nodes on the LAN,
   providing a high-speed TCP listener they can connect to.
3. **Relays traffic** between the PostInterface peers and the LAN RNS mesh.

```
 ┌──────────────┐     HTTP/POST      ┌──────────────────┐     TCP/HDLC     ┌──────────────┐
 │  Retichat    │◄──────────────────►│  OPNSense rnsd   │◄───────────────►│  RTNode V3   │
 │  (PHP)       │   PostInterface    │  (this bridge)    │  Backbone       │  (ESP32)     │
 └──────────────┘                    └──────────────────┘                  └──────────────┘
                                           │
                                           │ TCP/HDLC
                                           ▼
                                    ┌──────────────┐
                                    │  LAN clients  │
                                    │  (Sideband,   │
                                    │   Meshchat)   │
                                    └──────────────┘
```

## Architecture

| Layer | Component | Description |
|-------|-----------|-------------|
| **Binary** | `rnsd` (Rust) | Reticulum Network Stack daemon, compiled for FreeBSD/amd64 |
| **Service** | `rc.d/rnsd` | FreeBSD rc.d service script for start/stop/status |
| **Config** | `/usr/local/etc/reticulum/config` | Standard Reticulum TOML config, generated from OPNSense config.xml |
| **UI** | OPNSense MVC | Web UI under Services → Reticulum Bridge |

## Directory Structure

```
OPNS-RNS-Post-Bridge/
├── README.md
├── Makefile                          # Top-level build targets
├── rnsd/
│   └── build.sh                      # Cross-compile rnsd for FreeBSD
├── cross/
│   ├── Dockerfile                    # FreeBSD cross-compilation container
│   └── cross.toml                    # cross-rs configuration
├── config/
│   └── reticulum.conf.example        # Example bridge config
└── pkg/                              # OPNSense plugin package
    ├── +MANIFEST
    ├── +POST_INSTALL
    ├── +PRE_DEINSTALL
    └── files/
        ├── usr/local/bin/rnsd
        ├── usr/local/etc/rc.d/rnsd
        ├── usr/local/opnsense/
        │   ├── service/
        │   │   ├── conf/actions.d/actions_rnsd.conf
        │   │   └── templates/OPNsense/Rnsd/rnsd.conf
        │   └── mvc/app/
        │       ├── controllers/OPNsense/Rnsd/
        │       │   ├── IndexController.php
        │       │   └── forms/general.xml
        │       └── models/OPNsense/Rnsd/
        │           ├── General.php
        │           └── Menu/Menu.xml
        └── usr/local/share/reticulum/   # Default config location
```

## Build

```bash
# Prerequisites: Rust toolchain, Docker (for cross-compilation), cross-rs
cargo install cross

# Build rnsd for FreeBSD/amd64
make rnsd

# Build the OPNSense plugin package (.txz)
make package
```

## Install on OPNSense

```bash
# Copy the .txz package to the OPNSense box
scp pkg/opns-rns-post-bridge-*.txz root@opnsense:/tmp/

# Install
ssh root@opnsense 'pkg install /tmp/opns-rns-post-bridge-*.txz'

# Or for development, install directly
make install OPNSENSE_HOST=192.168.1.1
```

## Configuration

After installation, the bridge appears in the OPNSense web UI under
**Services → Reticulum Bridge**. Configuration fields:

| Field | Description | Default |
|-------|-------------|---------|
| **Enabled** | Enable/disable the bridge service | `false` |
| **PostInterface Node URL** | PHP node exchange endpoint | `https://retichat.com/reticulum` |
| **PostInterface Wake URL** | Wake endpoint on the PHP node | (optional) |
| **Bind Address** | BackboneInterface listen address | `0.0.0.0` |
| **Bind Port** | BackboneInterface listen port | `4242` |
| **Log Level** | rnsd log verbosity (0-7) | `3` (LOG_NOTICE) |
| **MTU** | Interface MTU | `500` |

The OPNSense config template generates `/usr/local/etc/reticulum/config`
and restarts rnsd on changes.

## Design Principles

This project follows the [DESIGN_PRINCIPLES.md](../DESIGN_PRINCIPLES.md) of
the parent Reticulum monorepo. Key rules:

1. **5-second rule**: no late-success masking; every network op asserts ≤5s.
2. **We caused it**: every bug is our bug; external systems are correct.
3. **No retries, no timeouts-as-fix**: fix the ordering/readiness bug instead.

## License

MIT — see [LICENSE](../Reticulum-rust/LICENSE) for details.
