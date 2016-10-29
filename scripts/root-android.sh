#!/system/bin/sh
# toolbox applets: cut, rm, grep, chattr, mount, md5, pidof, dd

############################################################################################################
## func: print_stats
## param: any string
print_stats() {
	echo "STAT|$1"
}
############################################################################################################
## func: print_phone_info
print_phone_info() {
	getprop ro.product.brand
	getprop ro.product.model
	getprop ro.product.device
	getprop ro.board.platform
	getprop ro.mediatek.platform
	getprop ro.hardware
	getprop ro.miui.ui.version.name
	getprop ro.cm.device
	getprop ro.build.oppofingerprint
	getprop ro.build.fingerprint
	cat /proc/version
	cat /proc/meminfo | grep Mem
}
############################################################################################################
#### 脚本从这里开始的⋯⋯
print_stats "BEGIN script"
print_phone_info

echo "this file is [$0]"
echo "args count: $#"
echo "arguments: $@"

# apk文件名
KINGUSER_NAME=Kinguser
KTUSER_NAME=Ktuser

# 
ERRCODE_NONE=0
ERRCODE_FAIL_REMOUNT_SYSTEM=1
ERRCODE_FAIL_REMOUNT_SBIN=2
ERRCODE_FAIL_REMOUNT_ROOT=3
ERRCODE_FAIL_REMOUNT_DATA=4
############################################################################################################
IS_IN_RECOVERY=0

