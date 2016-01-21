#!/system/bin/sh
stop nac_server
stop nac_ue

mount -r -w -o remount /system;
/data/local/tmp/busybox mount -orw,remount /system;

mount -o remount,rw /system;
/data/local/tmp/busybox mount -o remount,rw /system;

chmod 0644 /system/bin/nac_server;
chmod 0644 /system/bin/nac_ue;

if [ ! "$(/data/local/tmp/busybox echo busybox)" = "busybox" ]; then
	echo not_found_busybox
	exit 0
fi

/data/local/tmp/busybox chattr -iaA /system/app/kinguser.apk; rm /system/app/kinguser.apk
/data/local/tmp/busybox chattr -iaA /system/app/Kinguser.apk; rm /system/app/Kinguser.apk
/data/local/tmp/busybox chattr -iaA /system/app/KingUser.apk; rm /system/app/KingUser.apk
/data/local/tmp/busybox chattr -iaA /system/app/superuser.apk; rm /system/app/superuser.apk
/data/local/tmp/busybox chattr -iaA /system/app/Superuser.apk; rm /system/app/Superuser.apk
/data/local/tmp/busybox chattr -iaA /system/app/SuperUser.apk; rm /system/app/SuperUser.apk

su_manage_package="
com.noshufou.android.su
eu.chainfire.supersu
com.kingroot.kinguser
com.tencent.tcuser
com.mgyun.shua.su
com.baidu.easyroot
com.baiyi_mobile.easyroot
co.lvdou.superuser
com.qihoo.root
com.qihoo.permmgr
com.lbe.security.shuame
com.lbe.security.miui
com.lbe.security.su
com.koushikdutta.superuser
com.noshufou.android.su.elite
com.aroot.asuperuser
"

for name in $su_manage_package
do
	path=$(pm path $name)
	if [ ! "$path" = "" ]; then
		pm uninstall $name
		rm ${path#*:}
	fi
done


su_bin="
/system/bin/sysmon
/system/bin/start-ssh
/system/bin/scranton_RD
/system/bin/IPSecService
/system/bin/su
/system/xbin/su
/system/bin/.usr/.ku
/system/bin/.suv
/system/usr/.suv
/system/bin/.ext/.su
/system/bin/.ext
/system/bin/.apkolr
/system/bin/.suo
/system/bin/.uv
/system/bin/us
/system/xbin/krdem
/system/xbin/ku.sud
/system/xbin/supolicy
/system/xbin/.apkolr
/system/xbin/daemonsu
/system/xbin/.rgs
/system/xbin/kugote
/system/usr/.suo
/system/usr/.uv
/system/usr/ikm/ikmsu
/system/bin/install-recovery.sh
/system/etc/install-recovery.sh
/system/etc/install_recovery.sh
/system/etc/install-recovery.sh-ku.bak
/system/bin/ddexe-ku.bak
/system/bin/.krsh
/system/bin/rt.sh
/system/bin/sutemp
/system/xbin/sutemp
"

for name in $su_bin
do
	/data/local/tmp/busybox chattr -iaA $name
	rm $name
done


if [ -e "/system/bin/vold_real" ]; then
	echo found_vold_real
	/data/local/tmp/busybox chattr -iaA /system/bin/vold
	/data/local/tmp/busybox chattr -iaA /system/bin/vold_real
	rm /system/bin/vold
	cat /system/bin/vold_real > /system/bin/vold
	chown 0.0 /system/bin/vold
	chmod 0755 /system/bin/vold
	rm /system/bin/vold_real
fi

if [ -e "/system/bin/ddexe_real" ]; then
	echo found_ddexe_real
	/data/local/tmp/busybox chattr -iaA /system/bin/ddexe
	/data/local/tmp/busybox chattr -iaA /system/bin/ddexe_real
	rm /system/bin/ddexe
	cat /system/bin/ddexe_real > /system/bin/ddexe
	chown 0.0 /system/bin/ddexe
	chmod 0755 /system/bin/ddexe
	rm /system/bin/ddexe_real
fi

if [ -e "/system/bin/debuggerd_real" ]; then
	echo found_debuggerd_real
	/data/local/tmp/busybox chattr -iaA /system/bin/debuggerd
	/data/local/tmp/busybox chattr -iaA /system/bin/debuggerd_real
	rm /system/bin/debuggerd
	cat /system/bin/debuggerd_real > /system/bin/debuggerd
	chown 0.0 /system/bin/debuggerd
	chmod 0755 /system/bin/debuggerd
	rm /system/bin/debuggerd_real
fi
