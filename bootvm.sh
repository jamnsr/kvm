TOTAL_CORES_MASK=FF             # 0-8, bitmask 0b11111111
HOST_CORES_MASK=3       	# 0,1, bitmask 0b00000011
VIRT_CORES='2-7'           	# Cores reserved for virtual machine(s)
NUM_HUGEPAGE=24			# 24G in 1GB hugepages
    
prepare_env() {
    ### SHIELD
    # Shield two cores cores for host and rest for VM(s)
    sudo cset shield --kthread on --cpu $VIRT_CORES
    # Reduce VM jitter: https://www.kernel.org/doc/Documentation/kernel-per-CPU-kthreads.txt
    sudo sysctl vm.stat_interval=120

    sudo sysctl -w kernel.watchdog=0
    # the kernel's dirty page writeback mechanism uses kthread workers. They introduce
    # massive arbitrary latencies when doing disk writes on the host and aren't
    # migrated by cset. Restrict the workqueue to use only cpu 0.
    echo $HOST_CORES_MASK | sudo tee /sys/bus/workqueue/devices/writeback/cpumask > /dev/null
    # THP can allegedly result in jitter. Better keep it off.
    echo never | sudo tee /sys/kernel/mm/transparent_hugepage/enabled > /dev/null
    # Force P-states to P0
    echo performance | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor > /dev/null
    echo 0 | sudo tee /sys/bus/workqueue/devices/writeback/numa > /dev/null
    echo "[+] SHIELD PLACED"

    ### HUGEPAGES
    sync
    echo 3 | sudo tee /proc/sys/vm/drop_caches > /dev/null
    echo 1 | sudo tee /proc/sys/vm/compact_memory > /dev/null
    echo $NUM_HUGEPAGE | sudo tee /sys/kernel/mm/hugepages/hugepages-1048576kB/nr_hugepages > /dev/null
    echo "[+] HUGEPAGES ALLOCATED"

    ### NETWORK
    # Use the preconfigured network from libvirt,
    # just add a new tap device to that libvirt bridge
    sudo ip tuntap add dev vmtap mode tap
    sudo ip link set dev vmtap master virbr0
    sudo ip link set dev vmtap up
    echo "[+] NETWORK STARTED"
}
cleanup_env() {
    echo $TOTAL_CORES_MASK | sudo tee /sys/bus/workqueue/devices/writeback/cpumask > /dev/null
    sudo cset shield --reset

    sudo sysctl vm.stat_interval=1
    sudo sysctl -w kernel.watchdog=1
    echo always | sudo tee /sys/kernel/mm/transparent_hugepage/enabled > /dev/null
    echo powersave | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor > /dev/null
    echo 1 | sudo tee /sys/bus/workqueue/devices/writeback/numa > /dev/null
    echo "[+] SHIELD REMOVED"

    echo 0 | sudo tee /sys/kernel/mm/hugepages/hugepages-1048576kB/nr_hugepages > /dev/null
    echo "[+] HUGEPAGES DELETED"

    sudo ip link set vmtap down
    sudo ip link delete vmtap
    echo "[+] NETWORK CLEANED"
}

WIN10='{"driver":"file","filename":"/home/jamnas/Downloads/win10.iso","node-name":"windows","auto-read-only":true,"discard":"unmap"}'
WIN10_FMT='{"node-name":"win10fmt","read-only":true,"driver":"raw","file":"windows"}'

VIODRV='{"driver":"file","filename":"/home/jamnas/Downloads/virtiowin10.iso","node-name":"viostor","auto-read-only":true,"discard":"unmap"}'
VIODRV_FMT='{"node-name":"viofmt","read-only":true,"driver":"raw","file":"viostor"}'

LVM='{"driver":"host_device","filename":"/dev/vg_main/os","aio":"native","node-name":"lvmopt","cache":{"direct":true,"no-flush":false},"auto-read-only":true,"discard":"unmap"}'
LVM_FMT='{"node-name":"lvmoptfmt","read-only":false,"discard":"unmap","cache":{"direct":true,"no-flush":false},"driver":"raw","file":"lvmopt"}'

RAW='{"driver":"file","filename":"/run/media/jamnas/e250f241-5eda-4ec6-ae56-74cb73388ddc/scratch.img","node-name":"rawimg","auto-read-only":true,"discard":"unmap"}'
RAW_FMT='{"node-name":"rawimgfmt","read-only":false,"driver":"raw","file":"rawimg"}'

