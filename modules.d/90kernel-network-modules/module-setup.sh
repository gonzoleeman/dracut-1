#!/bin/bash

# called by dracut
check() {
    return 255
}

# called by dracut
depends() {
    return 0
}

running_in_qemu() {
    if type -P systemd-detect-virt >/dev/null 2>&1; then
        vm=$(systemd-detect-virt --vm 2>&1)
        (($? != 0)) && return 255
        [[ $vm = "qemu" ]] && return 0
        [[ $vm = "kvm" ]] && return 0
        [[ $vm = "bochs" ]] && return 0
    fi

    for i in /sys/class/dmi/id/*_vendor; do
        [[ -f $i ]] || continue
        read vendor < $i
        [[  "$vendor" == "QEMU" ]] && return 0
        [[  "$vendor" == "Bochs" ]] && return 0
    done

    return 255
}

# called by dracut
installkernel() {
    # Include wired net drivers, excluding wireless
    local _arch=$(uname -m)

    net_module_filter() {
        local _net_drivers='eth_type_trans|register_virtio_device|usbnet_open'
        local _unwanted_drivers='/(wireless|isdn|uwb|net/ethernet|net/phy|net/team)/'
        local _ret
        # subfunctions inherit following FDs
        local _merge=8 _side2=9
        function nmf1() {
            local _fname _fcont
            while read _fname; do
                [[ $_fname =~ $_unwanted_drivers ]] && continue
                case "$_fname" in
                    *.ko)    _fcont="$(cat      "$_fname" | tr -cd '[:print:]')" ;;
                    *.ko.gz) _fcont="$(gzip -dc "$_fname" | tr -cd '[:print:]')" ;;
                    *.ko.xz) _fcont="$(xz -dc   "$_fname" | tr -cd '[:print:]')" ;;
                esac
                [[   $_fcont =~ $_net_drivers
                && ! $_fcont =~ iw_handler_get_spy ]] \
                && echo "$_fname"
            done
            return 0
        }
        function rotor() {
            local _f1 _f2
            while read _f1; do
                echo "$_f1"
                if read _f2; then
                    echo "$_f2" 1>&${_side2}
                fi
            done | nmf1 1>&${_merge}
            return 0
        }
        # Use two parallel streams to filter alternating modules.
        set +x
        eval "( ( rotor ) ${_side2}>&1 | nmf1 ) ${_merge}>&1"
        [[ $debug ]] && set -x
        return 0
    }

    { find_kernel_modules_by_path drivers/net; if [ "$_arch" = "s390" -o "$_arch" = "s390x" ]; then find_kernel_modules_by_path drivers/s390/net; fi; } \
        | net_module_filter | instmods

    #instmods() will take care of hostonly
    instmods \
        =drivers/net/phy \
        =drivers/net/team \
        =drivers/net/ethernet \
        ecb arc4 bridge stp llc ipv6 bonding 8021q af_packet virtio_net xennet
    hostonly="" instmods iscsi_ibft crc32c iscsi_boot_sysfs

    if running_in_qemu; then
        hostonly='' instmods virtio_net e1000 8139cp pcnet32 e100 ne2k_pci
    else
        return 0
    fi
}

# called by dracut
install() {
    return 0
}

