#!/system/bin/sh
stop nac_server
stop debuggerd
stop hwnffserver
bb=/data/local/tmp/busybox

if [ ! -f $bb ] ; then
    bb=
fi

mount -o remount,rw /system
$bb mount -o remount,rw /system

$bb chattr -aiA /system/bin/su
$bb chattr -aiA /system/bin/ddexe
$bb chattr -aiA /system/bin/ddexe_real
$bb chattr -aiA /system/xbin/su
$bb chattr -aiA /system/xbin/supolicy
$bb chattr -aiA /system/etc/install-recovery.sh
$bb chattr -aiA /system/etc/install_recovery.sh

$bb rm -f /system/bin/su
$bb rm -f /system/xbin/su
$bb rm -f /system/xbin/supolicy
$bb rm -f /system/etc/install-recovery.sh
$bb rm -f /system/etc/install_recovery.sh

$bb cp /data/local/tmp/su /system/xbin/su
if $bb test ! -e /system/xbin/su ; then
    $bb cat /data/local/tmp/su > /system/xbin/su
fi

$bb cp /data/local/tmp/supolicy /system/xbin/supolicy
if $bb test ! -e /system/xbin/supolicy ; then
    $bb cat /data/local/tmp/supolicy > /system/xbin/supolicy
fi

if $bb test $(getprop init.svc.coolsec) = "running" ; then
    stop coolsec
    $bb echo -e "#!/system/bin/sh\nstop coolsec\n/system/xbin/su --daemon &" > /system/etc/install-recovery.sh
else
    $bb echo -e "#!/system/bin/sh\n/system/xbin/su --daemon &" > /system/etc/install-recovery.sh
fi

$bb chown 0.0 /system/xbin/su
$bb chown 0.0 /system/xbin/supolicy
$bb chown 0.0 /system/etc/install-recovery.sh

$bb chmod 0755 /system/xbin/su
$bb chmod 0755 /system/xbin/supolicy
$bb chmod 0755 /system/etc/install-recovery.sh

chcon u:object_r:system_file:s0 /system/xbin/su
chcon u:object_r:system_file:s0 /system/xbin/supolicy
chcon u:object_r:system_file:s0 /system/etc/install-recovery.sh

$bb ln -s /system/xbin/su /system/bin/su

$bb chattr +aiA /system/xbin/su
$bb chattr +aiA /system/xbin/supolicy
$bb chattr +aiA /system/etc/install-recovery.sh

if $bb test $(getprop ro.product.brand) = "OPPO" ; then
    $bb cp /system/etc/install-recovery.sh /system/etc/install_recovery.sh
    if $bb test ! -e /system/etc/install_recovery.sh ; then
        $bb cat /system/etc/install-recovery.sh > /system/etc/install_recovery.sh
    fi
    $bb chown 0.0 /system/etc/install_recovery.sh
    $bb chmod 0755 /system/etc/install_recovery.sh
    chcon u:object_r:system_file:s0 /system/etc/install_recovery.sh
    $bb chattr +aiA /system/etc/install_recovery.sh
fi

/system/xbin/su --install
/system/xbin/su --daemon &

id > /data/local/tmp/root.result
$bb id >> /data/local/tmp/root.result
$bb chmod 777 /data/local/tmp/root.result
