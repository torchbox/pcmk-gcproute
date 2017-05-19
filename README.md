# Pacemaker GCP route resource

This is a resource agent for Pacemaker to manage Google Cloud Platform routes.

Because GCP does not use ARP to map IP addresses to hosts, Pacemaker's IPaddr2
resource doesn't work; the IP is added to the server correctly, but no traffic
will be routed to it unless a route for that IP address is added at GCP.  This
resource agent handles creating that route.

Install:

```
# mkdir -p /usr/lib/ocf/resource.d/tbx
# cp gcproute.sh /usr/lib/ocf/resource.d/tbx/gcproute
# chmod 755 /usr/lib/ocf/resource.d/tbx/gcproute
```

Use it together with IPaddr2 like this:

```
primitive my-ip-addr IPaddr2            \
        params  ip=172.31.248.1         \
                cidr_netmask=32         \
                nic=lo                  \
        op monitor interval=10s

primitive my-ip-route ocf:tbx:gcproute          \
        params  name=postgres-3                 \
                network=itl                     \
                prefix=172.31.248.1             \
                prefix_length=32                \
        op monitor interval=10s timeout=30s     \
        op start timeout=30s interval=0         \
        op stop timeout=30s interval=0          \
        meta target-role=Started

group my-ip my-ip-addr my-ip-route
```

The virtual IP address should be outside the GCP network, to avoid conflicts.
It doesn't matter what network it's in, and no route for the network need exist
beforehand.

The route will be added using the instance's service account credentials;
therefore, the service account must have the compute.networkAdmin role.

## License

Copyright (c) 2017 Torchbox Ltd.

Permission is granted to anyone to use this software for any purpose,
including commercial applications, and to alter it and redistribute it
freely. This software is provided 'as-is', without any express or implied
warranty.
