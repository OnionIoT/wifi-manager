#!/bin/sh

#global variables: wifi libraries
UCI="/sbin/uci"
UBUS="/bin/ubus"
IWINFO="/usr/bin/iwinfo"
WIFI="/sbin/wifi"
WIFISETUP="/rom/usr/bin/wifisetup"

# global variable: internal
bUsage=0
bBoot=0
bVerbose=0


# file destinations
OUTFILE=/root/test_lim/wifi_manager/int_tmp_test.txt
OUTPUT_FILE=/root/test_lim/wifi_manager/result.txt
SCAN_FILE=/root/test_lim/wifi_manager/scannable_networks

_Print () {
    if [ $bVerbose == 1 ]; then
        echo $1 >&2
    fi
}

_Usage () {
    _Print "Test automation script for wifi manager"
}

# helper functions

Connection_res () {
    network=$1
    res=$(grep "$network" "$OUTFILE" | grep true)
    if [ "$res" != "" ]; then
        echo 1
    else
        echo 0
    fi

}

Set_sta_network_1 () {
    sta_network_to_setup=$1
    _Print "network to connect to is $sta_network_to_setup"
    count=0
    mode=$($UCI show wireless)
    while [ "$mode" != "" ];
    do
        mode=$($UCI -q get wireless.@wifi-iface[$count].mode)
        ssid=$($UCI -q get wireless.@wifi-iface[$count].ssid)
        _Print "$ssid $mode"
        if [ "$ssid" != "$sta_network_to_setup" ]; then
            if [ "$mode" == "sta" ]; then
                _Print "deleting $ssid from configured networks"
                nothing=$($WIFISETUP remove -ssid "$ssid")
                count=$((count-1))
            fi
        fi
        count=$((count+1))

    done
}

Delete_all_sta_nets () {
    _Print "Deleting all station networks"
    count=0
    mode=$($UCI show wireless)
    while [ "$mode" != "" ];
    do
        mode=$($UCI -q get wireless.@wifi-iface[$count].mode)
        ssid=$($UCI -q get wireless.@wifi-iface[$count].ssid)
        _Print "$ssid $mode"
        if [ "$mode" == "sta" ]; then
            _Print "deleting $ssid from configured networks"
            nothing=$($WIFISETUP remove -ssid "$ssid")
            count=$((count-1))
        fi
        count=$((count+1))
    done
}

Delete_conf_nets () {
    num_net=$1
    while [ $num_net != 0 ];
    do
        nothing=$($WIFISETUP remove -ssid "dummy_net$num_net")
        num_net=$((num_net-1))
    done
    
    scans=$(cat $SCAN_FILE)
    for word in $scans
    do
        nothing=$($WIFISETUP remove -ssid "$word")
    done
}

Disable_ap () {
    _Print "Disabling Omega access point"
    mode=$($UCI show wireless)
    count=0
    while [ "$mode" != "" ];
    do
        mode=$($UCI -q get wireless.@wifi-iface[$count].mode)
        if [ "$mode" == "ap" ]; then
            nothing=$($UCI -q set wireless.@wifi-iface[$count].disabled=1)
            nothing=$($UCI commit)
            nothing=$($WIFI)
            sleep 8
            break
        fi
        count=$((count+1))
    done
}

Enable_ap () {
    _Print "Enabling Omega access point"
    mode=$($UCI show wireless)
    count=0
    while [ "$mode" != "" ];
    do
        mode=$($UCI -q get wireless.@wifi-iface[$count].mode)
        if [ "$mode" == "ap" ]; then
            nothing=$($UCI -q set wireless.@wifi-iface[$count].disabled=0)
            nothing=$($UCI commit)
            nothing=$($WIFI)
            sleep 8
            break
        fi
        count=$((count+1))
    done
}

Check_ap_running () {
    _Print "Checking whether access point is up"
    check=$($UBUS call network.wireless status | grep mode | grep ap)
    if [ "$check" == "" ]; then
        result=1
    else
        result=0
    fi
    echo $result    
}

Disable_radio0 () {
    _Print "Disabling radio0 network"
    nothing=$($UCI -q set wireless.radio0.disabled=1)
    nothing=$($UCI commit)
    nothing=$($WIFI)
    sleep 8
}

Enable_radio0 () {
    _Print "Enabling radio0 network"
    nothing=$($UCI -q set wireless.radio0.disabled=0)
    nothing=$($UCI commit)
    nothing=$($WIFI)
    sleep 10
}

Check_radio0_running () {
    _Print "Checking whether radio0 device is up"
    check=$($UBUS call network.wireless status | grep up)
    if [ "$check" == "" ]; then
        result=1
    else
        result=0
    fi
    echo $result
}


