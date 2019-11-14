#!/bin/sh
rpmbuild -v --define "_topdir $PWD" -bb ldiff.spec
rm -rf SRPMS BUILDROOT SOURCES SPECS BUILD
