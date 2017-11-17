#!/bin/sh

## library for abstracting UCI operations for WiFi connectivity

# includes
. /usr/share/libubox/jshn.sh

########################################
###     UCI Searching Functions
########################################

# find total number of configured wifi networks
# 	returns value via echo
_FindNumNetworks () {
	local count=0

	# find the first network
	local network=$(uci -q get wireless.\@wifi-config[$count])

	# loop through all configured networks
	while [ "$network" == "wifi-config" ]
	do
		# add to the count
		count=$(($count + 1))

		# continue the loop
		network=$(uci -q get wireless.\@wifi-config[$count])
	done

	# return the count number
	echo $count
}

# find a network's array number by the ssid
#	$1	- ssid to look for
#	returns value via echo
#		-1: 		if not found
#		all others: valid value found
_FindNetworkBySsid () {
	local id=-1
	local count=0
	local ssidKey="$1"

	# ensure argument is present
	if [ "$ssidKey" != "" ]; then

		# find the first network
		local network=$(uci -q get wireless.\@wifi-config[$count])

		# loop through all configured networks
		while [ "$network" == "wifi-config" ]
		do
			# find the ssid
			local ssid=$(uci -q get wireless.\@wifi-config[$count].ssid)

			if [ "$ssid" == "$ssidKey" ]; then
				id=$count
				break
			fi

			# continue the loop
			count=$(($count + 1))
			network=$(uci -q get wireless.\@wifi-config[$count])
		done
	fi

	# return the count number
	echo $id
}

# find a networks SSID from the id
#	returns value via echo
#	$1	- network id
_FindNetworkSsid () {
	if [ $bApNetwork == 1 ]; then
		local ssidName=$(uci -q get wireless.\@wifi-iface[$1].ssid)
		#local ssidName=$(uci -q get wireless.ap.ssid)	# confirm the fix
	else
		local ssidName=$(uci -q get wireless.\@wifi-config[$1].ssid)
	fi

	echo $ssidName
}

# return a specified option from a configured network from the id
#	returns value via echo
#	$1	- configured network id
#	$2	- the option to return
_FindConfigNetworkOption () {
	local option=$(uci -q get wireless.\@wifi-config[$1].$2)
	echo "$option"
}

# find the encryption type of a configured network from the id
#	returns value via echo
#	$1	- configured network id
_FindConfigNetworkEncryption () {
	echo "$(_FindConfigNetworkOption $1 'encryption')"
}

# find the key of a configured network from the id
#	returns value via echo
#	$1	- configured network id
_FindConfigNetworkKey () {
	local encryption="$(_FindConfigNetworkOption $1 'encryption')"
	local key=""
	case "$encryption" in
		psk2|psk)
			key="$($(_FindConfigNetworkOption $1 'key'))"
		;;
		wep)
			key="$($(_FindConfigNetworkOption $1 'key1'))"
		;;
		none|*)
			key="none"
		;;
	esac
	echo "$key"
}

########################################
###     UCI Interaction Functions
########################################

# commit changes to wireless config
UciCommitWireless () {
	uci commit wireless
}

# add a wireless.wifi-config section
UciAddWifiConfigSection () {
	uci add wireless wifi-config > /dev/null
}

# get a wireless.wifi-config section based on it's index number
#  input:
#	$1	- index
#  output:
#	if section found: 	"wifi-config"
#	no section found:	""
UciCheckWifiConfigIndex () {
	local index=$1
	local config=""

	if [ $index -ge 0 ]; then
		config=$(uci -q get wireless.\@wifi-config[$index])
	fi

	echo "$config"
}

# populate a wireless.wifi-config section
#  input:
#	$1	- index
#	$2	- ssid
#	$3	- encryption
#	$4	- password
UciPopulateWifiConfigSection () {
	local index=$1
	local ssid=$2
	local encryption=$3
	local password=$4

	# set the network key based on the encryption
	case "$encryption" in
		psk2|psk)
			uci set wireless.\@wifi-config[$index].key="$password"
		;;
		wep)
			uci set wireless.\@wifi-config[$index].key=1
			uci set wireless.\@wifi-config[$index].key1="$password"
		;;
		none|*)
			# add a 'NONE' value as a placeholder for open networks
			# the config parser in wifimanager expects non-empty values for existing configurations
			uci set wireless.\@wifi-config[$index].key='none'
		;;
	esac

	# set the ssid and encryption type
	uci set wireless.\@wifi-config[$index].ssid="$ssid"
	uci set wireless.\@wifi-config[$index].encryption="$encrypt"

	# commit the changes
	UciCommitWireless
	# TODO: ensure the above is required
}

# delete a wireless.wifi-config section
#  input:
#	$1	- index
#	$2	- ssid
UciDeleteWifiConfigSection () {
	local index=$1
	local ssid=$2

	# remove the section
	uci delete wireless.\@wifi-config[$index]
	# commit the changes
	UciCommitWireless
}

