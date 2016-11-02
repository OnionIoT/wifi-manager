#!/bin/sh

# function to connect to the first network in the match networks file
#   enables configured network that was in the scan
#   checks that connection was successful (wwan interface is up)
#       if not successful:
#           enable the AP network
#           disable all STA networks
# arguments:
#   arg1 - if set to force, will enable connect force option (wifi setup must be triggered)

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


# output files if necessary
TEST_OUT=/root/int_tmp_test.txt

_Print () {
    if [ $bVerbose == 1 ]; then
        echo $1 >&2
    fi
    if [ $bTest == 1 ]; then
        echo $1 >> tmp_test.txt
    fi
}

Usage () {
    _Print "WDB40: Omega Network Manager"
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


Get_id () {
    echo $1 | cut -d " " -f $2
}


# Find_index () {
    # network_str=$1
    # starting_index=$2
    
    # if ("$starting_index" == 0); then
    # count=0
    # else
    # count=$((starting_index+1))
    # fi
    
    # num_found=-1
    # while [ "$num_found" == -1 ]
    # do
        # ssid=$(echo $($UCI -q show wireless.@wifi-iface[$count].ssid) | grep -o "'.*'" | sed "s/'/\"/g")
        # _Print "SSID at index $count is $ssid"
        # if [ "$ssid" == "$network_str" ]; then
            # num_found=$count
        # fi
        # count=$((count+1))
    # done
    # echo $num_found
# }

# Use ubus command to look at the status of
# wireless device. The "up" parameter should be true
Wait () {
    local ret=$($UBUS call network.wireless status | grep up )
    echo $ret | grep -q "true" && res=found
    if [ "$res" == "found" ];
    then
        _Print "radio0 is up"
    else
        _Print "radio0 is not up"
    fi

    echo $res
}

Read () {
    iwinfo_scans=$1
    step=0
    ssid_str=""
    
    while [ "$ret" != "" ]
    do
        mode=$(echo $($UCI -q show wireless.@wifi-iface[$step].mode) | grep -o "'.*'")
        ret=$(echo $($UCI -q show wireless.@wifi-iface[$step].ssid) | grep -o "'.*'" | sed "s/'/\"/g")
        # res=$(Compare_str "$ret" "$ssid_str")
        if [ "$mode" == "'sta'" ]; then
            ssid_str="$ssid_str$ret "
        fi
        step=$((step + 1))
    done
    
    # SHOW CONFIGURED NETWORKS IF VERBOSE
    if [ $bVerbose == 1 ] ; then
        for word in $ssid_str
        do
            _Print $word
        done
    fi
    echo $ssid_str
}

Read_idx () {
    iwinfo_scans=$1
    step=0
    idx_str=""

    while [ "$ret" != "" ]
    do
        mode=$(echo $($UCI -q show wireless.@wifi-iface[$step].mode) | grep -o "'.*'")
        ret=$(echo $($UCI -q show wireless.@wifi-iface[$step].ssid) | grep -o "'.*'" | sed "s/'/\"/g")
        if [ "$mode" == "'sta'" ]; then
            idx_str="$idx_str$step "
        fi
        step=$((step + 1))
    done
    
    echo $idx_str
}



Scan () {
    ret_str=""
    local ret=$( $IWINFO radio0 scan | grep -o '".*"')

    # SHOW CONFIGURED NETWORKS IF VERBOSE
    if [ $bVerbose == 1 ] ; then
        for word in $ret
        do
            _Print $word
        done
    fi
            
    echo $ret
}

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


Connect () {
    net_index=$1
    step=0
    ret=$(echo $($UCI show -q wireless.@wifi-iface[$step].ssid) | grep -o "'.*'" | sed "s/'/\"/g")
    while [ "$ret" != "" ]
    do
        mode=$(echo $($UCI -q show wireless.@wifi-iface[$step].mode) | grep -o "'.*'")
        if [ "$mode" == 'ap' ]; then
            ap_step=$step
        fi
        ret=$(echo $($UCI -q show wireless.@wifi-iface[$step].ssid) | grep -o "'.*'" | sed "s/'/\"/g")
        if [ "$ret" != "" ]; then
            if [ "$mode" == \'sta\' ]; then
                res=$($UCI set wireless.@wifi-iface[$step].disabled=1)
                $($UCI commit)
            fi
        fi
        step=$((step + 1))
    done
    local ret=$($UCI set wireless.@wifi-iface[$net_index].disabled=0)
    local ret=$($UCI set wireless.@wifi-iface[$ap_step].disabled=0)
    local ret=$($UCI commit)
}


Check_connection() {
    local ret=$($UBUS call network.interface.wwan status | grep \"up\" | grep -o ' .*,')
    _Print " wwan network is set up... $ret"
    if [ $bTest == 1 ]; then
        echo  " $ret " >> $TEST_OUT
    fi
    echo $ret | grep -q "true" && res="found"
    if [ "$res" == "found" ]; then
        ret=0
    else
        ret=1
    fi
    echo $ret
}


Connection_loop () {
    configured_nets=$1
    iwinfo_scans=$2
    conf_net_num=$(Get_conf_net_num)   
    res=0
    count=1
    conn_net=""
    while [ "$res" == 0 ]
    do
        _Print " "
        _Print " "
        connection=$(Get_network "$configured_nets" $count)
        index=$(Get_id "$index_nets" $count)
        _Print " trying to connect to... $connection" 
        res=$(Compare_str "$connection" "$iwinfo_scans")
        if [ "$res" == 1 ]; then
            $(Connect "$index")
            _Print "Calling wifi interface..." 
            $($WIFI)
            sleep 10
            checked=$(Check_connection)
            if [ $checked == 1 ]; then
                res=0
                count=$((count+1))
            fi
        else
            _Print "$connection not found, trying other networks"
            count=$((count+1))
        fi
        if [ $count == $conf_net_num ]; then
           _Print "ran out of configured networks... no station available"
            count=$((count-1))
            $($UCI set wireless.@wifi-iface[$count].disabled=1)
            $($UCI commit)
            $($WIFI)
           break
        fi
    done
}

Boot_init () {
    net_index=$1
    step=0
    ret=$(echo $($UCI -q show wireless.@wifi-iface[$step].ssid) | grep -o "'.*'" | sed "s/'/\"/g")
    while [ "$ret" != "" ]
    do
        mode=$($UCI -q get wireless.@wifi-iface[$step].mode)
        if [ "$mode" == "ap" ]; then
            ap_step=$step
        fi
        ret=$(echo $($UCI -q show wireless.@wifi-iface[$step].ssid) | grep -o "'.*'" | sed "s/'/\"/g")
        if [ "$ret" != "" ]; then
            if [ "$mode" == "sta" ]; then
                res=$($UCI set wireless.@wifi-iface[$step].disabled=1)
                $($UCI commit)
            fi
        fi
        step=$((step + 1))
    done
    $($WIFI)
    sleep 10
}

##########################################################
##########################################################
Regular_Seq () {

    # CHECK THAT RADIO0 IS UP
    init=$($IWINFO wlan0 scan)
    ret=$(Wait)
    if [ "$ret" != "found" ]; then
        _Print "radio0 is not up... try again later"
        if [ $bTest == 1 ]; then
            echo "radio0 not up, aborting" >> $TEST_OUT
        fi
        exit
    fi


    # READ CONFIGURED NETWORKS
    _Print "Reading configured networks in station mode..."
    configured_nets=$(Read)
    index_nets=$(Read_idx)
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
    fi

    # CONNECT TO MATCHING NETWORKS
    _Print  ""  
    $(Connection_loop "$configured_nets" "$iwinfo_scans")

    _Print "Wifi manager finished"
}

Boot_Seq () {

    # CHECK THAT radio0 IS UP
    init=$($IWINFO wlan0 scan)
    ret=$(Wait)
    if [ "$ret" != "found" ]; then
        _Print "radio0 is not up... try again later with regular sequence"
        if [ $bTest == 1 ]; then
            echo "radio0 not up, aborting" >> $TEST_OUT
        fi
        exit
    fi    


    # INITIALIZE BY DISABLING ALL STATION NETWORKS AND RESET WIFI ADAPTER
    _Print ""
    _Print "initializing... disabling all station mode networks"
    $(Boot_init)
    

    # WAIT FOR radio0 TO BE UP
    ret=$(Wait)
    if [ "$ret" != "found" ]; then
        _Print "radio0 is not up... try again later with regular sequence"
        exit
    fi


    # READ CONFIGURED NETWORKS
    _Print "Reading configured networks in station mode..."
    configured_nets=$(Read)
    index_nets=$(Read_idx)
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
    fi


    # CONNECT TO MATCHED NETWORKS
    _Print ""
    $(Connection_loop "$ssid_str" "$iwinfo_scans" "idx_str")

    _Print "wifi manager finished"

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

if [ $bUsage == 1 ]; then
    Usage
    exit
fi

if [ $bBoot == 1 ]; then
    Boot_Seq
else
    Regular_Seq
fi

