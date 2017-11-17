#!/bin/sh

# script to connect to the first network in the match networks file
#   enables configured network that was in the scan
#   checks that connection was successful (wwan interface is up)
#       if not successful:
#           enable the AP network
#           disable all STA networks
# arguments:
#   arg1 - if set to force, will enable connect force option (wifi setup must be triggered)

# includes
. /usr/lib/wifilib

# global variables: wifi libraries
UCI="/sbin/uci"
UBUS="/bin/ubus"
IWINFO="/usr/bin/iwinfo"
WIFI="/sbin/wifi"

# global variable: internal
bUsage=0
bBoot=0
bVerbose=0
bTest=0

# global variables: configuration option lists
configured_nets=""
configured_encrypt=""
configured_key=""

# global variable: default encryption for old configs
DEFAULTENCRYPTION='AES'

# output files if necessary
TEST_OUT=/root/int_tmp_test.txt
TEST_OUT_TMP=/tmp/wifimanager_log.txt

_Print () {
    if [ $bVerbose == 1 ]; then
        echo $1 >&2
    fi
    if [ $bTest == 1 ]; then
        echo $1 >> $TEST_OUT_TMP
    fi
}

Usage () {
    _Print "Omega2 Network Manager"
    _Print " Attempts to automatically connect to any configured networks"
    _Print ""
    _Print "This will always run at boot"
    _Print ""
    _Print "Afterwards, it can be run manually if the networks around you have changed"
    _Print " Run with no arguments and the following will be performed:"
    _Print " - Scan for wifi networks"
    _Print " - Check available networks from scan against configured networks"
    _Print " - Attempt to connect to any available configured networks"
    _Print " - If the connection is not successful:"
    _Print "   - Try to connect to any other available configured networks"
    _Print "   - If there are no other available configured networks, ensures the Omega's AP is enabled"
    _Print ""
    _Print "Use 'wifisetup' to configure your network settings"
    _Print ""
}
# Some helper functions
Compare_str () {
    substring=$1
    string=$2

    if [ "${string/$substring}" = "$string" ]; then
        echo 0
    else
        echo 1
    fi
}

Get_network () {
    ith_net=$2
    net_list=$1

    nth_quote=$((ith_net + ith_net - 1))
    step=0
    while [ "$nth_quote" != 0 ]
    do
        if [ "${net_list:$step:1}" == '"' ]; then
            nth_quote=$((nth_quote - 1))
        fi
        step=$((step+1))
    done
    step2=$step
    step3=1
    while [ "${net_list:$step2:1}" != '"' ]
    do
        step2=$((step2 + 1))
        step3=$((step3 + 1))
    done
    step=$((step-1))
    echo ${net_list:$step:$((step3+1))}
}


# Use ubus command to look at the status of
# wireless device. The "up" parameter should be true
Wait () {
    waitcount=0
    waitflag=0
    while [ "$waitcount" -le 20 ] &&
        [ "$waitflag" == 0 ]; do
        local ret=$($UBUS call network.device status '{"name":"ra0"}' | grep up )
        echo $ret | grep -q "true" && res=found
        if [ "$res" == "found" ];
        then
            _Print "radio0 is up"
            waitflag=1
        fi
        sleep 1
        waitcount=$((waitcount + 1))
    done
    echo $res
}

# Read a particular uci configuration option
# return nothing if it does not exist
# meant for building a space-separated list of quote-enclosed values
# eg. if wireless. \"AES\"
Read_option () {
    _Print "Entering Read_option"
    local option=$1
    _Print "option: $option"
    echo $($UCI -q show $option | grep -o "'.*'" | sed "s/'/\"/g")
}

Check_wifi_entry () {
    _Print "Entering Check_wifi_entry"
    local entry_number=$1
    local entry_exists=0
    local entry_type=$($UCI -q get wireless.@wifi-config[$entry_number])

    if [ "$entry_type" == "wifi-config" ]
    then
        entry_exists=1
    fi

    echo $entry_exists
}

