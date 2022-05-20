#!/bin/bash
while getopts "p:t:f:" opt; do
  case $opt in
    p)
        PACKAGE=$OPTARG
        echo "PACKAGE is $PACKAGE" ;;
    t)
        TIME=$OPTARG
        echo "time is $TIME min" ;;
    f)  FILENAME=$OPTARG
        echo "filename is $FILENAME"  ;;
    \?)
        echo "invalid arg"
        exit ;;
  esac
done
DURING=$((60*60*9))  #默认总时长是8个小时，超过8个小时就会强制退出，防止异常情况
LOGDIR=logdir_$(date "+%Y-%m-%d_%H-%M-%S")
log(){
  echo $(date "+%Y-%m-%d %H:%M:%S") $1
}
prepare() {
    log "$1 monkey前准备工作"
    mkdir -p ${LOGDIR}/$1
    adb -s $1 push  fastbot/monkeyq.jar /sdcard/
    adb -s $1 push  fastbot/framework.jar /sdcard/
    adb -s $1 push  fastbot/libs/* /data/local/tmp/
    if [ $FILENAME ]
    then
    installApp $1
    fi
}
killMonkey(){
  pid=$(adb -s $1 shell ps -A |grep monkey|awk '{print $2}')
  if [ $pid ]
  then
    adb -s $1 shell kill -9 $pid #手机需要root权限才能使用kill
    if [ $? -eq 0 ]
    then
      log "$1 kill monkey success "
    else
      log "$1 kill monkey failed"
    fi
  fi
}
killAllMoneky(){
  for line in `cat devices.txt`
  do
    killMonkey $line
  done
}
resetADB(){
  adb kill-server && adb start-server
}
getDevices() {
  #判断设备连接状态是否正常
  resetADB
  if [ $(adb devices|wc -l) -le 1 ]
  then
    log "没有可执行的设备"
    exit
  fi
  if [ $(adb devices|grep unauthorized|wc -l) -ne 0 ]
  then
    log "有设备没有授权"
    exit
  fi
    if [ $(adb devices|grep offline|wc -l) -ne 0 ]
  then
    log "有设备处于offline状态"
    resetADB
#    exit
  fi
  # 获取可执行的设备
  adb devices | sed '1d;$d' | awk '{print $1}' > devices.txt

}
#mk_dir(){
#    if [ -e $1 ]
#  then
#    rm -rf $1
#    log "$1 已删除"
#  fi
#  mkdir -p ${LOGDIR}/$1
#}

installApp(){
  #如果已经安装，则先卸载，防止因为覆盖安装低版本导致安装失败
  if [ $(adb -s $1 shell pm list packages|grep $PACKAGE|wc -l) -gt 0 ]
  then
    adb -s $1 uninstall $PACKAGE
  fi
  adb -s $1 install -r ./apkfiles/$FILENAME &
  sleep 5
  size=$(adb -s $1 shell  wm size|awk '{print $3'})
  echo $size
  x=$(echo $size|awk -F x '{print $1'})
  y=$(echo $size|awk -F x '{print $2'})
  # 不同机型需要适配百分比
  x_per=0.5
  y_per=0.858
  if [ $(adb -s $1 shell getprop|grep  -E "vivo|oppo"|wc -l) -gt 0 ]
  then
    echo $x $y
    adb -s $1 shell input tap $(($x/2)) $(($y*858/1000))
    echo $(($x/2)) $(($y*858/1000))
  fi
  if  [ $? -ne 0 ]
  then
    log  "$1 安装${FILENAME}失败"
    exit
  else
    log  "$1 安装${FILENAME}成功"
  fi
}
runMonkey(){
  killMonkey $1
  echo ${1}
  echo ${PACKAGE}
  echo ${TIME}
  adb -s $1 shell CLASSPATH=/sdcard/monkeyq.jar:/sdcard/framework.jar:/sdcard/fastbot-thirdpart.jar exec app_process /system/bin com.android.commands.monkey.Monkey -p $PACKAGE --agent reuseq --running-minutes $TIME --throttle 300 --output-directory /sdcard/$1 -v -v > ${LOGDIR}/$1/$1_fastbot.txt &
#  adb shell CLASSPATH=/sdcard/monkey.jar:/sdcard/framework.jar exec app_process /system/bin tv.panda.test.monkey.Monkey -p $PACKAGE --running-minutes $TIME --throttle 400 --uiautomatortroy  --output-directory /sdcard/fastbot -v -v > $1/$1.txt &
}

runAllDevices(){
  #getDevices
  for line in `cat devices.txt`
  do
    prepare $line
    log "开始执行monkey"
    runMonkey $line
    monitorMonkey $line &
  done
  wait
  post
  clearFile
}

monitorMonkey(){
  startime=$(date +%s)
  adb -s $1 logcat V > ${LOGDIR}/$1/$1_logcat.txt &
  sleep $((1*30)) #刚开始执行moneky,等待1分钟
  while true
  do
    if [ $(adb -s $1 shell ps -A|grep monkey|wc -l) -ne 0 ]
    then
      log "$1 monkey执行中"
    else
      log "$1 monkey执行结束"
      break
    fi
    nowtime=$(date +%s)
    interval=$(($nowtime-$startime))
    if [ $interval -ge $DURING ]
    then
      log "$1 monkey执行时间超时，强制退出"
      killMonkey $1
      break
    fi
    sleep $((1*60)) #5分钟监测一次
  done
}
post(){
  for line in `cat devices.txt`
  do
    adb -s $line pull /sdcard/$line ./${LOGDIR}/$line/
  done
}
clearFile(){
  mv nohup.out ${LOGDIR}
  log "移动日志文件成功"
}
runAllDevices