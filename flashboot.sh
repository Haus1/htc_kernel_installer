#!/system/bin/sh
#   Copyright 2012 haus.xda@gmail.com
#
#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
#   Unless required by applicable law or agreed to in writing, software
#   distributed under the License is distributed on an "AS IS" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#   See the License for the specific language governing permissions and
#   limitations under the License.

#
#  HTC Kernel Installer - v0.57
#   haus.xda@gmail.com
#
# 'if' is not always available so case is a more reliable alternative.
#

exec 1>>/data/local/bootinfo.txt 2>&1

PRINTLOG(){
	sync
	logwrapper echo $$" "$@
	echo $$" "$@
}
REBOOT(){
	#---Depending on the ROM 'reboot' may not be reliable
	while :; do
		REBOOT2 "/system/bin/reboot" " $@"
		REBOOT2 $TMPBB " reboot -d 2 -f $@"
		REBOOT2 $ROMBB " reboot -d 2 -f $@"
		PRINTLOG "Sending the reboot command to the radio..."
		echo -e 'AT$QCPWRDN\r' > /dev/smdcntl0; sleep 2
		echo -e 'AT$QCPWRDN\r' > /dev/smd0; sleep 2
		PRINTLOG "Failed To Reboot, Retying In 5 Seconds"
		sleep 5
	done
}
REBOOT2(){
	case $(ls $1) in
		$1)	PRINTLOG "Attempting to Reboot with \"$@\""
			sync; $@
			case $? in
				0)	PRINTLOG "Call to Reboot Successful"; sleep 8;;
			esac;;
	esac
}


echo $$" - "`date`" - "${0##*\/}" Starting --------------"

TMPBB="/system/bin/busybox2"
ROMBB="/system/xbin/busybox"
BOOTNEW="/data/local/bootnew.img"
BOOTOLD="/data/local/bootold.img"
BOOTNEWPAD="/data/local/bootnewpad.img"
BOOTCURRENT="/data/local/bootcurrent.img"
APPPROCESS="/system/bin/app_process"
NETD="/system/bin/netd"
FLASHBOOT="/system/bin/flashboot.sh"
BBPIDOF=$TMPBB" pidof"
BBGREP=$TMPBB" grep"
BBAWK=$TMPBB" awk"
BBMOUNT=$TMPBB" mount"
BBDD=$TMPBB" dd"
BBSTAT=$TMPBB" stat"
BBMD5=$TMPBB" md5sum"


#---Only the instance with the lowest PID should stay running
PIDS=$($BBPIDOF ${FLASHBOOT##*\/})
case ${PIDS##* } in
	$$)	PRINTLOG "Looks like this is the one! Proceeding...";;
	*)	PRINTLOG "Yielding to \"${PIDS##* }\""; exit 1;;
esac

#---Find the moint point for Boot and remount /system as writable
case $(ls "/proc/mtd") in
	/proc/mtd)
		EMMTD="/proc/mtd";;
	*)	EMMTD="/proc/emmc";;
esac
BLOCKBOOT=/dev/block/$(cat $EMMTD | $BBGREP '"boot"' | $BBAWK '-F:' '{ print $1; }')
PRINTLOG "Found Boot Partitions Mount Point at \""$BLOCKBOOT"\""
sync; $BBMOUNT -o rw,remount /system

#---Make sure the boot.img is where we expect it, if it's gone check to see if the padded copy is still available
$BBDD if=$BLOCKBOOT of=$BOOTOLD conv=noerror; sync
case $(ls $BOOTNEW) in
	$BOOTNEW)
		PRINTLOG "Preparing to Write New Boot Image"
		SIZEBOOT=$($BBSTAT $BOOTOLD | $BBGREP "Size:" | $BBAWK '{ printf("%s\n",$2); }'); sync
		$BBDD if=$BOOTNEW ibs=$SIZEBOOT of=$BOOTNEWPAD conv=sync; sync
		rm $BOOTNEW;;
	*)	case $(! ls $BOOTNEWPAD >>/dev/null 2>&1; echo $?) in
			0)	PRINTLOG "\"$BOOTNEW\" not found! Was /data wiped?"
				REBOOT "recovery";;
			*)	PRINTLOG "\"$BOOTNEW\" not found! Using \"$BOOTNEWPAD\" instead.";;
		esac;;
esac

#---Flash the new boot.img and then compare MD5s to verify it
$BBDD if=$BOOTNEWPAD of=$BLOCKBOOT; sync
$BBDD if=$BLOCKBOOT of=$BOOTCURRENT conv=noerror; sync

PRINTLOG "Verifying the Boot partitions MD5"
MD5OLD=$($BBMD5 $BOOTOLD | $BBAWK '-F ' '{ print $1; }')
MD5NEWPAD=$($BBMD5 $BOOTNEWPAD | $BBAWK '-F ' '{ print $1; }')
MD5CURRENT=$($BBMD5 $BOOTCURRENT | $BBAWK '-F ' '{ print $1; }')
PRINTLOG "$MD5OLD  $BOOTOLD"
PRINTLOG "$MD5NEWPAD  $BOOTNEWPAD"
PRINTLOG "$MD5CURRENT  $BOOTCURRENT"

case $MD5CURRENT in
	$MD5NEWPAD)
		PRINTLOG "Verified Boot Flashed Properly";;
	$MD5OLD)
		PRINTLOG "Failed to Write to \"$BLOCKBOOT\"!"
		REBOOT "recovery";;
	*)	PRINTLOG "Failed to Flash Correctly! Restoring Original."
		$BBDD if=$BOOTOLD of=$BLOCKBOOT
		REBOOT "recovery";;
esac

#---Replace the old files and clean up any unneeded ones
PRINTLOG "Cleaning Up";
cat $APPPROCESS.bck > $APPPROCESS
cat $NETD.bck > $NETD; sync
chown 0.2000 $APPPROCESS $NETD
chmod 755 $APPPROCESS $NETD
rm $FLASHBOOT $BOOTCURRENT $BOOTNEWPAD $BOOTOLD $APPPROCESS.bck $NETD.bck $TMPBB
REBOOT