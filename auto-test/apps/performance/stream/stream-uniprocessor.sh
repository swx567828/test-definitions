#!/bin/bash

. ../../../../utils/sh-test-lib
. ../../../../utils/sys_info.sh
OUTPUT="$(pwd)/output"
RESULT_FILE="${OUTPUT}/result.txt"
TEST_LOG="${OUTPUT}/stream-output.txt"

create_out_dir "${OUTPUT}"

# Run Test.

# centos has not per install bc command
pkgs="bc wget gcc gcc-c++"
install_deps "$pkgs"



# get system argment
memCountKB=`cat /proc/meminfo  |grep MemTotal | cut -d ":" -f2|tr -d "a-z" | awk {'print $1'}`
memCountGB=`echo "scale=2;$memCountKB / 1024 / 1024" | bc `
memCountGB=`echo $((${memCountGB//.*/+1}))`

# count chips count
currChipsNum=`dmidecode -t memory | grep  -A5 Memory | grep Size | grep -v No| cut -d : -f2|tr -d A-Z|wc -l`
chipType=`dmidecode -t memory | grep "Type: DD" | grep -v Unknown| head -n 1 | awk {'print $2'}`
chipManufacturer=`dmidecode -t memory | grep Manufacturer | grep -v NO|head -n 1| awk {'print $2'}`
chipSpeed=`dmidecode -t memory | grep "Speed" | grep -v Unknown|grep -v Clock|awk {'print $2'}|head -n 1`

biosVersion=`dmidecode -t bios|grep Version|cut -d : -f 2`
biosDate=`dmidecode -t bios|grep "Release Date"|cut -d : -f 2`

declare -A speedMap=()
declare -A stdevMap=()

speedMap["Copy"]=98103.49
speedMap["Scale"]=98127.90
speedMap["Add"]=99356.54
speedMap["Triad"]=99463.96

stdevMap["Copy"]=0.62
stdevMap["Scale"]=0.74
stdevMap["Add"]=0.27
stdevMap["Triad"]=0.15

echo "-----------------------------------------------------------------"
echo "Memory_Count= $memCountGB, Chips_Count= $currChipsNum" | tee $TEST_LOG
echo "chipType=$chipType , chipManufacturer=$chipManufacturer , chipSpeed=$chipSpeed" | tee $TEST_LOG
echo "biosVersion=$biosVersion , biosDate=$biosDate" | tee $TEST_LOG
echo ""

#下载Stream benchmark源码
#wget http://www.cs.virginia.edu/stream/FTP/Code/stream.c | tee $TEST_LOG
wget -c ${ci_http_addr}/test_dependents/stream.c | tee $TEST_LOG
#编译(STREAM_ARRAY_SIZE:测试数据集的大小,为100M,NTIME:kernel执行的次数,OFFSET:数组的偏移量,通常设置为靠近2的n次方
gcc -O -fopenmp -DSTREAM_ARRAY_SIZE=100000000 -DNTIME=12 -DOFFSET=1022 stream.c -o stream_omp_exe
print_info $? stream-build | tee $TEST_LOG

#运行
./stream_omp_exe | tee $TEST_LOG
print_info $? stream-run


for test in Copy Scale Add Triad; do
    ret=`grep "^${test}" "${TEST_LOG}" \
        | awk -v test="${test}" \
        '{printf("stream-uniprocessor-%s pass %s MB/s\n", test, $2)}' \
        | tee -a "${RESULT_FILE}"`
    echo $ret
    print_info $? STREAM-${test}-$ret
    lava-test-case STREAM-${test}-$ret --result pass
done

if [ $currChipsNum -ne 8 ];then
    echo "Now system Memory Count does not meet quantity requirements!!!!!!"
    # exit;
elif [ $memCountGB -ne 256 ] ;then
    echo "Now system Memory summory dose not meet quantity requirements!!!!!!!"
    # exit;
fi


for case in Copy Scale Add Triad;do
    ret=`grep "^$case" "$TEST_LOG" | awk {'print $2'}`
    sum=0.0
    count=0
    
    for i in $ret 
    do
        sum=`echo "$i + $sum" | bc`
        let count=count+1
    done

    avg=`echo "scale=5 ; $sum / $count" | bc`
    s2=0.0
    
    for i in $ret
    do
        s2=`echo "$s2 + ($i -$avg) * ($i -$avg)" | bc`
    done
    s2=`echo "scale=5 ; sqrt($s2/$count)/$avg *100" | bc`
    echo testcase-${case}-${s2}%


    if [ `echo "$avg < ${speedMap[$case]}" | bc ` -eq 1   ];then
        echo tasecase-speed-${case}-pass
    else
        echo testcase-speed-${case}-fail
    fi
    
    if [ `echo "$s2 < ${stdevMap[$case]}" | bc ` -eq 1 ];then
        echo testcase-stdev-${case}-pass
    else
        echo testcase-stdev-${case}-fail
    fi


done

rm -rf stream.c
rm -rf stream_omp_exe