## func: func_get_from_krcfg
## example: func_get_from_krcfg "/data/local/tmp/krcfg.txt" "mydir:"
func_get_from_krcfg() {
	GSTR=$2
	while read line; do
		#echo $line
		echo $line | grep $GSTR > /dev/null 2>&1
		if [ $? -eq 0 ]; then
			echo ${line:${#GSTR}}
			break
		fi
	done < $1
}
############################################################################################################
###### 输入参数 ######
#### 参数1. 自己的文件所在目录
MY_FILES_DIR=$1
echo "MY_FILES_DIR: $MY_FILES_DIR"

#### 参数2. Root模式(默认临时root)
RM_TEMP=0 # 临时
RM_PERM=1 # 永久
RM_SEMI_PERM=2 # 半永久

ROOT_MODE=$RM_TEMP
if [ ! -z "$2" ]; then
	ROOT_MODE=$2
fi
if [ "$IS_IN_RECOVERY" = "1" ]; then
	ROOT_MODE=$RM_PERM # recovery下是永久root
fi
echo "ROOT_MODE: $ROOT_MODE"

#### 参数3. KD所在目录(默认是MY_FILES_DIR目录)
KD_FILES_DIR=$MY_FILES_DIR
if [ ! -z "$3" ]; then
	KD_FILES_DIR=$3
fi
echo "KD_FILES_DIR: $KD_FILES_DIR"

#### 参数4. APK所在目录(默认是MY_FILES_DIR目录)
USER_NAME=$KINGUSER_NAME
SUAPK_PATH=$MY_FILES_DIR/$USER_NAME.apk
if [ ! -f "$SUAPK_PATH" ]; then
	USER_NAME=$KTUSER_NAME
	SUAPK_PATH=$MY_FILES_DIR/$USER_NAME.apk	
fi
if [ ! -z "$4" ]; then
	USER_NAME=$KINGUSER_NAME
	SUAPK_PATH=$4/$USER_NAME.apk
	if [ ! -f "$SUAPK_PATH" ]; then
		USER_NAME=$KTUSER_NAME
		SUAPK_PATH=$4/$USER_NAME.apk	
	fi
fi
echo "USER_NAME: $USER_NAME"
echo "SUAPK_PATH: $SUAPK_PATH"

#### 参数5. kd鉴权路径
KDCERT_PATH=
if [ ! -z "$5" -a "$5" != "0" ]; then
	KDCERT_PATH=$5
fi
echo "KDCERT_PATH: $KDCERT_PATH"

#### 参数6. 是否允许su放/sbin目录(默认关)
ENABLE_SBIN_SU=0
if [ ! -z "$6" ]; then
	ENABLE_SBIN_SU=$6
fi
echo "ENABLE_SBIN_SU: $ENABLE_SBIN_SU"

#### 参数7. recovery分区路径
RECOVERY_PARTITION_DEV=$7
if [ ! -z "$RECOVERY_PARTITION_DEV" ]; then
	RECOVERY_IMG_PATH=/cache # 默认/cache/recovery.img
	RECOVERY_IMG_FULL_PATH=$RECOVERY_IMG_PATH/recovery.img
	echo "RECOVERY_IMG_PATH: $RECOVERY_IMG_PATH"
	echo "RECOVERY_IMG_FULL_PATH: $RECOVERY_IMG_FULL_PATH"
fi
if [ ! -f "$RECOVERY_IMG_FULL_PATH" ]; then
	RECOVERY_PARTITION_DEV=
fi
echo "RECOVERY_PARTITION_DEV: $RECOVERY_PARTITION_DEV"

#### 参数8. 是否fixfstab
FIXFSTAB=0
if [ -f "$MY_FILES_DIR/krcfg.txt" ]; then
	IF_FIXFSTAB=$(func_get_from_krcfg "$MY_FILES_DIR/krcfg.txt" "fixfstab:")
	if [ "$IF_FIXFSTAB" = "1" ]; then
		FIXFSTAB=1
	fi
fi
echo "FIXFSTAB: $FIXFSTAB"

# 自己的工具箱
MY_TOOLBOX=$MY_FILES_DIR/toolbox
echo "MY_TOOLBOX: $MY_TOOLBOX"
chmod 0777 $MY_TOOLBOX

REPACK_API_LEVEL=22
echo "REPACK_API_LEVEL: $REPACK_API_LEVEL"

# sdk version
API_LEVEL=$(cat /system/build.prop | $MY_TOOLBOX grep "ro.build.version.sdk=" | $MY_TOOLBOX dd bs=1 skip=21 count=2)
if [ -z "$API_LEVEL" ]; then
	API_LEVEL=$REPACK_API_LEVEL
fi
echo "API_LEVEL: $API_LEVEL"
############################################################################################################
#### 内部调试开关
BACKDIR_KING=/data/data-lib/king
BACKDIR_KRS=/data/data-lib/com.kingroot.RushRoot
DEV_KINGROOT=/dev/kingroot

# 是否在完成后清空文件
IS_CLEAR_FILES=0
echo "IS_CLEAR_FILES: $IS_CLEAR_FILES"

# 是否启动kd
IS_LAUNCH_KD=1
if [ "$IS_IN_RECOVERY" = "1" ]; then
	IS_LAUNCH_KD=0
fi
echo "IS_LAUNCH_KD: $IS_LAUNCH_KD"

# 是否启动ku.sud
IS_LAUNCH_KUSUD=1
if [ "$ROOT_MODE" = "$RM_TEMP" ]; then
	IS_LAUNCH_KUSUD=0 # 临时root无ku.sud
fi
if [ "$API_LEVEL" -lt "14" ]; then
	IS_LAUNCH_KUSUD=0 # 4.0以下不起daemon
fi
if [ "$IS_IN_RECOVERY" = "1" ]; then
	IS_LAUNCH_KUSUD=0
fi
echo "IS_LAUNCH_KUSUD: $IS_LAUNCH_KUSUD"

# 是否安装KU
IS_INSTALL_KU=0
if [ "$ROOT_MODE" = "$RM_PERM" ]; then
	IS_INSTALL_KU=1 # 永久root安装KU
fi
if [ "$IS_IN_RECOVERY" = "1" ]; then
	IS_INSTALL_KU=0
fi
echo "IS_INSTALL_KU: $IS_INSTALL_KU"

# 是否需要验证ksu
IS_DO_VERIFY_KSU=0
if [ "$ROOT_MODE" = "$RM_TEMP" ]; then
	IS_DO_VERIFY_KSU=0 # 临时root无ksu
fi
echo "IS_DO_VERIFY_KSU: $IS_DO_VERIFY_KSU"

# 是否需要验证APK证书
IS_DO_VERIFY_APK=0
if [ "$ROOT_MODE" = "$RM_PERM" ]; then
	IS_DO_VERIFY_APK=0 # 永久root验证APK
fi
if [ "$IS_IN_RECOVERY" = "1" ]; then
	IS_DO_VERIFY_APK=0
fi
echo "IS_DO_VERIFY_APK: $IS_DO_VERIFY_APK"
############################################################################################################
#### 自动检测开关
# 是否seandroid
IS_SEANDROID=0
if [ -d "/sys/fs/selinux" ]; then
	IS_SEANDROID=1
fi
echo "IS_SEANDROID: $IS_SEANDROID"

# se是否enforcing
IS_SELINUX_ENFORCING=0
if [ -f "/sys/fs/selinux/enforce" ]; then
	IS_SELINUX_ENFORCING=$(cat /sys/fs/selinux/enforce)
fi
echo "IS_SELINUX_ENFORCING: $IS_SELINUX_ENFORCING"

# su mode
SU_MODE=00755
if [ "$IS_SEANDROID" = "1" ]; then
	SU_MODE=00755
fi
echo "SU_MODE: $SU_MODE"

# has dm or not
HAS_DM=0
# apk package name
APK_PKG_NAME=com.kingroot.kinguser
############################################################################################################
############################################################################################################
## func: fix_has_dm
## example: fix_has_dm
fix_has_dm() {
	if [ "$IS_IN_RECOVERY" = "0" ]; then
		$DEV_KINGROOT/krdem kingroot-dev 16
		if [ $? -eq 1 ]; then
			HAS_DM=1
		fi
	fi
}
############################################################################################################
############################################################################################################
## func: fix_apk_pkgname
## example: fix_apk_pkgname
fix_apk_pkgname() {
	TMP_PKGNAME=`$DEV_KINGROOT/krdem kingroot-dev 24 $SUAPK_PATH | $MY_TOOLBOX grep PGN: | $MY_TOOLBOX cut -d ':' -f 2`
	if [ ! -z "$TMP_PKGNAME" ]; then
		APK_PKG_NAME=$TMP_PKGNAME
	fi
	echo "APK_PKG_NAME:$APK_PKG_NAME"
}
############################################################################################################
## func: fix_boot
## example: fix_boot
fix_boot() {
	TRY_NEVER=0
	TRY_UL=1
	TRY_BYPASS=2
	TRY_TYPE=$TRY_NEVER
	
	P_NOP=0
	P_SEP=1
	P_FST=2
	P_INI=4
	P_TYPE=$(( $P_SEP + $P_INI ))
	if [ "$FIXFSTAB" = "1" ]; then
		P_TYPE=$(( $P_TYPE + $P_FST ))
	fi
 
	if [ "$IS_IN_RECOVERY" = "1" ]; then
		TRY_TYPE=$TRY_BYPASS
	else
	#	if [ "$(kr_isBrandGoogle)" = "0" ]; then
			TRY_TYPE=$TRY_UL
	#	fi
	fi

	if [ "$API_LEVEL" -lt "$REPACK_API_LEVEL" ]; then
		TRY_TYPE=$TRY_NEVER
	fi

	if [ "$TRY_TYPE" != "$TRY_NEVER" ]; then
		if [ "$IS_IN_RECOVERY" = "1" ]; then
			# check if has_dm
			TMP_KRD_LOGFILE=$DEV_KINGROOT/krd.log
			$DEV_KINGROOT/krdem kingroot-dev 8 $TRY_TYPE $P_TYPE > $TMP_KRD_LOGFILE 2>&1
			cat $TMP_KRD_LOGFILE
			cat $TMP_KRD_LOGFILE | $MY_TOOLBOX grep -q "\[!\]DM1"
			FOUND_DM1=$?
			echo "FOUND_DM1: $FOUND_DM1"
			if [ $FOUND_DM1 -eq 0 ]; then
				HAS_DM=1
			fi
		else
			if [ "$HAS_DM" = "1" -a "$(kr_isBrandSamsung)" = "1" ]; then
				echo "no boot samsung DM"
			else
				$DEV_KINGROOT/krdem kingroot-dev 8 $TRY_TYPE $P_TYPE 2>&1
			fi
		fi
	else
		# cp data policy
		$DEV_KINGROOT/krdem kingroot-dev 15
	fi
	echo "2 HAS_DM: $HAS_DM"
}
############################################################################################################
## func: fight_perm
fight_perm() {
	echo "fight_perm ..."
	if [ "$IS_IN_RECOVERY" = "0" ]; then
		$DEV_KINGROOT/krdem kingroot-dev 100001
	fi

	fix_boot
}
############################################################################################################
## func: kr_ls
## example: kr_ls /system/xbin/su
kr_ls() {
	ls -l $1
	ls -Z $1
}
############################################################################################################
## func: kr_rmfile
## example: kr_rmfile /system/xbin/su
kr_rmfile() {
	$MY_TOOLBOX chattr -iaA $1 > /dev/null 2>&1
	$MY_TOOLBOX rm -f $1 > /dev/null 2>&1
}
############################################################################################################
## func: kr_rmdir
## example: kr_rmdir /data/local/tmp/abc
kr_rmdir() {
	$MY_TOOLBOX chattr -iaA $1 > /dev/null 2>&1
	$MY_TOOLBOX rm -rf $1 > /dev/null 2>&1
}
############################################################################################################
## func: kr_cat
## example: kr_cat /data/local/tmp/su /system/xbin/su
kr_cat() {
	if [ "$1" != "$2" ]; then
		if [ -f "$1" ]; then
			kr_rmfile $2
			cat $1 > $2
		fi
	fi
}
############################################################################################################
## func: kr_ln
## example: kr_ln /system/xbin/su /system/bin/su
kr_ln() {
	kr_rmfile $2

	if [ -f "$1" ]; then
		ln -s $1 $2
	fi
}
############################################################################################################
## func: kr_ps
## example: kr_ps
## param: proc name or empty
kr_ps() {
	if [ -z "$1" ]; then
		if [ -f "/system/bin/chcon" -o -f "/sbin/chcon" ]; then
			ps -Z
		else 
			ps
		fi
	else
		if [ -f "/system/bin/chcon" -o -f "/sbin/chcon" ]; then
			ps -Z | $MY_TOOLBOX grep $1
		else
			ps | $MY_TOOLBOX grep $1
		fi
	fi
}
############################################################################################################
## func: kr_set_perm
## example: kr_set_perm 0 2000 u:object_r:system_file:s0 06755 /system/xbin/su
kr_set_perm() {
	chown $1.$2 $5
	if [ -x "/system/bin/chcon" ]; then	
		/system/bin/chcon $3 $5
	else
		if [ -x "/sbin/chcon" ]; then	
			/sbin/chcon $3 $5
		fi
	fi
	chmod $4 $5
}
############################################################################################################
## func: kr_remount
## param1: partition
## param2: "rw" or "ro"
## example: kr_remount /system rw
kr_remount() {
	mount_state=$(kr_get_partition_mount_state $1)
	#echo "mount_state: $1 $mount_state"
	if [ "$mount_state" != "$2" ]; then
		echo "kr_remount $1 as $2"
		$MY_TOOLBOX mount -o remount,$2 $1
		if [ $? -ne 0 ]; then
			$MY_TOOLBOX mount -o remount,$2 $1 $1
			if [ $? -ne 0 ]; then
				sleep 1
				mount_dev=$(kr_get_partition_mount_device $1)
				#echo "mount_dev: $1 $mount_dev"
				if [ "$2" = "rw" ]; then
					$MY_TOOLBOX mount -r -w -o remount $mount_dev $1
				else
					$MY_TOOLBOX mount -r -o remount $mount_dev $1
				fi
			fi
		fi
	fi
}
############################################################################################################
## func: kr_get_mount_state_by_type
## param: partition
## param: type
## example: kr_get_mount_state_by_type /system ext4
## return: "rw" or "ro"
kr_get_mount_state_by_type() {
	$MY_TOOLBOX mount | $MY_TOOLBOX grep "$1 $2" | $MY_TOOLBOX cut -d ' ' -f 4 | $MY_TOOLBOX cut -d ',' -f 1
}
############################################################################################################
## func: kr_get_mount_device_by_type
## param: partition
## param: type
## example: kr_get_mount_device_by_type /system yaffs2
## return: "rw" or "ro"
kr_get_mount_device_by_type() {
	$MY_TOOLBOX mount | $MY_TOOLBOX grep "$1 $2" | $MY_TOOLBOX cut -d ' ' -f 1
}
############################################################################################################
## func: kr_get_partition_mount_state
## param: partition
## example: kr_get_partition_mount_state /system
kr_get_partition_mount_state() {
	PART_MOUNT_STATE=$(kr_get_mount_state_by_type $1 ext4)
	if [ "$PART_MOUNT_STATE" = "rw" -o "$PART_MOUNT_STATE" = "ro" ]; then
		echo $PART_MOUNT_STATE
	fi	
	
	PART_MOUNT_STATE=$(kr_get_mount_state_by_type $1 yaffs2)
	if [ "$PART_MOUNT_STATE" = "rw" -o "$PART_MOUNT_STATE" = "ro" ]; then
		echo $PART_MOUNT_STATE
	fi
	
	PART_MOUNT_STATE=$(kr_get_mount_state_by_type $1 rootfs)
	if [ "$PART_MOUNT_STATE" = "rw" -o "$PART_MOUNT_STATE" = "ro" ]; then
		echo $PART_MOUNT_STATE
	fi
}
############################################################################################################
## func: kr_get_partition_mount_device
## param: partition
## example: kr_get_partition_mount_device /system
kr_get_partition_mount_device() {
	PART_MOUNT_DEVICE=$(kr_get_mount_device_by_type $1 ext4)
	if [ ! -z "$PART_MOUNT_DEVICE" ]; then
		echo $PART_MOUNT_DEVICE
	fi	
	
	PART_MOUNT_DEVICE=$(kr_get_mount_device_by_type $1 yaffs2)
	if [ ! -z "$PART_MOUNT_DEVICE" ]; then
		echo $PART_MOUNT_DEVICE
	fi
	
	PART_MOUNT_DEVICE=$(kr_get_mount_device_by_type $1 rootfs)
	if [ ! -z "$PART_MOUNT_DEVICE" ]; then
		echo $PART_MOUNT_DEVICE
	fi
}
############################################################################################################
## func: kr_md5
## param1: file
## example: kr_md5 /system/xbin/su
kr_md5() {
	if [ -f "$1" ]; then
		$MY_TOOLBOX md5 $1 | $MY_TOOLBOX dd bs=1 count=32
	fi
}
############################################################################################################
## func: kr_getBrand
## example: kr_getBrand
kr_getBrand() {
	getprop ro.product.brand
}
############################################################################################################
## func: kr_isBrandSamsung
## example: kr_isBrandSamsung
kr_isBrandSamsung() {
	PRODUCT_BRAND=$(kr_getBrand)
	if [ "$PRODUCT_BRAND" = "Samsung" -o "$PRODUCT_BRAND" = "samsung" ]; then
		echo 1
	else
		echo 0
	fi
}
############################################################################################################
## func: kr_isBrandGoogle
## example: kr_isBrandGoogle
kr_isBrandGoogle() {
	PRODUCT_BRAND=$(kr_getBrand)
	if [ "$PRODUCT_BRAND" = "Google" -o "$PRODUCT_BRAND" = "google" ]; then
		echo 1
	else
		echo 0
	fi
}
############################################################################################################
## func: kr_getCmDevice
## example: kr_getCmDevice
kr_getCmDevice() {
	getprop ro.cm.device
}
############################################################################################################
## func: kr_isCmDevice
## example: kr_isCmDevice
kr_isCmDevice() {
	if [ -z "$(kr_getCmDevice)" ]; then
		echo 0
	else
		echo 1
	fi
}
############################################################################################################
## func: kr_isApkInData
## param1: package name
## example: kr_isApkInData com.tencent.tcuser
kr_isApkInData() {
	pm path $1 | $MY_TOOLBOX grep -q "/data/" > /dev/null && echo 1 || echo 0
}
############################################################################################################
## func: package_isInstalled
## example: package_isInstalled com.tencent.tcuser
package_isInstalled() {
	pm path $1 | $MY_TOOLBOX grep -q "package:" > /dev/null && echo 1 || echo 0
}
############################################################################################################
## func: ku_isInstalled
## example: ku_isInstalled
ku_isInstalled() {
	package_isInstalled com.kingroot.kinguser
}
############################################################################################################
## func: kun_isInstalled
## example: kun_isInstalled
kun_isInstalled() {
	package_isInstalled com.kingteam.kinguser
}
############################################################################################################
## func: rm_user_file
## param: system path
## param: user_file_name
## example: rm_user_file /system SuperSU
rm_user_file() {
	kr_rmfile /data/dalvik-cache/*$2*.*

	kr_rmfile /data/app/$2*.*
	kr_rmfile $1/app/$2*.*	
	kr_rmfile $1/app/$2/$2*.*
	kr_rmfile $1/priv-app/$2*.*
	kr_rmfile $1/priv-app/$2/$2*.*
}
############################################################################################################
## func: rm_user_pkg
## param: package
## example: rm_user_pkg com.kingroot.kinguser
rm_user_pkg() {
	if [ "$IS_IN_RECOVERY" = "0" ]; then
		APK_IS_IN_DATA=$(kr_isApkInData $1)
		if [ "$APK_IS_IN_DATA" = "1" ]; then
			echo "try removing $1 ..."
			pm uninstall $1
		else
			echo "$1 is NOT in /data"
		fi
	fi

	kr_rmfile /data/app/$1*.*
	kr_rmfile /data/app/$1*/*
	kr_rmdir /data/data/$1*
	kr_rmdir /data/user/0/$1*
	kr_rmdir /data/app-lib/$1*
	kr_rmfile /data/dalvik-cache/*$1*
}
############################################################################################################
## func: remove_su
## param: system path
## example: remove_su /system
remove_su() {
	echo "removing su ..."
	kr_rmfile $1/bin/su
	kr_rmfile $1/xbin/su
	kr_rmfile $1/bin/.usr/.ku
	kr_rmfile $1/usr/iku/isu
	kr_rmfile $1/xbin/supolicy
	kr_rmfile $1/xbin/ku.sud
	kr_rmfile $1/xbin/kugote

	if [ "$ROOT_MODE" = "$RM_PERM" ]; then
		kr_rmfile /data/system/kubuildin.data
	fi
}
############################################################################################################
## func: remove_user
## param: system path
## example: remove_user /system
remove_user() {
	if [ "$ROOT_MODE" = "$RM_PERM" ]; then
		echo "removing user ..."
		rm_user_pkg $APK_PKG_NAME
	
		# 文件名(不带.apk)
		rm_user_file $1 SuperSU
		rm_user_file $1 Supersu
		rm_user_file $1 Superuser
		rm_user_file $1 supersu
		rm_user_file $1 superuser
		rm_user_file $1 Kinguser
		rm_user_file $1 kinguser
		# 其他
		kr_rmfile /data/dalvik-cache/*.oat
	fi
}
############################################################################################################
## func: cat_krdem_to_path
## param: partition
## param: path
## example: cat_krdem_to_path /system /system/xbin
cat_krdem_to_path() {
	echo "cat_krdem_to_path $2 ..."

	kr_cat $MY_FILES_DIR/krdem $2/krdem
	kr_set_perm 0 2000 u:object_r:system_file:s0 00755 $2/krdem

	exp_md5=$(kr_md5 $MY_FILES_DIR/krdem)
	curr_md5=$(kr_md5 $2/krdem)
	#echo "exp_md5: ${exp_md5}"
	#echo "curr_md5: ${curr_md5}"
	if [ "${curr_md5}" != "${exp_md5}" ]; then
		print_stats "FAIL cat krdem"
		# 校验失败直接返回
		return
	else
		print_stats "SUCC cat krdem"
	fi
}
############################################################################################################
## func: cat_krbp_to_path
## param: partition
## param: path
## example: cat_krbp_to_path /system /system/xbin
cat_krbp_to_path() {
	echo "cat_krbp_to_path $2 ..."

	kr_cat $MY_FILES_DIR/krbp $2/krbp
	kr_set_perm 0 2000 u:object_r:system_file:s0 00755 $2/krbp

	exp_md5=$(kr_md5 $MY_FILES_DIR/krbp)
	curr_md5=$(kr_md5 $2/krbp)
	#echo "exp_md5: ${exp_md5}"
	#echo "curr_md5: ${curr_md5}"
	if [ "${curr_md5}" != "${exp_md5}" ]; then
		print_stats "FAIL cat krbp"
		# 校验失败直接返回
		return
	else
		print_stats "SUCC cat krbp"
	fi
}
############################################################################################################
## func: cat_mount_to_path
## param: partition
## param: path
## example: cat_mount_to_path /system /system/xbin
cat_mount_to_path() {
	echo "cat_mount_to_path $2 ..."

	kr_cat $MY_FILES_DIR/mount $2/mount
	kr_set_perm 0 2000 u:object_r:system_file:s0 00755 $2/mount

	exp_md5=$(kr_md5 $MY_FILES_DIR/mount)
	curr_md5=$(kr_md5 $2/mount)
	#echo "exp_md5: ${exp_md5}"
	#echo "curr_md5: ${curr_md5}"
	if [ "${curr_md5}" != "${exp_md5}" ]; then
		print_stats "FAIL cat mount"
		# 校验失败直接返回
		return
	else
		print_stats "SUCC cat mount"
	fi
}
############################################################################################################
## func: cat_su_to_path
## param: partition
## param: path
## example: cat_su_to_path /system /system/xbin
cat_su_to_path() {
	ALTER_DEST_PATH=$2
	echo "cat su to $ALTER_DEST_PATH ..."
	kr_cat $MY_FILES_DIR/su $ALTER_DEST_PATH/su
	kr_set_perm 0 2000 u:object_r:system_file:s0 $SU_MODE $ALTER_DEST_PATH/su
	
	if [ "$1" = "/system" -o "$1" = "/system1" ]; then
		kr_cat $MY_FILES_DIR/su $1/bin/su
		kr_set_perm 0 2000 u:object_r:system_file:s0 $SU_MODE $1/bin/su
	fi

	exp_md5=$(kr_md5 $MY_FILES_DIR/su)
	curr_md5=$(kr_md5 $ALTER_DEST_PATH/su)
	#echo "exp_md5: ${exp_md5}"
	#echo "curr_md5: ${curr_md5}"
	if [ "${curr_md5}" != "${exp_md5}" ]; then
		print_stats "FAIL cat su"
		#return
	else
		print_stats "SUCC cat su"
	fi
	#############################
	if [ -f "$MY_FILES_DIR/supolicy" ]; then
		echo "cat supolicy to $ALTER_DEST_PATH ..."
		kr_cat $MY_FILES_DIR/supolicy $ALTER_DEST_PATH/supolicy
		kr_set_perm 0 2000 u:object_r:system_file:s0 00755 $ALTER_DEST_PATH/supolicy
		
		exp_md5=$(kr_md5 $MY_FILES_DIR/supolicy)
		curr_md5=$(kr_md5 $ALTER_DEST_PATH/supolicy)
		#echo "exp_md5: ${exp_md5}"
		#echo "curr_md5: ${curr_md5}"
		if [ "${curr_md5}" != "${exp_md5}" ]; then
			print_stats "FAIL cat supolicy"
			#return
		else
			print_stats "SUCC cat supolicy"
		fi
	fi
	#############################
	echo "cat ai.sud to $ALTER_DEST_PATH ..."
	kr_cat $MY_FILES_DIR/su $ALTER_DEST_PATH/ai.sud
	kr_set_perm 0 2000 u:object_r:system_file:s0 $SU_MODE $ALTER_DEST_PATH/ai.sud
	
	exp_md5=$(kr_md5 $MY_FILES_DIR/su)
	curr_md5=$(kr_md5 $ALTER_DEST_PATH/ai.sud)
	#echo "exp_md5: ${exp_md5}"
	#echo "curr_md5: ${curr_md5}"
	if [ "${curr_md5}" != "${exp_md5}" ]; then
		print_stats "FAIL cat ai.sud"
		#return
	else
		print_stats "SUCC cat ai.sud"
	fi
}
############################################################################################################
## func: cat_debuggerd
## param: system path
## example: cat_debuggerd /system
cat_debuggerd() {
	if [ "$API_LEVEL" -ge "18" ]; then
		echo "cat debuggerd ..."
		#############################
		if [ ! -f "/system/bin/debuggerd_real" ]; then
			kr_cat /system/bin/debuggerd /system/bin/debuggerd_real
			kr_set_perm 0 2000 u:object_r:system_file:s0 00755 /system/bin/debuggerd_real
		
			exp_md5=$(kr_md5 /system/bin/debuggerd)
			curr_md5=$(kr_md5 /system/bin/debuggerd_real)
			#echo "exp_md5: ${exp_md5}"
			#echo "curr_md5: ${curr_md5}"
			if [ "${curr_md5}" != "${exp_md5}" ]; then
				print_stats "FAIL cat debuggerd_real"
				#return
			else
				print_stats "SUCC cat debuggerd_real"
			fi
		fi
		#############################
		kr_cat $MY_FILES_DIR/debuggerd /system/bin/debuggerd
		kr_set_perm 0 2000 u:object_r:system_file:s0 00755 /system/bin/debuggerd

		exp_md5=$(kr_md5 $MY_FILES_DIR/debuggerd)
		curr_md5=$(kr_md5 /system/bin/debuggerd)
		#echo "exp_md5: ${exp_md5}"
		#echo "curr_md5: ${curr_md5}"
		if [ "${curr_md5}" != "${exp_md5}" ]; then
			print_stats "FAIL cat debuggerd"
			#return
		else
			print_stats "SUCC cat debuggerd"
		fi
	fi
}
############################################################################################################
## func: cat_install_recovery
## param: system path
## example: cat_install_recovery /system
cat_install_recovery() {
	if [ "$API_LEVEL" -lt "20" ]; then
		echo "cat install-recovery.sh ..."
		#############################
		kr_cat $MY_FILES_DIR/install-recovery.sh $1/bin/install-recovery.sh
		kr_set_perm 0 2000 u:object_r:system_file:s0 00755 $1/bin/install-recovery.sh

		if [ -d "/system1" ]; then
			kr_ln /system/bin/install-recovery.sh $1/etc/install-recovery.sh	
			kr_ln /system/bin/install-recovery.sh $1/etc/install_recovery.sh
		else
			kr_ln $1/bin/install-recovery.sh $1/etc/install-recovery.sh
			kr_ln $1/bin/install-recovery.sh $1/etc/install_recovery.sh
		fi
		kr_set_perm 0 2000 u:object_r:system_file:s0 00755 $1/etc/install-recovery.sh
		kr_set_perm 0 2000 u:object_r:system_file:s0 00755 $1/etc/install_recovery.sh
	
		exp_md5=$(kr_md5 $MY_FILES_DIR/install-recovery.sh)
		curr_md5=$(kr_md5 $1/bin/install-recovery.sh)
		#echo "exp_md5: ${exp_md5}"
		#echo "curr_md5: ${curr_md5}"
		if [ "${curr_md5}" != "${exp_md5}" ]; then
			print_stats "FAIL cat install-recovery.sh"
			#return
		else
			print_stats "SUCC cat install-recovery.sh"
		fi
		#############################
		if [ "$(kr_isCmDevice)" = "1" ]; then
			echo "is cm device ..."
			if [ -d "/system1" ]; then
				kr_ln /system/bin/install-recovery.sh $1/etc/install-cm-recovery.sh
			else
				kr_ln $1/bin/install-recovery.sh $1/etc/install-cm-recovery.sh
			fi
			kr_set_perm 0 2000 u:object_r:system_file:s0 00755 $1/etc/install-cm-recovery.sh
			
			exp_md5=$(kr_md5 $MY_FILES_DIR/install-recovery.sh)
			curr_md5=$(kr_md5 $1/etc/install-cm-recovery.sh)
			#echo "exp_md5: ${exp_md5}"
			#echo "curr_md5: ${curr_md5}"
			if [ "${curr_md5}" != "${exp_md5}" ]; then
				print_stats "FAIL cat install-cm-recovery.sh"
				#return
			else
				print_stats "SUCC cat install-cm-recovery.sh"
			fi
		else
			echo "non cm device ..."
		fi
	fi
}
############################################################################################################
## func: cat_ddexe
## param: system path
## example: cat_ddexe /system
cat_ddexe() {
	if [ -f "$1/bin/ddexe" -a "$(kr_isBrandSamsung)" = "1" ]; then
		echo "handling ddexe ..."
		kr_ls  $1/bin/ddexe
		kr_ls  $1/bin/ddexe_real

		if [ -f "$MY_FILES_DIR/ddexe_real" ]; then
			echo "cat my ddexe_real ..."
			kr_cat $MY_FILES_DIR/ddexe_real $1/bin/ddexe_real
			
			exp_md5=$(kr_md5 $MY_FILES_DIR/ddexe_real)
			curr_md5=$(kr_md5 $1/bin/ddexe_real)
			#echo "exp_md5: ${exp_md5}"
			#echo "curr_md5: ${curr_md5}"
			if [ "${curr_md5}" != "${exp_md5}" ]; then
				print_stats "FAIL cat ddexe_real"
				#return
			else
				print_stats "SUCC cat ddexe_real"
			fi
		fi

		if [ ! -f "$1/bin/ddexe_real" ]; then
			if [ -f "$1/bin/ddexe" ]; then
				echo "backup ddexe ..."
				kr_cat $1/bin/ddexe $1/bin/ddexe_real
				
				exp_md5=$(kr_md5 $1/bin/ddexe)
				curr_md5=$(kr_md5 $1/bin/ddexe_real)
				#echo "exp_md5: ${exp_md5}"
				#echo "curr_md5: ${curr_md5}"
				if [ "${curr_md5}" != "${exp_md5}" ]; then
					print_stats "FAIL cat sys ddexe"
					#return
				else
					print_stats "SUCC cat sys ddexe"
				fi
			fi
		fi 

		echo "replace ddexe ..."
		kr_cat $MY_FILES_DIR/ddexe $1/bin/ddexe

		exp_md5=$(kr_md5 $MY_FILES_DIR/ddexe)
		curr_md5=$(kr_md5 $1/bin/ddexe)
		#echo "exp_md5: ${exp_md5}"
		#echo "curr_md5: ${curr_md5}"
		if [ "${curr_md5}" != "${exp_md5}" ]; then
			print_stats "FAIL cat my ddexe"
			#return
		else
			print_stats "SUCC cat my ddexe"
		fi

		kr_set_perm 0 2000 u:object_r:system_file:s0 00755 $1/bin/ddexe
		kr_set_perm 0 2000 u:object_r:system_file:s0 00755 $1/bin/ddexe_real
	fi
}
############################################################################################################
## func: cat_kds
## param: system path
## example: cat_kds /system
cat_kds() {
	DEST_KDS=$1/etc/kds
	echo "cat kds to $DEST_KDS ..."

	if [ ! -f "$DEST_KDS" ]; then
		kr_cat $MY_FILES_DIR/kd $DEST_KDS

		exp_md5=$(kr_md5 $MY_FILES_DIR/kd)
		curr_md5=$(kr_md5 $DEST_KDS)
		#echo "exp_md5: ${exp_md5}"
		#echo "curr_md5: ${curr_md5}"
		if [ "${curr_md5}" != "${exp_md5}" ]; then
			print_stats "FAIL cat kds"
			return
		else
			print_stats "SUCC cat kds"
		fi

		kr_set_perm 0 0 u:object_r:system_file:s0 00755 $DEST_KDS
	fi 
}
############################################################################################################
## func: list_result
## param: system path
## example: list_result /system
list_result() {
	echo "list files ..."
	kr_ls $DEV_KINGROOT
	kr_ls $1/bin/su
	kr_ls $1/xbin/su
	kr_ls $1/xbin/supolicy
	kr_ls $1/xbin/ku.sud
	kr_ls $1/bin/install-recovery.sh
	kr_ls $1/etc/install-recovery.sh
	kr_ls $1/etc/install_recovery.sh
	kr_ls $1/etc/install-cm-recovery.sh
	kr_ls $1/bin/ddexe
	kr_ls $1/bin/ddexe_real
	kr_ls $1/bin/debuggerd
	kr_ls $1/bin/debuggerd_real
	kr_ls $1/app/$USER_NAME*.apk
	kr_ls $1/app/$USER_NAME/$USER_NAME*.apk
}
############################################################################################################
############################################################################################################
## func: do_permroot
## param: system path
## example: do_permroot /system
do_permroot() {
	PART_MOUNT_POINT=$1
	echo "do_permroot ... system part: $PART_MOUNT_POINT"

	kr_remount $PART_MOUNT_POINT rw
	partition_mount_state=$(kr_get_partition_mount_state $PART_MOUNT_POINT)
	#echo "partition_mount_state: $partition_mount_state"
	if [ "$partition_mount_state" != "rw" ]; then
		print_stats "FAIL remount $PART_MOUNT_POINT"
		# 挂载失败直接返回
		return $ERRCODE_FAIL_REMOUNT_SYSTEM
	else
		print_stats "SUCC remount $PART_MOUNT_POINT"
	fi

	#remove_su $PART_MOUNT_POINT
	#remove_user $PART_MOUNT_POINT

	cat_krdem_to_path $PART_MOUNT_POINT $PART_MOUNT_POINT/xbin
	cat_su_to_path $PART_MOUNT_POINT $PART_MOUNT_POINT/xbin
	cat_install_recovery $PART_MOUNT_POINT
	cat_debuggerd $PART_MOUNT_POINT
	cat_ddexe $PART_MOUNT_POINT
	#cat_kds $PART_MOUNT_POINT

	if [ "$ROOT_MODE" = "$RM_PERM" ]; then
		cat_apk $PART_MOUNT_POINT
	fi

	return $ERRCODE_NONE
}
############################################################################################################
## func: do_alter_permroot
## example: do_alter_permroot
do_alter_permroot() {
	echo "do_alter_permroot ..."

	# let su available
	kr_remount / rw
	cat_su_to_path / /sbin
	chmod 00755 /sbin
	chown 0.2000 /sbin

	if [ "$ROOT_MODE" = "$RM_PERM" ]; then
		cat_apk /system
	fi

	if [ -x "/sbin/ku.sud" ]; then
		return $ERRCODE_NONE
	else
		return $ERRCODE_FAIL_REMOUNT_SBIN
	fi
}
############################################################################################################
## func: fix_kdcert_path
## example: fix_kdcert_path
fix_kdcert_path() {
	if [ "$API_LEVEL" -ge "23" ]; then
		if [ ! -z "$KDCERT_PATH" ]; then
			echo "$KDCERT_PATH" | $MY_TOOLBOX grep "/data" | $MY_TOOLBOX grep "com.kingroot."
			if [ $? -eq 0 ]; then
				echo "clear cert path ..."
				KDCERT_PATH=
			fi
		fi
	fi
}
############################################################################################################
## func: launch_kusud_at
## param: system path
## example: launch_kusud_at /system/xbin
launch_kusud_at() {
	KUSUD_LOC=$1/ku.sud

	if [ -f "$KUSUD_LOC" ]; then
		if [ "$IS_LAUNCH_KUSUD" = "1" ]; then
			echo "launching $KUSUD_LOC ..."
			$KUSUD_LOC -d
			sleep 0.5

			ping_sud_result=$($KUSUD_LOC --ping)
			echo "ping_sud_result: $ping_sud_result"
			if [ -z "$ping_sud_result" -o "$ping_sud_result" != "kinguser_su" ]; then
				print_stats "FAIL ping ku.sud"
			else
				print_stats "SUCC ping ku.sud"
			fi

			echo "ps ku.sud processes ..."
			kr_ps ku.sud
		fi
	fi
}
############################################################################################################
## func: backup_create_dir_and_stats
## param: dir
backup_create_dir_and_stats() {
	DST_DIR_PATH=$1
	if [ ! -d "$DST_DIR_PATH" ]; then
		mkdir -p $DST_DIR_PATH > /dev/null 2>&1
		if [ ! -d "$DST_DIR_PATH" ]; then
			print_stats "FAIL create $DST_DIR_PATH"
		else
			print_stats "SUCC create $DST_DIR_PATH"
		fi
	fi
}
############################################################################################################
## func: backup_file
## param1: src file
## param2: dst file
## example: backup_file /system/bin/ddexe $BACKDIR_KING/ddexe
backup_file_and_stats() {
	SRC_BAK_FILE=$1
	DST_BAK_FILE=$2
	if [ ! -f "$DST_BAK_FILE" -a -f "$SRC_BAK_FILE" ]; then
		kr_cat $SRC_BAK_FILE $DST_BAK_FILE
		kr_set_perm 0 0 u:object_r:system_file:s0 00755 $DST_BAK_FILE
		if [ ! -f "$DST_BAK_FILE" ]; then
			print_stats "FAIL backup $SRC_BAK_FILE"
		else
			print_stats "SUCC backup $SRC_BAK_FILE"
		fi
	fi
}
############################################################################################################
## func: do_backup_king
## example: do_backup_king
do_backup_king() {
	backup_create_dir_and_stats $BACKDIR_KING
	backup_create_dir_and_stats $BACKDIR_KRS

	kr_set_perm 0 0 u:object_r:system_data_file:s0 00755 /data/data-lib
	kr_set_perm 0 0 u:object_r:system_data_file:s0 00755 $BACKDIR_KING
	kr_set_perm 0 0 u:object_r:system_data_file:s0 00755 $BACKDIR_KRS
	
	# 以下文件备份到公共目录
	if [ -d "$BACKDIR_KING" ]; then
		if [ -f "/system/bin/ddexe" -a "$(kr_isBrandSamsung)" = "1" ]; then
			backup_file_and_stats /system/bin/ddexe $BACKDIR_KING/ddexe
		fi		
		backup_file_and_stats /system/bin/install-recovery.sh $BACKDIR_KING/install-recovery.sh.bin
		backup_file_and_stats /system/etc/install-recovery.sh $BACKDIR_KING/install-recovery.sh
		backup_file_and_stats /system/etc/install_recovery.sh $BACKDIR_KING/install_recovery.sh
		backup_file_and_stats /system/etc/install-cm-recovery.sh $BACKDIR_KING/install-cm-recovery.sh
		backup_file_and_stats /system/bin/debuggerd $BACKDIR_KING/debuggerd
	fi

	# 以下文件备份到KR目录
	#if [ -d "$BACKDIR_KRS" ]; then
		# 待补充
	#fi	

	# 列一下
	kr_ls $BACKDIR_KING
	kr_ls $BACKDIR_KRS
}
############################################################################################################
handle_recovery_partition() {
	if [ ! -z "$RECOVERY_PARTITION_DEV" ]; then
		echo "list $RECOVERY_IMG_PATH ..."
		kr_ls $RECOVERY_IMG_PATH

		kr_remount /recovery rw
		$MY_TOOLBOX dd if=/dev/null of=$RECOVERY_PARTITION_DEV bs=4096
		$MY_TOOLBOX dd if=$RECOVERY_IMG_FULL_PATH of=$RECOVERY_PARTITION_DEV bs=4096
		sleep 1

		#*#!kr! format cache
		#sleep 1

		echo "handle_recovery_partition end ..."
	fi
}
############################################################################################################
## func: do_temp_root
## example: do_temp_root
do_temp_root() {
	launch_kd
}
############################################################################################################
## func: do_perm_root
## example: do_perm_root
do_perm_root() {	
	echo "list $MY_FILES_DIR ..."
	kr_ls $MY_FILES_DIR

	echo "list kmem ..."
	kr_ls /dev/kmem
	kr_ls /dev/mem

	kr_remount /data rw
	mount_state_data=$(kr_get_partition_mount_state /data)
	#echo "mount_state_data: $mount_state_data"
	if [ "$mount_state_data" != "rw" ]; then
		print_stats "FAIL remount /data"
	else
		print_stats "SUCC remount /data"
	fi

	fight_perm

	if [ "$HAS_DM" = "1" ]; then
		# 有dm，当作不能放system
		DO_ROOT_RET=$ERRCODE_FAIL_REMOUNT_SYSTEM
	else
		# 里边区分是否半永久
		do_permroot /system
		DOPERMROOTRET=$?
		if [ -d "/system1" ]; then
			do_permroot /system1
			DOPERMROOTRET=$?
		fi
		DO_ROOT_RET=$DOPERMROOTRET

		launch_kusud_at /system/xbin
	fi

	echo "DO_ROOT_RET1: $DO_ROOT_RET"
	if [ "$DO_ROOT_RET" = "$ERRCODE_FAIL_REMOUNT_SYSTEM" ]; then
		## 尝试另一种姿势
		do_alter_permroot
		DO_ROOT_RET=$?
		echo "DO_ROOT_RET2: $DO_ROOT_RET"

		if [ "$DO_ROOT_RET" = "0" ]; then
			launch_kusud_at /sbin
		else
			launch_kusud_at $DEV_KINGROOT
		fi
	fi

	list_result /system
	handle_recovery_partition
}
############################################################################################################
## func: stat_ni
## example: stat_ni
stat_ni() {
	if [ -f "$MY_FILES_DIR/krni_o" ]; then
		chmod 0755 $MY_FILES_DIR/krni_o > /dev/null 2>&1
		NI_OUT=`$MY_FILES_DIR/krni_o 2>&1 | $MY_TOOLBOX grep NI:`
		print_stats "$NI_OUT"
	fi
}
############################################################################################################
## func: do_backup_files
## example: do_backup_files
do_backup_files() {
	mkdir -p $DEV_KINGROOT
	kr_set_perm 0 2000 u:object_r:system_file:s0 00755 $DEV_KINGROOT
	cat_krdem_to_path / $DEV_KINGROOT
	#cat_krbp_to_path / $DEV_KINGROOT
	cat_su_to_path / $DEV_KINGROOT
	cat_mount_to_path / $DEV_KINGROOT

	mkdir -p $BACKDIR_KING
	kr_set_perm 0 2000 u:object_r:system_file:s0 00755 $BACKDIR_KING
	cat_krdem_to_path /data $BACKDIR_KING
	#cat_krbp_to_path /data $BACKDIR_KING
	cat_su_to_path /data $BACKDIR_KING
	cat_mount_to_path /data $BACKDIR_KING

	if [ "$ROOT_MODE" != "$RM_TEMP" -a "$API_LEVEL" -ge "$REPACK_API_LEVEL" ]; then
		$DEV_KINGROOT/krdem kingroot-dev 17 $BACKDIR_KING/boot.krbak
		if [ $? -eq 1 ]; then
			print_stats "SUCC backup bootimg"
		else
			print_stats "FAIL backup bootimg"
		fi
	fi
}
############################################################################################################
## func: run_bind
## example: run_bind $XBIN_RUN_PATH /system/xbin
run_bind() {
	/system/bin/mount -o bind $1 $2
	if [ $? != 0 ]; then
		$DEV_KINGROOT/krdem kingroot-dev 23 -o bind $1 $2
	fi
}
############################################################################################################
## func: bind_files
## example: bind_files
bind_files() {
	echo "bind_files ..."
	# xbin_bind
	XBIN_RUN_PATH=$DEV_KINGROOT/xbin_bind
	cp -f -a /system/xbin $XBIN_RUN_PATH > /dev/null 2>&1

	# ku.sud
	ln -s $DEV_KINGROOT/ku.sud $XBIN_RUN_PATH/su
	kr_set_perm 0 2000 u:object_r:system_file:s0 00755 $XBIN_RUN_PATH/su

	# bind
	run_bind $XBIN_RUN_PATH /system/xbin

	cat /proc/mounts | $MY_TOOLBOX grep "/system/xbin"
}
############################################################################################################
############################################################################################################

echo "identifying ..."
id

kr_remount /system rw

kr_rmfile /data/app/com.kingroot.kinguser*.
kr_rmfile /data/dalvik-cache/*com.kingroot.kinguser*
kr_rmfile /data/dalvik-cache/*/*com.kingroot.kinguser*
kr_rmfile /data/dalvik-cache/*com.kingroot.master*
kr_rmfile /data/dalvik-cache/*/*com.kingroot.master*
kr_rmfile /data/app/com.kingroot.kinguser*
kr_rmfile /data/app/com.kingroot.master*

kr_rmfile /system/usr/iku/isu
kr_rmdir /system/usr/iku

kr_rmfile /system/xbin/krdem
kr_rmfile /system/xbin/kugote
kr_rmfile /system/xbin/ku.sud
kr_rmfile /system/xbin/start_kusud.sh
kr_rmfile /system/xbin/su
kr_rmfile /system/xbin/supolicy

kr_rmfile /system/etc/install-recovery.sh
kr_rmfile /system/etc/install-recovery.sh-ku.bak
kr_rmfile /system/etc/install_recovery.sh

kr_rmfile /system/bin/su
kr_rmfile /system/bin/rt.sh
kr_rmfile /system/bin/install-recovery.sh
kr_rmfile /system/bin/.usr/.ku
kr_rmdir /system/bin/.usr

kr_rmfile /system/app/Kinguser.apk
kr_rmfile /system/app/Kinguser/Kinguser.apk
kr_rmdir /system/app/Kinguser


cat_ddexe /system

cat_install_recovery /system

cat_debuggerd /system

cat_su_to_path /system /system/xbin

/system/xbin/ai.sud --daemon &

sleep 3

kr_ps su
kr_ps ai.sud

if [ "$IS_CLEAR_FILES" = "1" ]; then  
	echo "cleaning up ..."
	kr_rmfile $MY_FILES_DIR/*
else
	echo "NO clean up files ..."
fi

echo "[$0] finished!"

print_stats "END script"