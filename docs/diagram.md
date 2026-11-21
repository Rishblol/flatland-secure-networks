# Flatland topology

## Flat layout

All six workloads share the Docker bridge `flatland-flat_flat`. Docker assigns the addresses when the project starts.

```mermaid
flowchart TB
    flat["Shared internal Docker bridge"]
    workstation["Workstation"] --- flat
    web["Web server"] --- flat
    app["Application server"] --- flat
    database["Database host"] --- flat
    file["File server"] --- flat
    jump["Admin jump host"] --- flat
```

## Segmented layout

Each zone has its own internal macvlan network and a separate Docker-created dummy parent link. Endpoints start in private mode and switch to bridge mode during startup. The router is the only container with an interface in more than one zone.

```mermaid
flowchart TB
    router["Router · nftables forwarding policy"]

    subgraph user["User · 10.149.240.0/26"]
        workstation["workstation · 10.149.240.10"]
    end
    subgraph dmz["DMZ · 10.149.240.64/26"]
        web["web · 10.149.240.74"]
    end
    subgraph server["Server · 10.149.240.128/26"]
        lan["Shared server network"]
        lan --- app["app · 10.149.240.138"]
        lan --- database["database · 10.149.240.139"]
        lan --- file["file · 10.149.240.140"]
    end
    subgraph management["Management · 10.149.240.192/26"]
        jump["jump · 10.149.240.202"]
    end

    workstation ---|"zone-user · 10.149.240.2"| router
    web ---|"zone-dmz · 10.149.240.66"| router
    lan ---|"zone-server · 10.149.240.130"| router
    jump ---|"zone-mgmt · 10.149.240.194"| router
```

The diagram shows network attachments. Consult the [flow matrix](flow-matrix.md) for the permitted connections. For B01, the workstation reaches the DMZ subnet through `10.149.240.2` and the web server returns traffic through `10.149.240.66`. B03 follows the shared server network directly.