# Read all network options
Read_network_options () {
    _Print "Entering Read_network_options"
    # modify several variables at once
    configured_nets=$1
    configured_encrypt=$2
    configured_key=$3

    entry_number=0

    # variables to store the config options at each step
    local next_ssid=""
    local next_encrypt=""
    local next_key=""

    local option_base_name="wireless.@wifi-config"

    local entry_status="nonempty"
    while [ "$entry_status" != 0 ]
    do
        # check if the section exists, returns 1 or 0
        entry_status=$(Check_wifi_entry $entry_number)
        if [ "$entry_status" == 1 ]
        then
            # read the options
            # if they exist, they will be enclosed in quotation marks
            # if they do not exist, they will be blank
            next_ssid=$(Read_option "$option_base_name[$entry_number].ssid")
            next_encrypt=$(Read_option "$option_base_name[$entry_number].encryption")
            next_key=$(Read_option "$option_base_name[$entry_number].key")

            # add to the option lists
            configured_nets="$configured_nets$next_ssid "
            configured_encrypt="$configured_encrypt$next_encrypt "
            configured_key="$configured_key$next_key "

            # increment entry number and do it again
            entry_number=$((entry_number + 1))
        fi
    done
}

#TODO: update so that iwpriv content is stored in a variable
#TODO: OVERHAUL #2: use ubus onion wifi-scan to grab a json array of available networks
Scan () {
    ret_str=""
    line=1
    var=$(iwpriv ra0 get_site_survey | grep '^[0-9]' | sed -n "${line}p")
    while [ "$var" != "" ]
    do
        var=$(iwpriv ra0 get_site_survey | grep '^[0-9]' | sed -n "${line}p")
        if [ "$var" != "" ]; then
            local ret="$ret"\""$(echo "${var:4:32}" | xargs)"\"" "
        fi
        line=$((line + 1))
    done
    # SHOW CONFIGURED NETWORKS IF VERBOSE
    if [ $bVerbose == 1 ] ; then
        for word in $ret
        do
            _Print $word
        done
    fi

    echo $ret
}

#TODO: replace this and all uses with _FindNumNetworks function from wifi-lib
Get_conf_net_num () {
    nums=$($UCI show wireless | grep -o '\[.*\]')
    count=0
    res=1
    while [ $res == 1 ]
    do
        res=0
        echo $nums | grep -q $count && res=1
        count=$((count+1))
    done
    echo $((count-1))
}

# set ApCli options for connecting to wifi
Connect () {
    local net_ssid=$(echo "$1" | sed -e 's/^"//' -e 's/"$//')
    local net_encrypt=$(echo "$2" | sed -e 's/^"//' -e 's/"$//')
    local net_key=$(echo "$3" | sed -e 's/^"//' -e 's/"$//')

    # populate the STA wireless.wifi-config
    UciPopulateWifiIfaceSection "sta" "$net_ssid" "$net_encrypt" "$net_key"

    # enable the network
    UciSetWifiIfaceEnable "sta" 1
}


