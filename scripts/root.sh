#!/system/bin/sh
stop nac_server
stop nac_ue

mount -r -w -o remount /system;
/data/local/tmp/busybox mount -orw,remount /system;

mount -o remount,rw /system;
/data/local/tmp/busybox mount -o remount,rw /system;

chmod 644 /system/bin/nac_server;
chmod 644 /system/bin/nac_ue;

if [ ! "$(/data/local/tmp/busybox echo busybox)" = "busybox" ]; then
	echo not_found_busybox
	exit 0
fi

/data/local/tmp/busybox chattr -iaA /system/bin/su; rm /system/bin/su;
/data/local/tmp/busybox chattr -iaA /system/xbin/su; rm /system/xbin/su;
/data/local/tmp/busybox chattr -iaA /system/app/superuser.apk; rm /system/app/superuser.apk;
/data/local/tmp/busybox chattr -iaA /system/app/Superuser.apk; rm /system/app/Superuser.apk;
/data/local/tmp/busybox chattr -iaA /system/app/kinguser.apk; rm /system/app/kinguser.apk;
/data/local/tmp/busybox chattr -iaA /system/app/Kinguser.apk; rm /system/app/Kinguser.apk;
/data/local/tmp/busybox chattr -iaA /system/etc/install-recovery.sh; rm /system/etc/install-recovery.sh;
/data/local/tmp/busybox chattr -iaA /system/etc/install_recovery.sh; rm /system/etc/install_recovery.sh;

cat /data/local/tmp/su>/system/bin/su; chown 0.0 /system/bin/su; chmod 6755 /system/bin/su; chcon u:object_r:system_file:s0 /system/bin/su;
cat /data/local/tmp/supolicy>/system/xbin/supolicy; chown 0.0 /system/xbin/supolicy; chmod 0755 /system/xbin/supolicy; chcon u:object_r:system_file:s0 /system/xbin/supolicy
cat /data/local/tmp/Superuser.apk>/system/app/Superuser.apk; chmod 0644 /system/app/Superuser.apk;
ln -s /system/bin/su /system/xbin/su;

echo '#!/system/bin/sh
/system/bin/su --daemon &
'>/system/etc/install-recovery.sh; chmod 0755 /system/etc/install-recovery.sh; chcon u:object_r:system_file:s0 /system/etc/install-recovery.sh;
ln -s /system/etc/install-recovery.sh /system/etc/install_recovery.sh;

if [ -e "/system/bin/vold_real" ]; then
	echo found_vold_real
else
	cat /system/bin/vold > /system/bin/vold_real
fi
chown 0.0 /system/bin/vold_real; chmod 755 /system/bin/vold_real; chcon u:object_r:system_file:s0 /system/bin/vold_real;
/data/local/tmp/busybox chattr -iaA /system/bin/vold; rm /system/bin/vold
echo '#!/system/bin/sh
/system/bin/su --daemon &
/system/bin/vold_real
'>/system/bin/vold; chown 0.0 /system/bin/vold; chmod 755 /system/bin/vold; chcon u:object_r:system_file:s0 /system/bin/vold;

if [ -e "/sbin/purgeroot.sh" ]; then
	setprop ro.yulong.csroot 1
	busybox chattr -iaA /system/bin/busybox
	busybox chattr -iaA /system/xbin/busybox
	rm /system/bin/busybox
	rm /system/xbin/busybox
fi

targes=$(getprop init.svc.coolsec)
if [ "$targes" = "running" ]; then
	/system/bin/stop coolsec
	busybox chattr -iaA /system/bin/busybox
	busybox chattr -iaA /system/xbin/busybox
	rm /system/bin/busybox
	rm /system/xbin/busybox
fi

/system/bin/su --install
/system/bin/su --daemon &
/system/bin/su --daemon &
/system/bin/su --daemon &
id