Test_0sta () {
    opt=$1

    _Print "Running 0 configured sta network test"
    mode=$($UCI show wireless)
    count=0
    while [ "$mode" != "" ];
    do
        mode=$($UCI -q get wireless.@wifi-iface[$count].mode)
        ssid=$($UCI -q get wireless.@wifi-iface[$count].ssid)
        if [ "$mode" != "ap" ]; then
            if [ "$ssid" != "" ]; then
                _Print "deleting $ssid from configured networks"
                nothing=$($WIFISETUP remove -ssid "$ssid")
                count=$((count-1))
            fi
        fi
        count=$((count+1))
    done
    if [ $opt == 0 ]; then
        $(sh test_wifimanager.sh -t)
    else
        $(sh test_wifimanager.sh -t -boot)
    fi

    res=$(grep "no configured networks" $OUTFILE)
    if [ "$res" == "" ]; then
        _Print "0 network test failed! check output log"
        echo 1
    else
        _Print "0 network test passed"
        echo 0
    fi
    rm $OUTFILE
}

Test_1sta () {
    password_test=$1
    opt=$2
    _Print "Running single configured sta network test"

    test_net=OnionWiFi
    if [ $password_test == 0 ]; then
        nothing=$($WIFISETUP add -ssid "$test_net" -encr psk2 -password onioneer)
    else
        nothing=$($WIFISETUP add -ssid "$test_net" -encr psk2 -password onionee)
    fi

    nothing=$(Set_sta_network_1 "$test_net")
    if [ $opt == 0 ]; then
        $(sh test_wifimanager.sh -t)
    else
        $(sh test_wifimanager.sh -t -boot)
    fi

    connection_check=$(Connection_res "$test_net")
    if [ $connection_check == 1 ]; then
        if [ $password_test == 0 ]; then
            _Print "\"$test_net\" connected, as expected"
            result=0
        else
            _Print "\"$test_net\" connected while password incorrect, unexpected behaviour detected"
            result=1
        fi
    else
        if [ $password_test == 1 ]; then
            _Print "\"$test_net\" not connected, as expected"
            result=0
        else
            _Print "\"$test_net\" not connected while password correct, unexpected behaviour detected"
            result=1
        fi
    fi
    rm $OUTFILE    
    echo $result
}

Test_xsta () {
    _Print "Running multiple configured sta network test"
    dummy_num=$1
    priority_num=$2
    opt=$3
    scans=$(cat $SCAN_FILE)
    _Print "$scans"
    $(Delete_all_sta_nets)
    while [ $dummy_num != 0 ]
    do
        _Print "adding dummy network dummy_net$dummy_num"
        nothing=$($WIFISETUP add -ssid "dummy_net$dummy_num")
        dummy_num=$((dummy_num-1))
    done
    for word in $scans
    do
        _Print "adding $word station network for testing"
        nothing=$($WIFISETUP add -ssid $word)
    done
    _Print "adding \"OnionWiFi\" station network for testing"
    nothing=$($WIFISETUP add -ssid "OnionWiFi" -encr psk2 -password onioneer)

    if [ $opt == 0 ]; then
        nothing=$(sh test_wifimanager.sh -t)
    else
        nothing=$(sh test_wifimanager.sh -t -boot)
    fi

    connection_check=$(Connection_res "OnionWiFi")
    if [ $connection_check == 1 ]; then
        _Print "\"OnionWiFi\" connected, as expected"
        result=0
    else
        _Print "\"OnionWiFi\" not connected, unexpected behaviour detected"
        result=1
    fi

    res=$(cat $OUTFILE)
    _Print "$res"

    for word in $scans
    do    
        res=$(cat int_tmp_test.txt | grep $word | grep false)
        if [ "$res" == "" ]; then
            _Print "did not attempt to connect to $word, unexpected behaviour detected"
            _Print "check whether $word is scannable via iwinfo wlan0 scan"
            result=1
        fi
    done

    rm $OUTFILE
    echo $result    
}

Run_radio0_test () {
    opt=$1
    nothing=$(Disable_radio0)
    if [ $opt == 0 ]; then
        $(sh test_wifimanager.sh -t)
    else
        $(sh test_wifimanager.sh -t -boot)
    fi
    res=$(grep "radio0 not up, aborting" $OUTFILE)
    if [ "$res" == "" ]; then
        echo "disabled radio0 test failed! check output log" >&2
        if [ $opt == 0 ]; then
            echo "REGULAR SEQ - disabled radio0 test failed" >> $OUTPUT_FILE
        else
            echo "BOOT SEQ - disabled radio0 test failed" >> $OUTPUT_FILE
        fi
    else
        echo "disabled radio0 test passed" >&2
        if [ $opt == 0 ]; then
            echo "REGULAR SEQ - disabled radio0 test passed" >> $OUTPUT_FILE
        else
            echo "BOOT SEQ - disabled radio0 test passed" >> $OUTPUT_FILE
        fi
    fi
    rm $OUTFILE
    nothing=$(Enable_radio0)

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
        *)
            echo "ERROR: Invalid Argument: $1"
            shift
            exit
        ;;
    esac
done