# reorder a wireless.wifi-config section
#  input:
#	$1	- index
#	$2	- ssid
#	$3	- desired order number in uci config
# 	$4 	- priority number in terms of other networks (optional)
UciReorderWifiConfigSection () {
	local index=$1
	local ssid=$2
	local priority=$3
	local humanPriority=$4

	# check that this wifi-config exists
	local config=$(UciCheckWifiConfigIndex $index)

	if [ "$config" != "" ]; then
		# print a message
		if [ "$humanPriority" != "" ]; then
			_Print "> Shifting '$ssid' priority to $humanPriority" "output"
		else
			_Print "> Shifting '$ssid' priority" "output"
		fi

		# perform the reorder
		uci reorder wireless.\@wifi-config[$index]=$priority

		# commit the changes
		UciCommitWireless
	fi
}

# output a JSON object of specified network
#	$1 	- network id
#	$2	- ssid
UciJsonOutputWifiNetworkInfo () {
	local id=$1
	local ssid=$2

	# check that this wifi-config exists
	local config=$(UciCheckWifiConfigIndex $id)

	if [ "$config" != "" ]; then
		# find the data
		local ssidRd=$(uci -q get wireless.\@wifi-config[$id].ssid)
		local modeRd=$(uci -q get wireless.\@wifi-config[$id].mode)
		local encrRd=$(uci -q get wireless.\@wifi-config[$id].encryption)
		local authRd=$(uci -q get wireless.\@wifi-config[$id].authentication)
		local passwordRd=$(uci -q get wireless.\@wifi-config[$id].key)

		if [ "$encrRd" == "wep" ]; then
			passwordRd=$(uci -q get wireless.\@wifi-config[$id].key$passwordRd)
		fi

		# create and populate object for this network
		_Print "$ssidRd" "ssid"
		_Print "$encrRd" "encryption"
		_Print "$passwordRd" "password"

	else
		$bError=1
	fi
}

# output a JSON list of all configured networks
UciJsonOutputAllNetworks () {
	local count=0

	# create the results array
	json_add_array results

	# find the first network
	local config=$(UciCheckWifiConfigIndex $count)

	# loop through all configured networks
	while [ "$config" == "wifi-config" ]
	do
		# create an object for this network
		json_add_object
		# populate the object
		UciJsonOutputWifiNetworkInfo $count
		# close the object
		json_close_object

		# continue the loop
		count=$(($count + 1))
		config=$(UciCheckWifiConfigIndex $count)
	done

	# finish the array
	json_close_array

	# print the json
	if [ $bJson == 0 ]; then
		json_dump | sed 's/,/,\n       /g' | sed 's/{ "/{\n\n        "/g' | sed 's/}/\n\}/g' | sed 's/\[/\[\n/g' | sed 's/\]/\n\]/g'
	fi
}


### wifi-iface ###

# check wifi-iface interface input
#	$1 	- 'ap' or 'sta'
UciCheckWifiIfaceInput () {
	local iface=$1
	local bIfaceError=0

	# check if iface is an allowed input
	if 	[ "$iface" != "ap" ] &&
		[ "$iface" != "sta" ];
	then
		bIfaceError=1
	fi

	echo $bIfaceError
}

# enable or disable a wifi iface
#	$1 	- 'ap' or 'sta'	(assuming that this has been checked)
#	$2	- enable (1) or disable (0)
UciSetWifiIfaceEnable () {
	local iface=$1
	local bEnable=$2

	# wifi-iface needs 'disabled' parameter - invert the enable
	local bDisabled=$((!$bEnable))

	# set the enable/disable
	uci set wireless.$iface.disabled="$bDisabled"

	# commit the changes
	UciCommitWireless
	# TODO: ensure the above is required
}

# populate a wireless.wifi-config section
#  input:
#	$1	- iface (ap|sta)
#	$2	- ssid
#	$3	- encryption
#	$4	- password
UciPopulateWifiIfaceSection () {
	local iface=$1
	local ssid=$2
	local encryption=$3
	local password=$4

	# check if iface is an allowed input
	local bInvalidInput=$(UciCheckWifiIfaceInput $iface)
	if 	[ $bInvalidInput -eq 0 ]; then
		# set the network key based on the encryption
		case "$encryption" in
			psk2|psk)
				uci set wireless.$iface.key="$password"
				#TODO: ensure this line works as intended
				uci -q delete wireless.$iface.key1
			;;
			wep)
				uci set wireless.$iface.key=1
				uci set wireless.$iface.key1="$password"
			;;
			none|*)
				# add a 'NONE' value as a placeholder for open networks
				# the config parser in wifimanager expects non-empty values for existing configurations
				uci set wireless.$iface.key='none'
				#TODO: ensure this line works as intended
				uci -q delete wireless.$iface.key1
			;;
		esac

		# set the ssid and encryption type
		uci set wireless.$iface.ssid="$ssid"
		uci set wireless.$iface.encryption="$encryption"

		# commit the changes
		UciCommitWireless
	fi
}
