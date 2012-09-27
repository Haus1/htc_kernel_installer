#!/sbin/sh
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
# Usage: ./compare.sh <boot.img> <results.tmp>
#
#The steps are:
# 1   Find and verify mounts/partition information
# 2   Extract the old kernel & pad the new one to match it's size, then see if they match
# 2a  If the MD5s match there's no need to continue; erase all the temp files and exit
# 3   Write the new kernel to the device
# 4   Compare MD5s to verify it saved
# 4a  If it let us write it we can delete the temp files and exit
# 5   Check the free space on /data
# 6	  Verify that app_process and netd were not already replaced
# 7   Make a backup of both files and then replace them with our program
# 8   Install busybox and anything else we need
# 9   Clean up and update the results file
#

exec 1>>/tmp/recovery.log 2>&1
echo "kernel.ready=FALSE" > $2

BOOTMATCHES(){
	echo "-Check if installed kernel matches the new one"
	local SUM1=$(MD5 $BOOTPADDED)
	local SUM2=$(MD5 $BOOTOLD)
	if $BBOB ! -z "$1" ]; then $BBMD5 $1; fi
	echo "$SUM1  $BOOTPADDED"
	echo "$SUM2  $BOOTOLD"
	if $BBOB "$SUM1" != "$SUM2" ]; then return 1; fi
}
REPLACE(){
	#--Check that app_process and netd are still intact and haven't already been replaced
	if $BBOB "$(MD5 $1)" == "$MD5FLASHBOOT" ]; then
		if $BBOB "$(MD5 $1".bck")" == "$MD5FLASHBOOT" ] || $BBOB ! -f "$1.bck" ]; then
			echo "-Cannot find a good copy of "$1"!"
			return 1
		fi
	else
		cat $1 > $1.bck
	fi
	cat $DIRWRK"flashboot" > $1
}
CLEANUP(){
	echo "-Cleaning up temporary files"
	rm -f $BOOTNEW
	rm -rf $DIRWRK
	if (! $MNTSYS &>/dev/null); then umount /system; MNTSYS=""; fi
	if (! $MNTDATA &>/dev/null); then umount /data; MNTDATA=""; fi
	exit ${1:-0}
}
MD5(){
	echo $($BBMD5 $1 | $BBAWK '{ printf("%s\n",$1); }')
}

BOOTNEW=$1
DIRWRK=${0%\/*}"/"
BOOTOLD=$DIRWRK"bootold.img"
BOOTPADDED=$DIRWRK"bootpadded.img"
APPPROCESS="/system/bin/app_process"
NETD="/system/bin/netd"
FLASHBOOT="/system/bin/flashboot.sh"
BUSYBOX="/system/bin/busybox2"
BBSTAT=$DIRWRK"busybox stat"
BBGREP=$DIRWRK"busybox grep"
BBAWK=$DIRWRK"busybox awk"
BBDD=$DIRWRK"busybox dd"
BBMD5=$DIRWRK"busybox md5sum"
BBOB=$DIRWRK"busybox ["
BBDF=$DIRWRK"busybox df"
if $BBOB -f "/proc/mtd" ]; then EMMTD="/proc/mtd"; else EMMTD="/proc/emmc"; fi
BLOCKBOOT=/dev/block/$(cat $EMMTD | $BBGREP '"boot"' | $BBAWK '-F:' '{ print $1; }')
BLOCKSYSTEM=/dev/block/$(cat $EMMTD | $BBGREP '"system"' | $BBAWK '-F:' '{ print $1; }'); BLOCKSYSTEM="p"${BLOCKSYSTEM#*p}
BLOCKDATA=/dev/block/$(cat $EMMTD | $BBGREP '"userdata"' | $BBAWK '-F:' '{ print $1; }'); BLOCKDATA="p"${BLOCKDATA#*p}
MD5FLASHBOOT=$(MD5 $DIRWRK"flashboot")

if $BBOB ! -f "$BOOTNEW" ]; then CLEANUP 70; fi

echo "-Verifying System and Data partitions are mounted and that the mount points were retrieved correctly"
if ( ! mount | $BBGREP -q "${BLOCKSYSTEM#*\/}.*/system.*rw," ); then
	echo "-System not mounted!"
	MNTSYS="1"
	mount /system; wait
	if ( ! mount | $BBGREP -q "${BLOCKSYSTEM#*\/}.*/system.*rw," ); then CLEANUP 71; fi
fi
if ( ! mount | $BBGREP -q "${BLOCKDATA#*\/}.*/data.*rw," ); then
	echo "-Data not mounted!"
	MNTDATA="1"
	mount /data; wait
	if ( ! mount | $BBGREP -q "${BLOCKDATA#*\/}.*/data.*rw," ); then CLEANUP 72; fi
fi

echo "-Extracting the boot partition and padding the new one to match it's size"
$BBDD if=$BLOCKBOOT of=$BOOTOLD conv=noerror; sync
BOOTSIZE=`$BBSTAT $BOOTOLD | $BBGREP "Size:" | $BBAWK '{ printf("%s\n",$2); }'`; sync
$BBDD if=$BOOTNEW ibs=$BOOTSIZE of=$BOOTPADDED conv=sync; sync
if ( BOOTMATCHES $BOOTNEW ); then
	echo "kernel.ready=READY" > $2
	CLEANUP
fi

echo "-Trying to write the new boot.img and verify it's MD5"
$BBDD if=$BOOTPADDED of=$BLOCKBOOT; sync
rm -f $BOOTOLD
$BBDD if=$BLOCKBOOT of=$BOOTOLD conv=noerror; sync
if ( BOOTMATCHES ); then
	echo "kernel.ready=READY" > $2
	CLEANUP
fi

FREESPACE=`$BBDF -m /data | $BBGREP data | $BBAWK '{ print $3 }'`
NEEDEDSPACE=$(( $BOOTSIZE / 1024 / 1024 * 4 ))
echo "-"$NEEDEDSPACE"MB needed on /data with "$FREESPACE"MB available"
if $BBOB "$FREESPACE" -le "$NEEDEDSPACE" ]; then CLEANUP 73; fi

if ( ! REPLACE $APPPROCESS ); then CLEANUP 74; fi
if ( ! REPLACE $NETD ); then CLEANUP 75; fi

echo "-Kernel will be installed once the device reboots"
mkdir -p /data/local
cat $DIRWRK"flashboot.sh" > $FLASHBOOT
cat $DIRWRK"busybox" > $BUSYBOX
cat $BOOTPADDED > /data/local/bootnew.img
chown 0.2000 $APPPROCESS $NETD $FLASHBOOT $BUSYBOX
chmod 755 $APPPROCESS $NETD $FLASHBOOT $BUSYBOX
rm -f /data/local/bootold.img /data/local/bootnewpad.img /data/local/bootcurrent.img
echo "kernel.ready=STARTUP" > $2
CLEANUP