if [ $bUsage == 1 ]; then
    _Usage
    exit
fi

if [ -e "$OUTFILE" ]; then
    _Print "removing test output file"
    rm $OUTFILE
fi

if [ -e "$OUTPUT_FILE" ]; then
    _Print "removing result output file"
    rm $OUTPUT_FILE
fi


##########################
# MAIN CODE              #
##########################


Run_test () {
    echo "REGULAR SEQUENCE TESTING" >&2
##############################################
# disabled radio0 test
    nothing=$(Run_radio0_test 0)


###############################################
# 0 configured network test
    res0=$(Test_0sta 0)
    if [ $res0 == 0 ]; then
        echo "" >&2
        echo "0 configured network test passed" >&2
        echo "REGULAR SEQ - 0 configured network test passed" >> $OUTPUT_FILE
        echo "" >&2
    else
        echo "" >&2
        echo "0 configured network test failed" >&2
        echo "REGULAR SEQ - 0 configured network test failed" >> $OUTPUT_FILE
        echo "" >&2
    fi


###############################################
# password test
    res1_0=$(Test_1sta 0 0)
    res1_1=$(Test_1sta 1 0)
    if [ $res1_0 == 0 ] && [ $res1_1 == 0 ]; then
        echo "" >&2
        echo "password test passed" >&2
        echo "REGULAR SEQ - password test passed" >> $OUTPUT_FILE
        echo "" >&2
    else
        echo "" >&2
        echo "password test failed" >&2
        echo "REGULAR SEQ - password test failed" >> $OUTPUT_FILE
        echo "" >&2
    fi


################################################
# priority test
    resx=$(Test_xsta 5 2 0)
    if [ $resx == 0 ]; then
        echo "" >&2
        echo "network priority test passed" >&2
        echo "REGULAR SEQ - network priority test passed" >> $OUTPUT_FILE
        echo "" >&2
    else
        echo "" >&2
        echo "network priority test failed" >&2
        echo "REGULAR SEQ - network priority test failed" >> $OUTPUT_FILE
        echo "" >&2
    fi


##############################################
# check AP test
    check=$(Check_ap_running 0)
    if [ $check == 0 ]; then
        echo "" >&2
        echo "check AP test passed" >&2
        echo "REGULAR SEQ - check AP test passed" >> $OUTPUT_FILE
        echo "" >&2
    else
        echo "" >&2
        echo "check AP test failed" >&2
        echo "REGULAR SEQ - check AP test failed" >> $OUTPUT_FILE
        echo "" >&2
    fi

#####################################################
#####################################################


    echo "BOOT SEQUENCE TESTING" >&2
##############################################
# disabled radio0 test
    nothing=$(Run_radio0_test 1)


###############################################
# 0 configured network test
    res0=$(Test_0sta 1)
    if [ $res0 == 0 ]; then
        echo "" >&2
        echo "0 configured network test passed" >&2
        echo "BOOT SEQ - 0 configured network test passed" >> $OUTPUT_FILE
        echo "" >&2
    else
        echo "" >&2
        echo "0 configured network test failed" >&2
        echo "BOOT SEQ - 0 configured network test failed" >> $OUTPUT_FILE
        echo "" >&2
    fi


###############################################
# password test
    res1_0=$(Test_1sta 0 1)
    res1_1=$(Test_1sta 1 1)
    if [ $res1_0 == 0 ] && [ $res1_1 == 0 ]; then
        echo "" >&2
        echo "password test passed" >&2
        echo "BOOT SEQ - password test passed" >> $OUTPUT_FILE
        echo "" >&2
    else
        echo "" >&2
        echo "password test failed" >&2
        echo "BOOT SEQ - password test failed" >> $OUTPUT_FILE
        echo "" >&2
    fi


################################################
# priority test
resx=$(Test_xsta 5 2 1)
    if [ $resx == 0 ]; then
        echo "" >&2
        echo "network priority test passed" >&2
        echo "BOOT SEQ - network priority test passed" >> $OUTPUT_FILE
        echo "" >&2
    else
        echo "" >&2
        echo "network priority test failed" >&2
        echo "BOOT SEQ - network priority test failed" >> $OUTPUT_FILE
       echo "" >&2
    fi


##############################################
# check AP test
    check=$(Check_ap_running 0)
    if [ $check == 0 ]; then
        echo "" >&2
        echo "check AP test passed" >&2
        echo "BOOT SEQ - check AP test passed" >&2
        echo "" >&2
    else
        echo "" >&2
        echo "check AP test failed" >&2
        echo "BOOT SEQ - check AP test failed" >&2
        echo "" >&2
    fi
}


$(Disable_ap)
echo "Disabled AP network tests" >> $OUTPUT_FILE
$(Run_test)

$(Enable_ap)
echo "Enabled AP network tests" >> $OUTPUT_FILE
$(Run_test)

$(Delete_conf_nets 5)

echo "Testing Finished" >&2


