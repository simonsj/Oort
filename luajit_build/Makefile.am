EXTRA_DIST = manifest-dist $(shell cat manifest-dist)

all-am: luajit-stamp

manifest-dist:
	find ../luajit -path ../luajit/.git -prune -o -type f -a -print > manifest-dist

luajit-stamp:
if MINGW32
	cd $(top_srcdir)/luajit && make BUILDMODE=static Q= HOST_CC="gcc -m32" CROSS=`echo $(CC) | sed -e 's/gcc//'` TARGET_SYS="Windows" clean all
else
	cd $(top_srcdir)/luajit && make BUILDMODE=static Q= clean all
endif
	touch luajit-stamp
