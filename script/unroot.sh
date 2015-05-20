#!/system/bin/sh
bb=/data/local/tmp/busybox

if [ ! -f $bb ]; then
    bb=
fi

mount -o remount,rw /system
$bb mount -o remount,rw /system

$bb chattr -aiA /system/bin/su
$bb chattr -aiA /system/xbin/su
$bb chattr -aiA /system/xbin/supolicy
$bb chattr -aiA /system/xbin/ddexe
$bb chattr -aiA /system/xbin/ddexe_real
$bb chattr -aiA /system/etc/install-recovery.sh
$bb chattr -aiA /system/etc/install_recovery.sh
$bb chattr -aiA /system/bin/.suv
$bb chattr -aiA /system/usr/.suv
$bb chattr -aiA /system/usr/.suo
$bb chattr -aiA /system/bin/.uv
$bb chattr -aiA /system/usr/.uv
$bb chattr -aiA /system/bin/.ext/.su
$bb chattr -aiA /system/bin/.ext
$bb chattr -aiA /system/bin/.apkolr
$bb chattr -aiA /system/bin/.suo
$bb chattr -aiA /system/xbin/.apkolr
$bb chattr -aiA /system/xbin/k.sud
$bb chattr -aiA /system/xbin/ku.sud
$bb chattr -aiA /system/xbin/daemonsu
$bb chattr -aiA /system/xbin/.rgs
$bb chattr -aiA /system/xbin/su
$bb chattr -aiA /system/bin/us

/system/xbin/su --uninstall

$bb rm -f /system/bin/su
$bb rm -f /system/xbin/su
$bb rm -f /system/xbin/supolicy
$bb rm -f /system/etc/install-recovery.sh
$bb rm -f /system/etc/install_recovery.sh
$bb rm -f /system/bin/.suv
$bb rm -f /system/usr/.suv
$bb rm -f /system/usr/.suo
$bb rm -f /system/bin/.uv
$bb rm -f /system/usr/.uv
$bb rm -f /system/bin/.ext/.su
$bb rm -f /system/bin/.ext
$bb rm -f /system/bin/.apkolr
$bb rm -f /system/bin/.suo
$bb rm -f /system/xbin/.apkolr
$bb rm -f /system/xbin/k.sud
$bb rm -f /system/xbin/ku.sud
$bb rm -f /system/xbin/daemonsu
$bb rm -f /system/xbin/.rgs
$bb rm -f /system/xbin/su
$bb rm -f /system/bin/us
