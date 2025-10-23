# VPP on LX2160

# Building from Source

This process is left as an exercise for the reader - note that vpp should be compiled against the nxp version of dpdk.

# Prebuilt Binaries

[SolidRun Yocto BSP](https://github.com/SolidRun/meta-solidrun-arm-lx2xxx) is recommended, and the default `fsl-image-networking-full` comes with vpp preinstalled.
Binary images are available at [images.solid-run.com](https://images.solid-run.com/LX2k/meta-solidrun-arm-lx2xxx/) at `2025-07-08_952ba17/` or later.

In addition an oci container is available for import into docker (since 23/10/2025):

```
wget https://images.solid-run.com/LX2k/meta-solidrun-arm-lx2xxx/<version>/vpp-oci-image-lx216x.rootfs-oci.tar
mkdir vpp-oci-image; cd vpp-oci-image
tar --strip-components=1 -xf ../vpp-oci-image-lx216x.rootfs-oci.tar
skopeo copy oci:. docker-daemon:vpp-oci-image:latest
```

# Examples

## L2 Switch (LX2162A Clearfog)

### Create `/etc/vpp/startup.conf`

```
unix {
	nodaemon
	log /var/log/vpp/vpp.log
	full-coredump
	cli-listen /run/vpp/cli.sock
	interactive
}

logging {
	default-log-level debug
	default-syslog-log-level debug
}

api-trace {
	on
}

socksvr {
	default
}

cpu {
	main-core 0
	workers 15
}

buffers {
	buffers-per-numa 8000
}

dpdk {
	huge-dir /dev/hugepages
}
```

### Assign all upper row ports (2x SFP + 4x RJ45) to DPDK

```
for i in 9 11 2 3 4 5; do echo dpni.$i > /sys/bus/fsl-mc/drivers/fsl_dpaa2_eth/unbind; restool dpni destroy dpni.$i; done
export DPRC=dprc.2 DPDMAI_COUNT=38 MAX_TCS=16 MAX_QOS=32 MAX_QUEUES=12 MAX_CGS=18
bash /usr/share/dpdk/dpaa2/dynamic_dpl.sh dpmac.5 dpmac.3 dpmac.16 dpmac.15 dpmac.13 dpmac.14
dpdk-hugepages.py --setup 2G
```

### Start VPP

```
mkdir -p /var/log/vpp
vpp -c /etc/vpp/startup.conf
# or with docker
# docker run --rm -i -t -v /etc/vpp:/etc/vpp:ro -v /var/log/vpp:/var/log/vpp:rw vpp-oci-image -c /etc/vpp/startup.conf
```

### Enable L2 Bridge

1. Create Bridge:

       create bridge-domain 1 arp-term 1 mac-age 60 learn 1 forward 1

2. Add Interfaces to Bridge:

       set interface l2 bridge TenGigabitEthernet0 1
       set interface l2 bridge TenGigabitEthernet1 1
       set interface l2 bridge TenGigabitEthernet2 1
       set interface l2 bridge TenGigabitEthernet3 1
       set interface l2 bridge TenGigabitEthernet4 1
       set interface l2 bridge TenGigabitEthernet5 1

3. Enable all Interfaces:

       set interface state TenGigabitEthernet0 up
       set interface state TenGigabitEthernet1 up
       set interface state TenGigabitEthernet2 up
       set interface state TenGigabitEthernet3 up
       set interface state TenGigabitEthernet4 up
       set interface state TenGigabitEthernet5 up

L2 Switch is now operating:

    show bridge-domain 1 detail

**Note that VPP aborts after processing some packets for uknown reasons, likely related to buffers.**


