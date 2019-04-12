su binary
===

# This project is no longer maintained. Please refer to [Magisk](https://github.com/topjohnwu/Magisk) if you need it.

Note
========

* Source code is modified by CyanogenMod su, https://github.com/CyanogenMod/android_system_extras_su

* Supports android 4.3+ devices and need to use `su --daemon` or `su -d`

* Android 6.0+ requires patch boot partition


Building
========

* Download the Android Native Development Kit (NDK): https://developer.android.com/ndk/downloads/index.html

* Extract into some directory and put that in your path: 
	`export PATH=NDK_DIR:$PATH`

* In another directory clone this repo: 
	`git clone https://github.com/jpacg/su-binary`

* Change to the directory where the repo was cloned
	`cd su-binary`

* To start build process use the following
	`make` or `ndk-build NDK_PROJECT_PATH=. APP_BUILD_SCRIPT=./Android.mk NDK_APPLICATION_MK=./Application.mk`

* If all goes well you will get the compiled binary at:
	`./libs/armeabi-v7a/su`