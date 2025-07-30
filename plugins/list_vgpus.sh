#!/usr/bin/env bash
# This script will list virtual GPUs on a "Linux with KVM Hypervisor that Uses a Vendor-Specific VFIO Framework",
# as nVidia calls them.
# It has been tested only under Ubuntu 24.04 with nVidia GRID.
# Other vendors might work provided that they use a similar structure
# 
# Guillermo Miranda, November 2024

# Read lines into an array. See https://stackoverflow.com/a/11426834
IFS=$'\n' pcidevices=( $(lspci -Dnn) )

is_vendor_dev() {
	local dev=$1
	local vendor=$2
	find /sys/bus/pci/devices/$dev/ -maxdepth 1 -type d -name "$vendor" >/dev/null
	return $?
}

# Checks if a virtual gpu is enabled
# 0 meaning not enabled, 1 enabled
# An optional type can be passed to return only vgpus of that ype
is_vgpu_enabled() {
	local dev=$1
	local vendor=$2
	local filter_type=$3

	# Check if the current_vgpu_type file exists
	local vgpu_type_path="/sys/bus/pci/devices/$dev/$vendor/current_vgpu_type"
	if [ ! -f $vgpu_type_path ]; then
		# early return meaning vgpu not enabled
		return 0
	fi
	
	# Ensure that the vGPU has a selected type
	# And if a filter is active, is only of that type
	local vgpu_type=$(cat $vgpu_type_path)
	if [ "$vgpu_type" == 0 ] || ([ ! -z "$filter_type" ] && [ "$vgpu_type" != "$filter_type" ] ); then
                # vgpu not enabled
                return 0
        fi

	# I don't know how to return the type
	return 1
}

main() {
	local vendor=$1
	local filter_vgpu_type=$2

	for line in "${pcidevices[@]}"; do
		local dev=$(echo "$line"| cut -d' ' -f1)

		# If the vendor subfolder is not present, skip it
		is_vendor_dev "$dev" "$vendor"
		if [ $? -gt 0 ];  then
			continue
		fi
		is_vgpu_enabled "$dev" "$vendor" "$filter_vgpu_type"
		local gpu_enabled=$?
		# If this vgpu is enabled and is of the selected type, print the full line
		if [ $gpu_enabled -gt 0 ]; then
			echo $line
		fi
	done
}

main $@