Check_connection() {
    checkcount=0
    checkflag=0
    while [ "$checkcount" -le 10 ] &&
        [ "$checkflag" == 0 ]; do
        local ret=$($UBUS call network.interface.wwan status | grep \"up\" | grep -o ' .*,')
        _Print " wwan network is set up... $ret"
        if [ $bTest == 1 ]; then
            echo  " $ret " >> $TEST_OUT
        fi
        #TODO: check this line
        echo $ret | grep -q "true" && res="found"
        if [ "$res" == "found" ]; then
            ret=0
            checkflag=1
        else
            ret=1
        fi
        sleep 1
        checkcount=$((checkcount + 1))
    done
    echo $ret
}


Connection_loop () {
    _Print "Entering Connection_loop"
    # TODO: OVERHAUL: no need to pass configured_nets, configured_encrypt, configured_key
    configured_nets=$1
    configured_encrypt=$2
    configured_key=$3
    iwinfo_scans=$4
    conf_net_num=$(Get_conf_net_num)
    res=0
    count=1
    conn_net=""

    _Print "configured_nets: $configured_nets"
    _Print "configured_key: $configured_key"
    _Print "configured_encrypt: $configured_encrypt"

    while [ "$res" == 0 ]
    do
        _Print " "
        _Print " "
        _Print "Current Count: $count"
        _Print "Number of configured nets: $conf_net_num"
        # ssid
        _Print "Reading ssid."
        # TODO: OVERHAUL: replace this with _FindNetworkSsid from wifi-lib
        connection=$(Get_network "$configured_nets" $count)
        _Print "ssid: $connection"

        _Print " trying to connect to... $connection"
        _Print " iwinfo_scans: $iwinfo_scans" # debug
        res=$(Compare_str "$connection" "$iwinfo_scans")

        # check if current configured network is in the list of available networks
        if [ "$res" == 1 ]; then
            # collect the remaining info
            # password
            _Print "Reading key."
            # TODO: OVERHAUL: replace this with _FindConfigNetworkKey from wifi-lib
            key=$(Get_network "$configured_key" $count)
            _Print "key: $key"
            # encryption type
            _Print "Reading encryption type."
            # TODO: OVERHAUL: replace this with _FindConfigNetworkEncryption from wifi-lib
            encryption=$(Get_network "$configured_encrypt" $count)
            _Print "encryption: $encryption"

            # set the wireless config to connect to this network
            $(Connect "$connection" "$encryption" "$key")

            # bring the interface down, run the system wifi script, and bring the interface back up
            local down=$($UBUS call network.interface.wwan down)
            $($WIFI &> /dev/null)
            sleep 10
            local up=$($UBUS call network.interface.wwan up)
            sleep 5

            # check if successfully connected to the network
            checked=$(Check_connection)
            if [ $checked == 1 ]; then
                # exit the loop
                res=0
                count=$((count+1))
            fi
        else
            _Print "$connection not found, trying other networks"
            count=$((count+1))
        fi

        # check if we've run out of configured networks
        if [ "$count" -gt "$conf_net_num" ]; then
           _Print "ran out of configured networks... no station available"
            UciSetWifiIfaceEnable "sta" 0
            $($WIFI)
           break
        fi
    done
}

##########################################################
##########################################################

# Main network connection sequence
# formerly Boot_Seq
# This and Regular_Seq were functionally equivalent save for the iwpriv set SiteSurvey line, so they've been combined
Main_Seq () {
    # _Print "Entering Main_Seq"
    # wait until ra0 is up
    # CHECK THAT radio0 IS UP
    ret=$(Wait)
    if [ "$ret" != "found" ]; then
        _Print "radio0 is not up... try again later"
        if [ $bTest == 1 ]; then
            echo "radio0 not up, aborting" >> $TEST_OUT
        fi
        exit
    fi

    # read stored network options
    # TODO: OVERHAUL: change this to:
    #   * use the _FindNumNetworks function from wifi-lib
    #   * if the result is 0, then exit
    _Print "Reading configured network options."
    Read_network_options "$configured_nets" "$configured_encrypt" "$configured_key"

    if [ "$configured_nets" == "" ]; then
        _Print "no configured station networks... aborting"
        if [ "$bTest" == 1 ]; then
            echo "no configured networks" >> $TEST_OUT
        fi
        exit
    fi


    # SCAN NEARBY NETWORKS
    _Print ""
    _Print "Scanning nearby networks..."
    iwinfo_scans=$(Scan)
    if [ "$iwinfo_scans" == "" ]; then
        _Print "no nearby networks... aborting"
        if [ "$bTest" == 1 ]; then
            echo "no scanned networks" >> $TEST_OUT
        fi
        exit
    #TODO: OVERHAUL #2: add an else to init the json function with the scan results
    fi

    # CONNECT TO MATCHED NETWORKS
    _Print ""
    $(Connection_loop "$configured_nets" "$configured_encrypt" "$configured_key" "$iwinfo_scans")


    exit
}

# parse arguments
while [ "$1" != "" ]
do
    case "$1" in
        -boot|boot)
            bBoot=1
            shift
        ;;
        -v|--v|verbose|-verbose|--verbose)
            bVerbose=1
            shift
        ;;
        -h|--h|help|-help|--help)
            bVerbose=1
            bUsage=1
            shift
        ;;
        -t|--t|test|-test|--test)
            bTest=1
            shift
        ;;
        *)
            echo "ERROR: Invalid Argument: $1"
            shift
            exit
        ;;
    esac
done

# print usage and exit
if [ $bUsage == 1 ]; then
    Usage
    exit
fi


if [ $bBoot != 1 ]; then
    # start scanning for nearby wifi networks (only when not run at boot)
    init=$(iwpriv ra0 set SiteSurvey=1)
fi

# run the program
Main_Seq