ARGS="-uuid $(uuidgen) \
-machine pc-q35-6.0,accel=kvm,usb=off,vmport=off,dump-guest-core=off,kernel_irqchip=on \
-drive if=pflash,format=raw,unit=0,readonly=on,file=/usr/share/edk2-ovmf/x64/OVMF_CODE.fd \
-cpu host,hv-time,hv-relaxed,hv-vapic,hv-spinlocks=0x1fff,hv-vpindex,hv-runtime,hv-synic,hv-stimer,hv-vendor-id=GenuineIntel,hv-frequencies,hv-tlbflush,hv-ipi,kvm=off,hypervisor=false,-hypervisor \
-m ${NUM_HUGEPAGE}G \
-mem-path /dev/hugepages \
-mem-prealloc \
-overcommit mem-lock=off \
-smp 6,sockets=1,dies=1,cores=6,threads=1 \
-smbios type=0,vendor=$RANDOM,version=$RANDOM,date=$RANDOM,release=$RANDOM.$RANDOM,uefi=on \
-smbios type=1,manufacturer=$RANDOM,product=$RANDOM,version=$RANDOM,serial=$RANDOM,uuid=$(uuidgen),sku=$RANDOM,family=$RANDOM \
-smbios type=2,manufacturer=$RANDOM,product=$RANDOM,version=$RANDOM,serial=$RANDOM,asset=$RANDOM,location=$RANDOM \
-smbios type=3,manufacturer=$RANDOM,version=$RANDOM,serial=$RANDOM,asset=$RANDOM,sku=$RANDOM \
-smbios type=4,manufacturer=$RANDOM,sock_pfx=$RANDOM,version=$RANDOM,serial=$RANDOM,asset=$RANDOM,part=$RANDOM \
-smbios type=11,value=$RANDOM,value=$RANDOM,value=$RANDOM,value=$RANDOM \
-smbios type=17,manufacturer=$RANDOM,serial=$RANDOM,asset=$RANDOM,loc_pfx=$RANDOM,bank=$RANDOM,part=$RANDOM,speed=$RANDOM \
-device pcie-root-port,port=0x8,chassis=1,id=pci.1,bus=pcie.0,multifunction=on,addr=0x1 \
-device pcie-root-port,port=0x9,chassis=2,id=pci.2,bus=pcie.0,addr=0x1.0x1 \
-device pcie-root-port,port=0xa,chassis=3,id=pci.3,bus=pcie.0,addr=0x1.0x2 \
-device pcie-root-port,port=0xb,chassis=4,id=pci.4,bus=pcie.0,addr=0x1.0x3 \
-device pcie-root-port,port=0xc,chassis=5,id=pci.5,bus=pcie.0,addr=0x1.0x4 \
-device pcie-root-port,port=0xd,chassis=6,id=pci.6,bus=pcie.0,addr=0x1.0x5 \
-device pcie-root-port,port=0xe,chassis=7,id=pci.7,bus=pcie.0,addr=0x1.0x6 \
-device pcie-root-port,port=0xf,chassis=8,id=pci.8,bus=pcie.0,addr=0x1.0x7 \
-device qemu-xhci,p2=15,p3=15,id=usb,bus=pci.1,addr=0x0 \
-rtc base=localtime,clock=host,driftfix=none \
-global kvm-pit.lost_tick_policy=discard \
-display none \
-no-user-config \
-nodefaults \
-no-hpet \
-global ICH9-LPC.disable_s3=1 \
-global ICH9-LPC.disable_s4=1 \
-boot strict=on"

addGPU(){
    ARGS+=" -device vfio-pci,host=0000:01:00.0,id=hostdev1,bus=pci.3,multifunction=on,addr=0x0 \
    -device vfio-pci,host=0000:01:00.1,id=hostdev2,bus=pci.3,addr=0x0.0x1 \
    -device vfio-pci,host=0000:01:00.2,id=hostdev3,bus=pci.3,addr=0x0.0x2 \
    -device vfio-pci,host=0000:01:00.3,id=hostdev4,bus=pci.3,addr=0x0.0x3"
}
addNVME(){
    #Use a script to dynamically bind the samsung nvme ssd
    sudo /usr/bin/vfio-pci-bind.sh 0000:02:00.0 144d:a808
    ARGS+=" -device vfio-pci,host=0000:02:00.0,id=hostdev5,bus=pci.4,addr=0x0"
}
addNIC(){
    ARGS+=" -netdev tap,id=hostnet0,ifname=vmtap,script=no,downscript=no,vhost=on \
    -device e1000e,netdev=hostnet0,id=net0,mac=52:54:00:8f:89:ad,bus=pci.5,addr=0x0"
}
addLVM(){
    ARGS+=" -blockdev ${LVM}
    -blockdev ${LVM_FMT}
    -object iothread,id=io1 \
    -device virtio-blk-pci,bus=pci.2,addr=0x0,drive=lvmoptfmt,iothread=io1,id=virtio-disk0,write-cache=on"
}
addRAW(){
    ARGS+=" -blockdev ${RAW}
    -blockdev ${RAW_FMT}
    -device ide-hd,bus=ide.0,drive=rawimgfmt,id=maindiskraw,serial=$RANDOM"
}
addUSB(){
    ### USB DEVICES
    # NZXT USB
    # NZXT Smart Dev
    # Ducky Keyboard
    # Razer Mouse
    # Sound G6
    ARGS+=" -device usb-host,vendorid=0x1e71,productid=0x2007 \
    -device usb-host,vendorid=0x1e71,productid=0x2006 \
    -device usb-host,vendorid=0x05ac,productid=0x024f \
    -device usb-host,vendorid=0x1532,productid=0x007b \
    -device usb-host,vendorid=0x041e,productid=0x3256"
}
addWIN(){
    ARGS+=" -blockdev ${WIN10}
    -blockdev ${WIN10_FMT}
    -device ide-cd,bus=ide.1,drive=win10fmt,bootindex=1"
}
addVIO(){
    ARGS+=" -blockdev ${VIODRV}
    -blockdev ${VIODRV_FMT}
    -device ide-cd,bus=ide.2,drive=viofmt,id=viocd"
}

addGPU
addNIC
addUSB

if [[ $1 == "main" ]]; then
    echo "[+] PREPARING MAIN VM"
    addLVM
    addNVME
    # T5 External SSD
    ARGS+=" -device usb-host,vendorid=0x04e8,productid=0x61f5"
else
    echo "[+] PREPARING SCRATCH VM"
    addRAW
fi

if [[ $2 == "install" ]]; then
    echo "[+] ***ADDING INSTALL CDs"
    addVIO
    addWIN
fi

prepare_env

echo "[+] STARTING QEMU"
sudo cset shield --exec /usr/bin/qemu-system-x86_64 -- -$ARGS
echo "[+] EXITED QEMU"

cleanup_env
